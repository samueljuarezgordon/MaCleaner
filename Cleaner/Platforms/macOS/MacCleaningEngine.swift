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

    /// Elimina los elementos uno a uno, en el orden recibido, informando de cada uno.
    ///
    /// Cada paso se espera con `abandoningOnCancel`: al detener la limpieza se deja de esperar
    /// al instante, aunque el paso (un borrado enorme, simctl, el asistente) siga en segundo plano.
    @concurrent
    func clean(_ items: [ScanItem], progress: AsyncStream<CleaningProgress>.Continuation) async throws -> CleaningReport {
        var reclaimed: Int64 = 0
        var trashed: Int64 = 0
        var failures: [String] = []
        var disabled = 0
        /// Si el asistente respondió a la primera comprobación (`nil` hasta que haga falta).
        var helperResponds: Bool?

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                for pending in items[index...] {
                    progress.yield(.finished(pending.id, .skipped(String(localized: "No se llegó a eliminar: limpieza detenida."))))
                }
                failures.append(String(localized: "Limpieza detenida: \(items.count - index) elementos sin tocar."))
                break
            }

            // Un elemento ya borrado por otro (p. ej. datos de una app desinstalada) no es un error.
            if item.id.hasPrefix("/"), !FileManager.default.fileExists(atPath: item.id) {
                progress.yield(.finished(item.id, .alreadyGone))
                continue
            }

            // Antes del primer elemento del sistema se comprueba que el asistente responde:
            // si no, cada llamada XPC podría quedarse esperando para siempre.
            if item.removal == .privileged || item.removal.isSystemLaunchItem {
                if helperResponds == nil {
                    progress.yield(.started(item.id, step: String(localized: "Comprobando que el asistente privilegiado responde")))
                    helperResponds = await helper.installedVersion(timeout: .seconds(5)) != nil
                }
                if helperResponds == false {
                    let message = String(localized: "el asistente privilegiado no responde. Instálalo (o reinstálalo) y apruébalo en Mantenimiento y permisos.")
                    failures.append("\(item.displayName): \(message)")
                    progress.yield(.finished(item.id, .failed(message)))
                    continue
                }
            }

            progress.yield(.started(item.id, step: String(localized: item.removal.progressStep)))
            let outcome: CleaningItemOutcome
            do {
                outcome = try await abandoningOnCancel { [helper] in
                    try await Self.remove(item, helper: helper)
                }
            } catch is CancellationError {
                outcome = .failed(String(localized: "Detenido mientras se eliminaba; macOS puede terminarlo en segundo plano."))
            } catch {
                outcome = .failed(error.localizedDescription)
            }

            switch outcome {
            case .removed: reclaimed += item.reclaimableBytes
            case .trashed: trashed += item.reclaimableBytes
            case .disabled: disabled += 1
            case .failed(let message): failures.append("\(item.displayName): \(message)")
            case .alreadyGone, .skipped: break
            }
            progress.yield(.finished(item.id, outcome))
        }

        return CleaningReport(reclaimedBytes: reclaimed, trashedBytes: trashed, failures: failures, disabledStartupItems: disabled)
    }

    @concurrent
    private static func remove(_ item: ScanItem, helper: HelperClient) async throws -> CleaningItemOutcome {
        let fileManager = FileManager.default
        switch item.removal {
        case .delete:
            try fileManager.removeItem(atPath: item.id)
            return .removed
        case .moveToTrash:
            try fileManager.trashItem(at: URL(fileURLWithPath: item.id), resultingItemURL: nil)
            return .trashed
        case .simulatorDevice(let udid):
            try check(await SimulatorCleaner.deleteDevice(udid: udid))
            return .removed
        case .simulatorRuntime(let identifier):
            try check(await SimulatorCleaner.deleteRuntime(identifier: identifier))
            return .removed
        case .uninstallApp(let relatedPaths):
            // NSWorkspace se comporta como el Finder: pide contraseña si la app es de root.
            _ = try await NSWorkspace.shared.recycle([URL(fileURLWithPath: item.id)])
            for path in relatedPaths where fileManager.fileExists(atPath: path) {
                try? fileManager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            }
            return .trashed
        case .launchAgent(let label):
            await LaunchItemStatus.bootoutUserService(label)
            try fileManager.trashItem(at: URL(fileURLWithPath: item.id), resultingItemURL: nil)
            return .disabled
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
                return .failed(String(localized: "el asistente privilegiado no responde o está desactualizado. Reinstálalo en Mantenimiento y permisos."))
            }
            return result.removed ? .disabled : .failed(result.message)
        case .privileged:
            // Rutas del sistema: el demonio vuelve a validar la firma y la lista blanca.
            // Se piden de una en una para poder seguir el avance y ver cuál se atasca.
            let result = try await helper.removeItems(atPaths: [item.id])
            if result.removed.contains(item.id) { return .removed }
            return .failed(result.failures.first ?? String(localized: "el asistente no pudo borrarlo."))
        case .photoLibrary, .evictFromDevice, .systemPurge:
            return .skipped(String(localized: "No se puede eliminar en macOS."))
        }
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

private extension RemovalMethod {
    nonisolated var isSystemLaunchItem: Bool {
        if case .systemLaunchItem = self { true } else { false }
    }
}
#endif
