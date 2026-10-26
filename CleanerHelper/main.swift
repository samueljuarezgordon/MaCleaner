import Foundation

// launchd arranca el demonio la primera vez que la app se conecta a su servicio Mach
// (`MachServices` del launchd.plist). Si el proceso no escucha en ese servicio, launchd lo
// relanza una y otra vez y los mensajes de la app se quedan esperando para siempre.

/// `NSXPCListener.delegate` es una referencia débil: el delegado tiene que vivir aquí.
let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Sin peticiones durante un rato, el demonio termina; launchd lo relanza cuando haga falta.
IdleMonitor.shared.start()

// Atiende las conexiones hasta que launchd lo detenga o quede inactivo.
dispatchMain()
