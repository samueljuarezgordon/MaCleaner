# Cómo contribuir

## Estilo

- Swift 6 con aislamiento por defecto en `MainActor`. El dominio y el escáner son `nonisolated`; el trabajo pesado usa `@concurrent`.
- Async/await en lugar de Combine.
- Sangría de 4 espacios, `PascalCase` para tipos y `camelCase` para miembros.
- Comentarios en español, solo donde la lógica no sea evidente.
- Todos los textos visibles en español, con `LocalizedStringResource` cuando vengan del dominio.
- Lo que solo existe en una plataforma va dentro de `#if os(macOS)` / `#if os(iOS)`, también los textos (por ejemplo, «Disco de arranque» en Mac y «Almacenamiento» en iOS).

## Compilar y comprobar

Antes de enviar un cambio, compila **las dos plataformas**:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# macOS
xcodebuild -project Cleaner.xcodeproj -scheme MaCleaner -destination 'platform=macOS' build

# iOS (simulador, sin firmar)
xcodebuild -project Cleaner.xcodeproj -scheme MaCleaner \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Una compilación de macOS sin firmar (`CODE_SIGNING_ALLOWED=NO`) sirve para comprobar errores, pero **no para probar el asistente**: este exige que la app esté firmada con un Team ID.

## Añadir una categoría de limpieza

1. Añade el `case` a `CleaningCategory` en `Shared/Domain/CleaningModels.swift` y rellena `title`, `explanation`, `consequence`, `systemImage` y `module`.
2. Escribe el recolector en `Platforms/macOS/Scanner/` (o en el motor de iOS):
   - Asigna a cada elemento un `RiskLevel` y un `reason` que explique **por qué** tiene ese riesgo y **qué pasa** si se borra.
   - Usa `.moveToTrash` para todo lo que no se regenere solo.
3. Registra el *job* en `MacCleaningEngine.jobs`. El orden fija la prioridad ante duplicados.
4. Documenta la regla en `docs/CATEGORIES.md` y, si cambia lo que ve el usuario, en la guía de su plataforma (`docs/GUIA-MAC.md` o `docs/GUIA-IOS.md`).

## Añadir un método de borrado

1. Añade el `case` a `RemovalMethod` y rellena `summary`, `isRecoverable`, `progressStep` (lo que se ve mientras se elimina) y `stallHint` (qué suele retenerlo si tarda).
2. Impleméntalo en `MacCleaningEngine.remove(_:helper:)` devolviendo un `CleaningItemOutcome`. No captures errores en silencio: un fallo debe llegar como `.failed(motivo)` con un texto que entienda el usuario.
3. Si puede bloquearse sin atender a la cancelación, no hace falta nada más: `clean` ya lo espera con `abandoningOnCancel`.

## Reglas de seguridad

- Si cambias `HelperProtocol`, `PrivilegedService` o el ciclo de vida del demonio, sube `HelperConstants.helperVersion` (ver [docs/HELPER.md](docs/HELPER.md)).
- No amplíes `HelperConstants.privilegedRoots` ni `launchItemRoots` sin revisar `docs/SECURITY.md`.
- Cualquier operación nueva del demonio debe:
  - llamar a `callerIsTrusted()` y validar sus argumentos dentro del propio demonio,
  - marcar su actividad con `IdleMonitor.shared.begin()` / `end()` (dentro del `Task` si sigue trabajando tras volver),
  - tener su plazo en `HelperClient.Timeout`.
- Lo de riesgo alto nunca debe seleccionarse automáticamente.

## Probar el asistente sin la app

El demonio solo acepta clientes firmados por el mismo equipo con el identificador de la app, así que un cliente mínimo con esa firma permite comprobar de extremo a extremo que launchd lo arranca y que responde:

```swift
// xpctest.swift
import Foundation

@objc(CleanerHelperProtocol)
protocol HelperProtocol {
    func version(withReply reply: @escaping @Sendable (String) -> Void)
}

let connection = NSXPCConnection(machServiceName: "com.tuempresa.Cleaner.Helper", options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { print("error XPC: \($0)"); exit(2) } as! HelperProtocol
proxy.version { print("responde versión \($0)"); exit(0) }
DispatchQueue.main.asyncAfter(deadline: .now() + 8) { print("sin respuesta en 8 s"); exit(1) }
dispatchMain()
```

```sh
xcrun swiftc xpctest.swift -o xpctest
codesign -f -s "Apple Development: <tu certificado>" -i com.tuempresa.Cleaner xpctest
./xpctest                                    # → responde versión X

cp xpctest xpctest-adhoc && codesign -f -s - -i com.tuempresa.Cleaner xpctest-adhoc
./xpctest-adhoc                              # → error XPC (rechazado, como debe ser)
```

El demonio que se prueba es el registrado en el sistema, es decir, el de la app instalada (normalmente `/Applications/MaCleaner.app`). Para comprobar el cierre por inactividad, espera unos 2–3 minutos sin usar la app y mira `launchctl print system/com.tuempresa.Cleaner.Helper`: debe pasar a `state = not running` con `last exit code = 0`.

## Vistas previas

`Shared/Presentation/Views/PreviewSupport.swift` (solo en Debug) contiene un motor de ejemplo con datos realistas para las vistas previas de Xcode.

## Publicar una release

1. **Versión**: sube `MARKETING_VERSION` y `CURRENT_PROJECT_VERSION` en `Cleaner.xcodeproj/project.pbxproj` (todas las configuraciones) y, si cambió el demonio, `HelperConstants.helperVersion`. Actualiza la versión que citan `docs/HELPER.md` y la guía de Mac.
2. **CHANGELOG**: pasa *Sin publicar* a `## X.Y.Z — AAAA-MM-DD`.
3. **Compilar** en Release:

   ```sh
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   xcodebuild -project Cleaner.xcodeproj -scheme MaCleaner -configuration Release \
     -destination 'platform=macOS' -derivedDataPath build/mac -allowProvisioningUpdates build
   xcodebuild -project Cleaner.xcodeproj -scheme MaCleaner -configuration Release \
     -destination 'generic/platform=iOS' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build
   ```

4. **Probar** la app de Mac instalada en `/Applications` y el asistente (ver [arriba](#probar-el-asistente-sin-la-app)).
5. **Empaquetar**:

   ```sh
   V=X.Y.Z
   ditto -c -k --keepParent --sequesterRsrc build/mac/Build/Products/Release/MaCleaner.app MaCleaner-$V-macOS.zip
   mkdir -p ipa/Payload && cp -R build/ios/Build/Products/Release-iphoneos/MaCleaner.app ipa/Payload/
   (cd ipa && zip -qry ../MaCleaner-$V-iOS.ipa Payload) && rm -rf ipa
   shasum -a 256 MaCleaner-$V-macOS.zip MaCleaner-$V-iOS.ipa > SHA256SUMS.txt
   ```

   Usa `ditto` y no `zip` para el `.app` de Mac: conserva la firma. Compruébalo descomprimiendo y ejecutando `codesign --verify --deep --strict MaCleaner.app`.
6. **Publicar**: commit, etiqueta `vX.Y.Z` y release en GitHub con los tres archivos y unas notas con el formato de las anteriores (novedades por plataforma, tabla de descargas e instalación):

   ```sh
   git tag -a vX.Y.Z -m "MaCleaner X.Y.Z" && git push origin main vX.Y.Z
   gh release create vX.Y.Z --title "MaCleaner X.Y.Z" --notes-file notas.md \
     MaCleaner-$V-macOS.zip MaCleaner-$V-iOS.ipa SHA256SUMS.txt
   ```

7. **Verificar** descargando los archivos publicados y comprobando `shasum -a 256 -c SHA256SUMS.txt`.

La carpeta `build/` no se sube al repositorio.

## Pull requests

- Un cambio por PR, con descripción de qué cambia y por qué.
- Compila para macOS **y** para iOS antes de enviarlo.
- Si cambia lo que ve el usuario, actualiza la guía de su plataforma y el CHANGELOG (*Sin publicar*).
