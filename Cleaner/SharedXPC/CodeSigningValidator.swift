#if os(macOS)
import Foundation
import Security

/// Validación criptográfica de la firma del proceso remoto de una conexión XPC.
///
/// La usan ambos extremos: el demonio para validar a la app (antes de cualquier operación
/// destructiva) y la app para validar al demonio (contra la suplantación del servicio Mach).
nonisolated enum CodeSigningValidator {

    /// Team ID con el que está firmado el proceso actual. Si el proceso no está firmado
    /// con un certificado de Apple (firma ad hoc) devuelve `nil` y la validación falla de
    /// forma segura: nunca se acepta un peer sin requisito.
    static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }

        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Requisito de firma (lenguaje de requisitos de Code Signing) para un peer firmado
    /// por el mismo equipo que este proceso.
    static func requirement(forIdentifier identifier: String) -> String? {
        guard let team = currentTeamIdentifier() else { return nil }
        return #"anchor apple generic and identifier "\#(identifier)" and certificate leaf[subject.OU] = "\#(team)""#
    }

    /// Extrae el `audit_token_t` de la conexión.
    ///
    /// - Important: `auditToken` es una propiedad privada de `NSXPCConnection` (se accede
    ///   por KVC). A diferencia del PID, el audit token incluye el `pidversion`, por lo que
    ///   no es vulnerable a la reutilización de PID. Como es API privada, se combina siempre
    ///   con `NSXPCConnection.setCodeSigningRequirement(_:)`, que es pública.
    static func auditToken(of connection: NSXPCConnection) -> audit_token_t? {
        guard let value = connection.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        value.getValue(&token, size: MemoryLayout<audit_token_t>.size)
        return token
    }

    /// Valida que el proceso remoto cumple `requirement`, identificándolo por su audit token.
    static func validate(_ connection: NSXPCConnection, requirement requirementText: String) -> Bool {
        guard let token = auditToken(of: connection) else { return false }

        let tokenData = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let guest else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        var error: Unmanaged<CFError>?
        let status = SecCodeCheckValidityWithErrors(
            guest,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            requirement,
            &error
        )
        error?.release()
        return status == errSecSuccess
    }
}
#endif
