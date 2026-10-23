import Foundation

/// Único punto del código compartido que conoce los motores concretos de cada plataforma.
nonisolated enum CleaningEngineFactory {
    static func makeDefault() -> any CleaningEngine {
        #if os(macOS)
        MacCleaningEngine()
        #elseif os(iOS)
        IOSCleaningEngine()
        #else
        #error("Plataforma no soportada")
        #endif
    }
}
