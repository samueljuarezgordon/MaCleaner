#if os(macOS)
import Foundation

nonisolated struct ProcessOutput: Sendable {
    let exitCode: Int32
    let output: String

    var succeeded: Bool { exitCode == 0 }
}

/// Ejecuta herramientas del sistema (`tmutil`, `xcrun`) con async/await.
/// Compartido entre la app (contexto de usuario) y el demonio (root).
nonisolated enum ProcessRunner {

    @concurrent
    static func run(_ executablePath: String, arguments: [String]) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // El handler se registra antes de `run()` para no perder una terminación inmediata.
        let (termination, continuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            continuation.yield(finished.terminationStatus)
            continuation.finish()
        }
        try process.run()

        // La salida se drena en paralelo: si se leyera al final, un proceso que escriba más
        // de lo que cabe en el búfer del pipe se bloquearía y nunca terminaría.
        async let output = collect(pipe.fileHandleForReading)

        var exitCode: Int32 = -1
        for await status in termination {
            exitCode = status
        }
        return ProcessOutput(exitCode: exitCode, output: String(decoding: await output, as: UTF8.self))
    }

    @concurrent
    private static func collect(_ handle: FileHandle) async -> Data {
        var data = Data()
        do {
            for try await byte in handle.bytes {
                data.append(byte)
            }
        } catch {
            // Un error de lectura solo hace perder la salida, no el código de salida.
        }
        return data
    }
}
#endif
