#if os(macOS)
import AppKit
import SwiftUI

/// Acciones de mantenimiento que no son elementos sueltos sino operaciones del sistema.
enum MaintenanceAction: String, Identifiable, CaseIterable {
    case thinSnapshots
    case deleteUnusableSimulators
    case eraseSimulators
    case rebuildLaunchServices
    case resetQuickLook

    var id: Self { self }

    /// `false` para acciones que arreglan problemas en lugar de liberar espacio.
    var freesSpace: Bool {
        switch self {
        case .thinSnapshots, .deleteUnusableSimulators, .eraseSimulators: true
        case .rebuildLaunchServices, .resetQuickLook: false
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .thinSnapshots: "Instantáneas locales de Time Machine"
        case .deleteUnusableSimulators: "Simuladores y runtimes inutilizables"
        case .eraseSimulators: "Restablecer todos los simuladores"
        case .rebuildLaunchServices: "Reconstruir la base de datos de apps"
        case .resetQuickLook: "Restablecer Vista rápida y miniaturas"
        }
    }

    var systemImage: String {
        switch self {
        case .thinSnapshots: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .deleteUnusableSimulators: "iphone.slash"
        case .eraseSimulators: "iphone.gen3.badge.exclamationmark"
        case .rebuildLaunchServices: "square.grid.3x3.square"
        case .resetQuickLook: "eye.fill"
        }
    }

    var tint: Color {
        switch self {
        case .thinSnapshots: .teal
        case .deleteUnusableSimulators: .indigo
        case .eraseSimulators: .orange
        case .rebuildLaunchServices: .blue
        case .resetQuickLook: .purple
        }
    }

    var risk: RiskLevel {
        switch self {
        case .thinSnapshots: .moderate
        case .deleteUnusableSimulators: .safe
        case .eraseSimulators: .moderate
        case .rebuildLaunchServices, .resetQuickLook: .safe
        }
    }

    var whatIsDeleted: LocalizedStringResource {
        switch self {
        case .thinSnapshots:
            "Las instantáneas que macOS guarda en tu disco entre copias de Time Machine."
        case .deleteUnusableSimulators:
            "Runtimes de simulador dañados o incompletos y simuladores cuyo runtime ya no está instalado."
        case .eraseSimulators:
            "Las apps instaladas, cuentas, fotos y ajustes de TODOS los simuladores. Los simuladores siguen existiendo, vacíos, como recién creados."
        case .rebuildLaunchServices:
            "El registro de LaunchServices: la lista de qué apps hay instaladas y qué app abre cada tipo de archivo. Se vuelve a crear al momento."
        case .resetQuickLook:
            "La caché de miniaturas y vistas previas del Finder y de Vista rápida."
        }
    }

    var purpose: LocalizedStringResource {
        switch self {
        case .thinSnapshots:
            "Te permiten recuperar archivos de las últimas horas aunque el disco de Time Machine no esté conectado."
        case .deleteUnusableSimulators:
            "Nada: no pueden arrancar. Suelen quedar tras actualizar Xcode."
        case .eraseSimulators:
            "Guardaban el estado de tus pruebas: sesiones iniciadas, datos de ejemplo, permisos concedidos…"
        case .rebuildLaunchServices:
            "Arregla apps repetidas en «Abrir con», iconos incorrectos o archivos que se abren con la app equivocada."
        case .resetQuickLook:
            "Arregla miniaturas que no se actualizan, se ven mal o vistas previas que no funcionan."
        }
    }

    /// Qué suele retener la acción cuando tarda demasiado.
    var stallHint: LocalizedStringResource {
        switch self {
        case .thinSnapshots:
            "tmutil puede tardar varios minutos con muchas instantáneas grandes, y no suelta las que usa una copia de Time Machine en curso."
        case .deleteUnusableSimulators, .eraseSimulators:
            "simctl espera a CoreSimulator. Cierra Xcode y el Simulador si están abiertos."
        case .rebuildLaunchServices:
            "lsregister vuelve a registrar todas las apps del disco; con muchas apps tarda unos minutos."
        case .resetQuickLook:
            "qlmanage espera a que el servicio de Vista rápida se reinicie."
        }
    }

    /// A partir de aquí la acción se considera lenta y se explica qué suele retenerla.
    var stallThreshold: TimeInterval {
        switch self {
        case .thinSnapshots, .rebuildLaunchServices: 60
        case .deleteUnusableSimulators, .eraseSimulators, .resetQuickLook: 30
        }
    }

    var afterwards: LocalizedStringResource {
        switch self {
        case .thinSnapshots:
            "Tus copias en el disco de Time Machine no se tocan. Solo pierdes la posibilidad de restaurar desde estas instantáneas locales; macOS creará otras nuevas."
        case .deleteUnusableSimulators:
            "Ninguna consecuencia visible. Xcode deja de mostrarlos en la lista de destinos."
        case .eraseSimulators:
            "Tendrás que volver a instalar tus apps en los simuladores y repetir la configuración de prueba."
        case .rebuildLaunchServices:
            "Durante un minuto el Finder puede ir algo lento mientras vuelve a registrar las apps. Las apps predeterminadas que elegiste se conservan."
        case .resetQuickLook:
            "El Finder volverá a generar las miniaturas la próxima vez que abras cada carpeta."
        }
    }
}

/// Estado de permisos y de las acciones de mantenimiento, con estimaciones medidas.
@MainActor
@Observable
final class MaintenanceModel {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let bytes: Int64?
    }

    struct Estimate {
        var bytes: Int64 = 0
        var entries: [Entry] = []
        /// La cifra es aproximada (lo decide macOS, no se puede medir exactamente).
        var isApproximate = false
    }

    enum Outcome {
        case success(freedBytes: Int64, message: String?)
        case failure(String)
    }

    private(set) var fullDiskAccess: FullDiskAccessStatus = .undetermined
    private(set) var helperState: HelperInstallationState = .notRegistered
    /// Versión del demonio que responde ahora mismo (`nil` si no responde o no está activo).
    private(set) var helperVersion: String?
    private(set) var isCheckingHelper = false
    private(set) var isReinstallingHelper = false
    /// Resultado del último diagnóstico del asistente (`nil` si no se ha hecho).
    private(set) var diagnostics: [HelperDiagnostics.Check]?
    private(set) var isDiagnosing = false

    /// El demonio activo es de una versión anterior a la que espera la app.
    var isHelperOutdated: Bool {
        helperState == .enabled && helperVersion.map { $0 != HelperConstants.helperVersion } ?? false
    }

    /// Activo en Ajustes, pero no responde a la app.
    var isHelperUnresponsive: Bool {
        helperState == .enabled && !isCheckingHelper && helperVersion == nil
    }
    private(set) var estimates: [MaintenanceAction: Estimate] = [:]
    private(set) var isMeasuring = false
    private(set) var running: MaintenanceAction?
    private(set) var outcomes: [MaintenanceAction: Outcome] = [:]
    private(set) var log = ""

    func refresh() {
        fullDiskAccess = FullDiskAccessProbe.check()
        helperState = HelperInstaller.state
        Task { await checkHelperVersion() }
    }

    func checkHelperVersion() async {
        guard helperState == .enabled, !isCheckingHelper else {
            if helperState != .enabled { helperVersion = nil }
            return
        }
        isCheckingHelper = true
        helperVersion = await HelperClient.shared.installedVersion()
        isCheckingHelper = false
    }

    /// Da de baja y vuelve a registrar el demonio para cargar el binario de esta versión.
    func reinstallHelper() {
        guard !isReinstallingHelper else { return }
        isReinstallingHelper = true
        Task {
            do {
                try await HelperInstaller.reinstall()
                append("Asistente reinstalado.")
            } catch {
                append("No se pudo reinstalar el asistente: \(error.localizedDescription)")
            }
            // Un demonio nuevo sin aprobar queda en «requiere aprobación».
            helperVersion = nil
            refresh()
            isReinstallingHelper = false
            if helperState == .requiresApproval {
                HelperInstaller.openApprovalSettings()
            }
        }
    }

    func diagnoseHelper() {
        guard !isDiagnosing else { return }
        isDiagnosing = true
        Task {
            diagnostics = await HelperDiagnostics.run()
            isDiagnosing = false
            refresh()
        }
    }

    func installHelper() {
        do {
            try HelperInstaller.register()
        } catch {
            append("No se pudo registrar el asistente: \(error.localizedDescription)")
        }
        refresh()
        if helperState == .requiresApproval {
            HelperInstaller.openApprovalSettings()
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = FullDiskAccessProbe.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Estimaciones

    func measure() async {
        guard !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }

        async let snapshots = Self.snapshotEstimate()
        async let simulators = Self.simulatorEstimates()
        let (unusable, erase) = await simulators
        estimates[.thinSnapshots] = await snapshots
        estimates[.deleteUnusableSimulators] = unusable
        estimates[.eraseSimulators] = erase
    }

    private static func snapshotEstimate() async -> Estimate {
        var estimate = Estimate(isApproximate: true)
        estimate.bytes = DiskUsage.current()?.purgeableBytes ?? 0
        if let output = try? await ProcessRunner.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"]) {
            estimate.entries = output.output
                .split(separator: "\n")
                .compactMap { line -> Entry? in
                    guard let match = line.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})/) else { return nil }
                    var components = DateComponents()
                    components.year = Int(match.1)
                    components.month = Int(match.2)
                    components.day = Int(match.3)
                    components.hour = Int(match.4)
                    components.minute = Int(match.5)
                    let date = Calendar.current.date(from: components)
                    return Entry(
                        id: String(line),
                        title: date?.formatted(date: .abbreviated, time: .shortened) ?? String(line),
                        subtitle: date?.formatted(.relative(presentation: .named)) ?? "",
                        bytes: nil
                    )
                }
        }
        return estimate
    }

    private static func simulatorEstimates() async -> (unusable: Estimate, erase: Estimate) {
        let inventory = await SimulatorInventory.load()
        let scanner = BulkDirectoryScanner()

        // Se mide la carpeta de datos de cada simulador (lo que borra `erase`) y la carpeta
        // completa de los inutilizables (lo que borra `delete unavailable`).
        let sizes = await withTaskGroup(of: (String, Int64, Int64).self) { group in
            for device in inventory.devices {
                group.addTask {
                    let data = await Self.size(of: device.dataPath, using: scanner)
                    let whole = device.isAvailable == false ? await Self.size(of: device.directory, using: scanner) : 0
                    return (device.udid, data, whole)
                }
            }
            var result: [String: (data: Int64, whole: Int64)] = [:]
            for await (udid, data, whole) in group {
                result[udid] = (data, whole)
            }
            return result
        }

        var unusable = Estimate()
        for device in inventory.devices where device.isAvailable == false {
            let bytes = sizes[device.udid]?.whole ?? 0
            unusable.bytes += bytes
            unusable.entries.append(Entry(
                id: device.udid,
                title: device.name,
                subtitle: "\(SimulatorInventory.runtimeName(device.runtimeIdentifier)) · \(device.availabilityError ?? "sin runtime")",
                bytes: bytes
            ))
        }
        for runtime in inventory.runtimes where !runtime.isReady {
            unusable.bytes += runtime.sizeBytes ?? 0
            unusable.entries.append(Entry(
                id: runtime.identifier,
                title: runtime.displayName,
                subtitle: "Runtime en estado «\(runtime.state ?? "desconocido")»",
                bytes: runtime.sizeBytes
            ))
        }

        var erase = Estimate()
        for device in inventory.devices where device.isAvailable != false {
            let bytes = sizes[device.udid]?.data ?? 0
            erase.bytes += bytes
            guard bytes > 0 else { continue }
            erase.entries.append(Entry(
                id: device.udid,
                title: device.name,
                subtitle: SimulatorInventory.runtimeName(device.runtimeIdentifier),
                bytes: bytes
            ))
        }
        erase.entries.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        unusable.entries.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        return (unusable, erase)
    }

    private nonisolated static func size(of path: String?, using scanner: BulkDirectoryScanner) async -> Int64 {
        guard let path else { return 0 }
        return (try? await scanner.measureTree(at: path, metrics: ScanMetrics()).reclaimableBytes) ?? 0
    }

    // MARK: - Ejecución

    /// Lo que se ve mientras corre una acción: paso, tiempo, avance y qué la retiene.
    struct Activity {
        var step: String
        let since = Date.now
        /// Avance medido (por ejemplo, instantáneas que quedan y espacio ya liberado).
        var detail: String?
        /// Algo concreto que impide avanzar, detectado mientras corre.
        var blocker: String?
    }

    private(set) var activity: Activity?
    private var runningTask: Task<Void, Never>?

    private struct HelperUnresponsive: LocalizedError {
        var errorDescription: String? {
            String(localized: "El asistente privilegiado no responde. Reinstálalo arriba y apruébalo en Ajustes del Sistema.")
        }
    }

    func perform(_ action: MaintenanceAction) {
        guard running == nil else { return }
        running = action
        outcomes[action] = nil
        let before = DiskUsage.current()?.availableBytes ?? 0
        append("— \(String(localized: action.title)): inicio")

        runningTask = Task {
            var monitor: Task<Void, Never>?
            do {
                let outputs: [ProcessOutput]
                switch action {
                case .thinSnapshots:
                    // Si el asistente no responde, la llamada XPC podría no volver nunca.
                    step("Comprobando que el asistente privilegiado responde")
                    guard await HelperClient.shared.installedVersion(timeout: .seconds(5)) != nil else {
                        throw HelperUnresponsive()
                    }
                    step("macOS está purgando las instantáneas (tmutil thinlocalsnapshots)")
                    monitor = Task { await watchThinning(freeBefore: before) }
                    outputs = [try await abandoningOnCancel { try await HelperClient.shared.thinLocalSnapshots() }]
                case .deleteUnusableSimulators:
                    step("Eliminando runtimes y simuladores inutilizables (simctl)")
                    outputs = try await abandoningOnCancel { try await SimulatorCleaner.deleteUnusableRuntimes() }
                case .eraseSimulators:
                    step("Apagando y restableciendo todos los simuladores (simctl)")
                    outputs = [try await abandoningOnCancel { try await SimulatorCleaner.eraseAllSimulators() }]
                case .rebuildLaunchServices:
                    step("Reconstruyendo la base de datos de apps (lsregister)")
                    outputs = [try await abandoningOnCancel { try await SystemRepair.rebuildLaunchServices() }]
                case .resetQuickLook:
                    step("Restableciendo Vista rápida (qlmanage)")
                    outputs = try await abandoningOnCancel { try await SystemRepair.resetQuickLook() }
                }
                outputs.forEach { append("[\($0.exitCode)] \($0.output)") }

                let after = DiskUsage.current()?.availableBytes ?? before
                if let failed = outputs.first(where: { !$0.succeeded }) {
                    outcomes[action] = .failure(failed.output.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    outcomes[action] = .success(freedBytes: max(0, after - before), message: nil)
                }
            } catch is CancellationError {
                let message = String(localized: "Dejaste de esperar. macOS puede seguir terminándolo en segundo plano.")
                outcomes[action] = .failure(message)
                append("\(String(localized: action.title)): \(message)")
            } catch {
                outcomes[action] = .failure(error.localizedDescription)
                append("\(String(localized: action.title)): \(error.localizedDescription)")
            }
            monitor?.cancel()
            if let since = activity?.since {
                append("— \(String(localized: action.title)): fin tras \(Duration.seconds(Int(Date.now.timeIntervalSince(since))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))")
            }
            activity = nil
            running = nil
            runningTask = nil
            await measure()
        }
    }

    /// Deja de esperar a la acción en curso. Lo que ya pidió al sistema no se puede deshacer.
    func stopWaiting() {
        runningTask?.cancel()
    }

    private func step(_ text: String) {
        if activity == nil {
            activity = Activity(step: text)
        } else {
            activity?.step = text
        }
        append(text)
    }

    /// Mientras se purgan las instantáneas, mide cuántas quedan y cuánto se ha liberado, y
    /// detecta una copia de Time Machine en curso, que retiene las instantáneas hasta terminar.
    private func watchThinning(freeBefore: Int64) async {
        var lastRemaining: Int?
        var wasBackingUp = false
        while !Task.isCancelled {
            async let list = try? ProcessRunner.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])
            async let status = try? ProcessRunner.run("/usr/bin/tmutil", arguments: ["status"])
            let remaining = await list.map { Self.snapshotCount(in: $0.output) }
            let isBackingUp = await status.map { $0.output.contains("Running = 1") } ?? false
            guard !Task.isCancelled else { return }

            let freed = max(0, (DiskUsage.current()?.availableBytes ?? freeBefore) - freeBefore)
            var parts: [String] = []
            if let remaining { parts.append(String(localized: "Quedan \(remaining) instantáneas")) }
            parts.append(String(localized: "\(freed.byteString) liberados"))
            activity?.detail = parts.joined(separator: " · ")
            activity?.blocker = isBackingUp
                ? String(localized: "Time Machine está haciendo una copia ahora mismo y macOS no suelta las instantáneas hasta que termine. Espera a que acabe o detenla desde el menú de Time Machine.")
                : nil

            if let remaining, remaining != lastRemaining {
                append("Quedan \(remaining) instantáneas · \(freed.byteString) liberados")
                lastRemaining = remaining
            }
            if isBackingUp != wasBackingUp {
                append(isBackingUp ? "Time Machine está haciendo una copia" : "La copia de Time Machine ha terminado")
                wasBackingUp = isBackingUp
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private nonisolated static func snapshotCount(in output: String) -> Int {
        output.split(separator: "\n").count { $0.contains("com.apple.TimeMachine.") }
    }

    private func append(_ line: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        log += "\(time)  " + line.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}

// MARK: - Vista

struct MaintenanceView: View {
    @State private var model = MaintenanceModel()
    @State private var pendingConfirmation: MaintenanceAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PermissionsCard(model: model)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mantenimiento")
                        .font(.title2.bold())
                    Text("Operaciones del sistema que liberan espacio de golpe o arreglan problemas habituales. Antes de ejecutar cada una verás qué borra, para qué servía y cuánto vas a recuperar.")
                        .foregroundStyle(.secondary)
                }

                ForEach(MaintenanceAction.allCases) { action in
                    MaintenanceCard(
                        action: action,
                        estimate: model.estimates[action],
                        isMeasuring: model.isMeasuring && action.freesSpace,
                        isRunning: model.running == action,
                        activity: model.running == action ? model.activity : nil,
                        stopWaiting: model.stopWaiting,
                        isDisabled: model.running != nil || (action == .thinSnapshots && model.helperState != .enabled),
                        disabledReason: action == .thinSnapshots && model.helperState != .enabled
                            ? "Requiere el asistente privilegiado (arriba)." : nil,
                        outcome: model.outcomes[action]
                    ) {
                        pendingConfirmation = action
                    }
                }

                if !model.log.isEmpty {
                    DisclosureGroup("Detalles técnicos") {
                        Text(model.log)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Mantenimiento y permisos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Volver a medir", systemImage: "arrow.clockwise") {
                    Task { await model.measure() }
                }
                .disabled(model.isMeasuring || model.running != nil)
            }
        }
        .task {
            model.refresh()
            await model.measure()
        }
        .task {
            // Al volver de Ajustes del Sistema se vuelve a consultar el estado.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                model.refresh()
            }
        }
        .confirmationDialog(
            pendingConfirmation.map { String(localized: $0.title) } ?? "",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            presenting: pendingConfirmation
        ) { action in
            Button(confirmTitle(for: action), role: .destructive) {
                model.perform(action)
            }
        } message: { action in
            Text("\(String(localized: action.whatIsDeleted))\n\n\(String(localized: action.afterwards))")
        }
    }

    private func confirmTitle(for action: MaintenanceAction) -> String {
        let bytes = model.estimates[action]?.bytes ?? 0
        let size = bytes > 0 ? " (\(bytes.byteString))" : ""
        return switch action {
        case .thinSnapshots: "Purgar instantáneas\(size)"
        case .deleteUnusableSimulators: "Eliminar inutilizables\(size)"
        case .eraseSimulators: "Restablecer simuladores\(size)"
        case .rebuildLaunchServices: "Reconstruir"
        case .resetQuickLook: "Restablecer"
        }
    }
}

private struct MaintenanceCard: View {
    let action: MaintenanceAction
    let estimate: MaintenanceModel.Estimate?
    let isMeasuring: Bool
    let isRunning: Bool
    let activity: MaintenanceModel.Activity?
    let stopWaiting: () -> Void
    let isDisabled: Bool
    let disabledReason: String?
    let outcome: MaintenanceModel.Outcome?
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: action.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(action.tint.gradient, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.title)
                        .font(.headline)
                    RiskBadge(risk: action.risk)
                }
                Spacer()
                if action.freesSpace {
                    EstimateLabel(estimate: estimate, isMeasuring: isMeasuring && estimate == nil)
                } else {
                    Label("No libera espacio", systemImage: "wrench.adjustable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ExplanationRow(title: "Qué se borra", systemImage: "trash.circle.fill", text: Text(action.whatIsDeleted), tint: .red)
                ExplanationRow(title: "Para qué servía", systemImage: "questionmark.circle.fill", text: Text(action.purpose), tint: .blue)
                ExplanationRow(title: "Qué pasa después", systemImage: "arrow.uturn.backward.circle.fill", text: Text(action.afterwards), tint: .orange)
            }

            if let entries = estimate?.entries, !entries.isEmpty {
                DisclosureGroup("Ver lo que se borrará (\(entries.count))") {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title)
                                    if !entry.subtitle.isEmpty {
                                        Text(entry.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let bytes = entry.bytes {
                                    Text(bytes.byteString)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    .padding(.top, 6)
                }
            }

            if let activity {
                ActivityPanel(action: action, activity: activity, stopWaiting: stopWaiting)
            }

            HStack(spacing: 12) {
                Button(action: perform) {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(buttonTitle)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(action.tint)
                .disabled(isDisabled || isRunning || (estimate.map { $0.bytes == 0 && $0.entries.isEmpty } ?? false))

                if let disabledReason {
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch outcome {
                case .success(let freed, _):
                    Label(freed > 0 && action.freesSpace ? "Liberados \(freed.byteString)" : "Hecho", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                case nil:
                    EmptyView()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private var buttonTitle: String {
        let bytes = estimate?.bytes ?? 0
        let size = bytes > 0 ? " · \(estimate?.isApproximate == true ? "hasta " : "")\(bytes.byteString)" : ""
        return switch action {
        case .thinSnapshots: "Purgar instantáneas\(size)"
        case .deleteUnusableSimulators: "Eliminar inutilizables\(size)"
        case .eraseSimulators: "Restablecer simuladores\(size)"
        case .rebuildLaunchServices: "Reconstruir"
        case .resetQuickLook: "Restablecer"
        }
    }
}

/// Paso en curso, tiempo transcurrido, avance medido y lo que retiene la acción.
private struct ActivityPanel: View {
    let action: MaintenanceAction
    let activity: MaintenanceModel.Activity
    let stopWaiting: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(activity.since))
            let isSlow = elapsed >= action.stallThreshold
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(activity.step)
                        .font(.callout)
                    Spacer()
                    Text(Duration.seconds(Int(elapsed)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(isSlow || activity.blocker != nil ? .orange : .secondary)
                        .contentTransition(.numericText())
                    Button("Dejar de esperar", action: stopWaiting)
                        .controlSize(.small)
                        .help("La app deja de esperar; lo que ya se pidió a macOS puede seguir en segundo plano")
                }
                if let detail = activity.detail {
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                if let blocker = activity.blocker {
                    Label(blocker, systemImage: "lock.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isSlow {
                    Label {
                        Text("Está tardando más de lo normal. \(String(localized: action.stallHint))")
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(action.tint.opacity(0.08), in: .rect(cornerRadius: 12))
        }
    }
}

private struct EstimateLabel: View {
    let estimate: MaintenanceModel.Estimate?
    let isMeasuring: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if isMeasuring {
                ProgressView().controlSize(.small)
                Text("Midiendo…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let estimate {
                Text(estimate.bytes > 0 ? estimate.bytes.byteString : "0 bytes")
                    .font(.title2.bold().monospacedDigit())
                Text(estimate.isApproximate ? "liberables como máximo" : "se liberarán")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionsCard: View {
    let model: MaintenanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permisos")
                .font(.title2.bold())

            PermissionRow(
                title: "Acceso total al disco",
                systemImage: "lock.shield.fill",
                explanation: "Permite analizar Mail, las copias de iPhone, los contenedores de apps y otras carpetas protegidas. MaCleaner solo lee para medir; nada sale de tu Mac.",
                isGranted: model.fullDiskAccess == .granted
            ) {
                Button("Abrir Ajustes…", action: model.openFullDiskAccessSettings)
            }

            Divider()

            PermissionRow(
                title: "Asistente privilegiado",
                systemImage: "key.fill",
                explanation: "Necesario para borrar cachés y registros del sistema, purgar instantáneas y quitar servicios de inicio de /Library. Solo acepta rutas de una lista blanca y comprueba la firma de MaCleaner en cada petición.",
                isGranted: model.helperState == .enabled && !model.isHelperOutdated && !model.isHelperUnresponsive
            ) {
                switch model.helperState {
                case .requiresApproval:
                    Button("Aprobar en Ajustes…", action: HelperInstaller.openApprovalSettings)
                case .notRegistered, .notFound:
                    Button("Instalar", action: model.installHelper)
                case .enabled:
                    Button("Reinstalar", action: model.reinstallHelper)
                        .disabled(model.isReinstallingHelper)
                }
            }

            HelperStatusDetails(model: model)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 20))
    }
}

/// Versión instalada, avisos y guía de instalación y reinstalación del asistente.
private struct HelperStatusDetails: View {
    let model: MaintenanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isReinstallingHelper {
                Label {
                    Text("Reinstalando…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
            } else if model.isHelperOutdated, let version = model.helperVersion {
                warning("Está activa la versión \(version), pero esta versión de MaCleaner necesita la \(HelperConstants.helperVersion). Pulsa «Reinstalar» para actualizarlo.")
            } else if model.isHelperUnresponsive {
                warning("Aparece activo en Ajustes, pero no responde. Suele pasar al mover o renombrar la app, o tras compilarla de nuevo con otra firma. Pulsa «Reinstalar».")
            } else if model.helperState == .enabled, let version = model.helperVersion {
                Label("Versión \(version) · responde correctamente", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.helperState == .notFound {
                warning("El asistente no está dentro de la app. Compila el esquema MaCleaner completo (incluye el target CleanerHelper) y ejecuta la app desde ahí.")
            }

            DisclosureGroup("Cómo instalar o reinstalar el asistente") {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Pulsa «Instalar» (o «Reinstalar» si ya estaba activo).")
                    step(2, "macOS abrirá Ajustes del Sistema › General › Ítems de inicio y extensiones. En «Permitir en segundo plano», activa MaCleaner. Te pedirá tu contraseña.")
                    step(3, "Vuelve a MaCleaner: el estado se actualiza solo y debe mostrar «Versión \(HelperConstants.helperVersion) · responde correctamente».")
                    Text("Reinstala cuando actualices MaCleaner, cuando la app lo pida o si las acciones del sistema fallan. Reinstalar no borra nada: solo detiene el asistente antiguo y registra el nuevo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    HStack {
                        Button("Abrir Ítems de inicio…", action: HelperInstaller.openApprovalSettings)
                        Button("Comprobar de nuevo") { model.refresh() }
                            .disabled(model.isCheckingHelper)
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)

            DiagnosticsSection(model: model)
        }
        .padding(.leading, 40)
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 18, height: 18)
                .background(.tint.opacity(0.2), in: .circle)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

/// Diagnóstico paso a paso del asistente, con un informe que se puede copiar.
private struct DiagnosticsSection: View {
    let model: MaintenanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: model.diagnoseHelper) {
                    if model.isDiagnosing {
                        Label {
                            Text("Diagnosticando…")
                        } icon: {
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Label("Diagnosticar el asistente", systemImage: "stethoscope")
                    }
                }
                .disabled(model.isDiagnosing)
                if let checks = model.diagnostics, !model.isDiagnosing {
                    Button("Copiar informe", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(HelperDiagnostics.report(checks), forType: .string)
                    }
                }
            }
            if let checks = model.diagnostics {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(checks) { check in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: symbol(for: check.status))
                                .foregroundStyle(color(for: check.status))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(check.title)
                                    .font(.callout.weight(.medium))
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
            }
        }
    }

    private func symbol(for status: HelperDiagnostics.Check.Status) -> String {
        switch status {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    private func color(for status: HelperDiagnostics.Check.Status) -> Color {
        switch status {
        case .ok: .green
        case .warning: .orange
        case .failure: .red
        case .info: .secondary
        }
    }
}

private struct PermissionRow<Action: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    let explanation: LocalizedStringResource
    let isGranted: Bool
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isGranted {
                Label("Activo", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                action
            }
        }
    }
}
#endif
