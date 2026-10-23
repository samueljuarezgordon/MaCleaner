import Foundation

/// Decide qué conexiones XPC acepta el demonio.
nonisolated final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Sin Team ID propio (firma ad hoc) no se puede construir un requisito fiable:
        // se rechaza todo (fail closed).
        guard let requirement = CodeSigningValidator.requirement(
            forIdentifier: HelperConstants.appBundleIdentifier
        ) else {
            return false
        }

        // Capa 1 (API pública): el sistema evalúa el requisito sobre el audit token del peer
        // en cada mensaje e invalida la conexión si deja de cumplirse.
        connection.setCodeSigningRequirement(requirement)

        // Capa 2: validación explícita audit token → SecCode → SecCodeCheckValidityWithErrors.
        // El audit token identifica al proceso de forma inequívoca (incluye pidversion), así
        // que no es vulnerable a la reutilización de PID.
        guard CodeSigningValidator.validate(connection, requirement: requirement) else {
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = PrivilegedService(clientRequirement: requirement)
        connection.resume()
        return true
    }
}
