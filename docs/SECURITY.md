# Seguridad

MaCleaner borra archivos, así que la seguridad se diseña en capas: el usuario revisa, la app valida y el demonio vuelve a validar.

## Principios

1. **Nada se borra sin revisión.** Toda limpieza pasa por `CleanReviewSheet`, que muestra el desglose por riesgo y los elementos de riesgo alto.
2. **Lo de riesgo alto nunca se selecciona automáticamente.**
3. **Recuperable cuando tiene sentido.** Instaladores, restos de apps, apps desinstaladas, archivos personales y agentes de usuario van a la Papelera. Solo se borra directamente lo que se regenera solo.
4. **Sin red.** La app no hace peticiones de red ni envía telemetría.

## Asistente privilegiado (`CleanerHelper`)

Demonio de launchd registrado con `SMAppService.daemon(plistName:)` y ejecutado como root. El usuario lo aprueba en Ajustes del Sistema.

### Autenticación de la conexión XPC

- **Demonio → cliente**: `HelperListenerDelegate` construye un requisito de firma con el Team ID propio y el identificador de la app.
  - Se aplica con `setCodeSigningRequirement`, que el sistema evalúa en cada mensaje.
  - Además se valida explícitamente: *audit token* → `SecCode` → `SecCodeCheckValidityWithErrors`.
  - El *audit token* incluye `pidversion`, así que la validación no es vulnerable a la reutilización de PID.
- **Cliente → demonio**: `HelperClient` exige el mismo Team ID al demonio (validación inversa).
- **Sin Team ID (firma ad hoc)** no se puede construir un requisito fiable y se rechaza todo (*fail closed*).
- `PrivilegedService` vuelve a validar al llamante justo antes de cada operación destructiva.

### Ciclo de vida

- launchd arranca el demonio bajo demanda, cuando la app se conecta a su servicio Mach.
- `main.swift` solo crea el `NSXPCListener`; toda conexión pasa por `HelperListenerDelegate` antes de exportar `PrivilegedService`.
- `IdleMonitor` lo termina tras **2 minutos sin operaciones en curso**: no queda un proceso root vivo sin necesidad. Una purga o un borrado largo cuentan como actividad hasta que responden.
- En la app, cada llamada tiene un plazo máximo (`HelperClient.Timeout`): un demonio que no contesta no deja a la app esperando para siempre.

### Operaciones expuestas

| Método | Restricción |
|---|---|
| `version` | Solo devuelve la versión. La conexión ya se validó al aceptarla. |
| `removeItems(atPaths:)` | Solo dentro de `/Library/Caches`, `/Library/Logs` y `/private/var/log`. |
| `thinLocalSnapshots` | Ejecuta exactamente `tmutil thinlocalsnapshots / 999999999999 4`. |
| `removeLaunchItem(atPath:)` | Solo un plist que sea hijo directo de `/Library/LaunchAgents` o `/Library/LaunchDaemons`. |

### Defensas frente a rutas manipuladas

- Se rechazan rutas relativas y componentes `..`.
- `resolveAllowedPath` resuelve con `realpath` el **directorio padre**, no el elemento final. Si el elemento es un enlace simbólico se borra el enlace, nunca su destino.
- `resolveLaunchItemPath` exige además `lstat` de archivo regular (sin enlaces) y extensión `.plist`.
- La etiqueta del servicio se lee del propio plist; nunca se confía en la que envíe el cliente. Las etiquetas `com.apple.*` se rechazan.

## Operaciones en el contexto del usuario

Simuladores (`simctl`), LaunchServices (`lsregister`), Quick Look (`qlmanage`) y los agentes de `~/Library/LaunchAgents` se gestionan desde la app, no desde el demonio. Así operan sobre los datos del usuario y no requieren root.

## Cómo comprobarlo

La validación se puede probar con un cliente XPC mínimo que llame a `version` (ver [CONTRIBUTING.md](../CONTRIBUTING.md#probar-el-asistente-sin-la-app)):

- Firmado con el certificado del equipo y el identificador `com.tuempresa.Cleaner`: responde.
- Con firma ad hoc (`codesign -s -`), aunque use el mismo identificador: la conexión se rechaza (`NSCocoaErrorDomain` 4097).

## Informar de una vulnerabilidad

Abre un *issue* privado (*Security advisory*) en GitHub en lugar de uno público.
