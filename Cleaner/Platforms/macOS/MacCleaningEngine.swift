#if os(macOS)
import AppKit
import Foundation

/// Motor de limpieza profunda de macOS.
///
/// Lanza en paralelo un recolector por cada grupo de categorías. Cada uno mide con
/// `BulkDirectoryScanner` y asigna un riesgo a cada elemento. Después elimina duplicados
/// y elementos anidados.
nonisolated struct MacCleaningEngine: CleaningEngine {
    private let helper = HelperClient.shared

    var supportedCategories: [CleaningCategory] {
        CleaningCategory.allCases.filter { $0.module != .photos && $0.module != .iCloudDrive && $0 != .ownAppCache }
    }

    /// Un recolector y las categorías que produce. El orden fija la prioridad en caso de
    /// duplicados: gana el primero.
    private struct Job: Sendable {
        let categories: [CleaningCategory]
        let run: @Sendable (MacScanContext) async throws -> [ScanItem]
    }

    private static let jobs: [Job] = [
        Job(categories: [.trash], run: MacScanCollectors.trash),
        Job(categories: [.installers, .compressedArchives], run: MacScanCollectors.downloads),
        Job(categories: [.appLeftovers], run: MacScanCollectors.appLeftovers),
        Job(categories: [.unusedApps, .largeApps], run: MacScanCollectors.applications),
        Job(categories: [.launchAgents, .systemLaunchItems], run: MacScanCollectors.startupItems),
        Job(categories: [.userCaches], run: MacScanCollectors.userCaches),
        Job(categories: [.appCaches], run: MacScanCollectors.appCaches),
        Job(categories: [.systemCaches], run: MacScanCollectors.systemCaches),
        Job(categories: [.userLogs], run: MacScanCollectors.userLogs),
        Job(categories: [.systemLogs], run: MacScanCollectors.systemLogs),
        Job(categories: [.xcodeDerivedData], run: MacScanCollectors.derivedData),
        Job(categories: [.xcodeDeviceSupport], run: MacScanCollectors.deviceSupport),
        Job(categories: [.xcodeArchives], run: MacScanCollectors.xcodeArchives),
        Job(categories: [.xcodeCaches], run: MacScanCollectors.xcodeCaches),
        Job(categories: [.simulatorDevices, .simulatorRuntimes], run: MacScanCollectors.simulators),
        Job(categories: [.mailAttachments], run: MacScanCollectors.mailAttachments),
        Job(categories: [.deviceBackups], run: MacScanCollectors.deviceBackups),
        Job(categories: [.simulatorCaches], run: MacScanCollectors.simulatorCaches),
        Job(categories: [.packageCaches], run: MacScanCollectors.packageCaches),
        Job(categories: [.largeFiles, .projectDependencies], run: MacScanCollectors.homeArtifacts),
    ]

    // MARK: - Escaneo

    @concurrent
    func scan(categories: Set<CleaningCategory>, progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary {
        let clock = ContinuousClock()
        let start = clock.now
        let context = MacScanContext(apps: await InstalledAppIndex.build(), progress: progress)

        var results: [Int: [ScanItem]] = [:]
        try await withThrowingTaskGroup(of: (Int, [ScanItem]).self) { group in
            // Solo se lanzan los recolectores de las categorías elegidas. Un recolector puede
            // producir varias categorías: lo que no se haya elegido se descarta.
            for (index, job) in Self.jobs.enumerated() {
                let wanted = job.categories.filter(categories.contains)
                guard !wanted.isEmpty else { continue }
                group.addTask {
                    wanted.forEach(context.started)
                    let items = try await job.run(context).filter { categories.contains($0.category) }
                    wanted.forEach { context.finished($0, items: items) }
                    return (index, items)
                }
            }
            for try await (index, items) in group {
                results[index] = items
            }
        }

        let ordered = Self.jobs.indices.flatMap { results[$0] ?? [] }
        var inaccessible = context.inaccessibleCategories.intersection(categories)
        if inaccessible.contains(.installers) { inaccessible.insert(.compressedArchives) }
        if inaccessible.contains(.largeFiles) { inaccessible.insert(.projectDependencies) }
        if inaccessible.contains(.simulatorDevices) { inaccessible.insert(.simulatorRuntimes) }
        if inaccessible.contains(.unusedApps) { inaccessible.insert(.largeApps) }
        inaccessible.formIntersection(categories)

        return ScanSummary(
            items: Self.removingOverlaps(ordered).sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            entriesVisited: context.metrics.snapshot.entriesVisited,
            duration: clock.now - start,
            inaccessibleCategories: inaccessible
        )
    }

    /// Quita duplicados (gana el primero) y elementos contenidos dentro de otro elemento,
    /// para no contar dos veces los mismos bytes ni intentar borrar algo ya borrado.
    static func removingOverlaps(_ items: [ScanItem]) -> [ScanItem] {
        var unique: [String: ScanItem] = [:]
        for item in items where unique[item.id] == nil {
            unique[item.id] = item
        }
        return unique.values.filter { item in
            var parent = (item.id as NSString).deletingLastPathComponent
            while parent.count > 1 {
                if unique[parent] != nil { return false }
                parent = (parent as NSString).deletingLastPathComponent
            }
            return true
        }
    }

    // MARK: - Limpieza

    @concurrent
    func clean(_ items: [ScanItem]) async throws -> CleaningReport {
        var reclaimed: Int64 = 0
        var trashed: Int64 = 0
        var failures: [String] = []
        var disabled = 0
        let fileManager = FileManager.default

        for item in items {
            try Task.checkCancellation()
            // Un elemento ya borrado por otro (p. ej. datos de una app desinstalada) no es un error.
            if item.id.hasPrefix("/"), !fileManager.fileExists(atPath: item.id) { continue }
            do {
                switch item.removal {
                case .delete:
                    try fileManager.removeItem(atPath: item.id)
                    reclaimed += item.reclaimableBytes
                case .moveToTrash:
                    try fileManager.trashItem(at: URL(fileURLWithPath: item.id), resultingItemURL: nil)
                    trashed += item.reclaimableBytes
                case .simulatorDevice(let udid):
                    try Self.check(await SimulatorCleaner.deleteDevice(udid: udid))
                    reclaimed += item.reclaimableBytes
                case .simulatorRuntime(let identifier):
                    try Self.check(await SimulatorCleaner.deleteRuntime(identifier: identifier))
                    reclaimed += item.reclaimableBytes
                case .uninstallApp(let relatedPaths):
                    // NSWorkspace se comporta como el Finder: pide contraseña si la app es de root.
                    _ = try await NSWorkspace.shared.recycle([URL(fileURLWithPath: item.id)])
                    for path in relatedPaths where fileManager.fileExists(atPath: path) {
                        try? fileManager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                    }
                    trashed += item.reclaimableBytes
                case .launchAgent(let label):
                    await LaunchItemStatus.bootoutUserService(label)
                    try fileManager.trashItem(at: URL(fileURLWithPath: item.id), resultingItemURL: nil)
                    disabled += 1
                case .systemLaunchItem(let label):
                    // Los agentes de /Library se cargan en la sesión del usuario: se detienen aquí.
                    if item.id.hasPrefix("/Library/LaunchAgents/") {
                        await LaunchItemStatus.bootoutUserService(label)
                    }
                    let result: (removed: Bool, message: String)
                    do {
                        result = try await helper.removeLaunchItem(atPath: item.id)
                    } catch {
                        // Un asistente 1.0 no conoce esta operación: XPC devuelve un error genérico.
                        failures.append("\(item.displayName): el asistente privilegiado no responde o está desactualizado. Reinstálalo en Mantenimiento y permisos.")
                        continue
                    }
                    if result.removed {
                        disabled += 1
                    } else {
                        failures.append("\(item.displayName): \(result.message)")
                    }
                case .privileged, .photoLibrary, .evictFromDevice:
                    continue
                }
            } catch {
                failures.append("\(item.displayName): \(error.localizedDescription)")
            }
        }

        // Rutas del sistema: el demonio vuelve a validar la firma y la lista blanca.
        let privileged = items.filter { $0.removal == .privileged }
        if !privileged.isEmpty {
            do {
                let result = try await helper.removeItems(atPaths: privileged.map(\.id))
                let removed = Set(result.removed)
                reclaimed += privileged.filter { removed.contains($0.id) }.reduce(0) { $0 + $1.reclaimableBytes }
                failures += result.failures
            } catch {
                failures.append("Elementos del sistema: instala (o reinstala) y aprueba el asistente privilegiado en Mantenimiento y permisos (\(error.localizedDescription)).")
            }
        }

        return CleaningReport(reclaimedBytes: reclaimed, trashedBytes: trashed, failures: failures, disabledStartupItems: disabled)
    }

    private struct CommandFailed: LocalizedError {
        let output: ProcessOutput
        var errorDescription: String? {
            let message = output.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "simctl terminó con el código \(output.exitCode)" : message
        }
    }

    private static func check(_ output: ProcessOutput) throws {
        guard output.succeeded else { throw CommandFailed(output: output) }
    }
}
#endif
