# Asistente privilegiado: instalación, reinstalación y solución de problemas

El asistente (`CleanerHelper`) es un pequeño demonio que se ejecuta como root. Solo sirve para lo que la app no puede hacer con tus permisos de usuario:

- borrar cachés y registros del sistema (`/Library/Caches`, `/Library/Logs`, `/private/var/log`),
- purgar instantáneas locales de Time Machine,
- quitar servicios de inicio de terceros de `/Library/LaunchAgents` y `/Library/LaunchDaemons`.

Todo lo demás (análisis, cachés de usuario, simuladores, apps, agentes de tu usuario) funciona sin él. Su diseño de seguridad está en [SECURITY.md](SECURITY.md).

## Instalar

1. Abre MaCleaner › **Mantenimiento y permisos**.
2. En *Asistente privilegiado*, pulsa **Instalar**.
3. macOS abre **Ajustes del Sistema › General › Ítems de inicio y extensiones**. En *Permitir en segundo plano*, activa **MaCleaner** e introduce tu contraseña.
4. Vuelve a MaCleaner. El estado debe mostrar **«Versión 1.2.0 · responde correctamente»**.

## Reinstalar

Reinstala cuando:

- actualices MaCleaner y la app muestre *«Está activa la versión X, pero esta versión de MaCleaner necesita la Y»*,
- la app indique que el asistente *«no responde»*,
- una limpieza falle con *«el asistente privilegiado no responde o está desactualizado»*.

Pasos:

1. MaCleaner › **Mantenimiento y permisos** › **Reinstalar**.
2. Si macOS vuelve a pedir aprobación, actívalo de nuevo en *Ítems de inicio y extensiones*.
3. Comprueba que aparece la versión correcta. Si no, pulsa **Comprobar de nuevo**.

Reinstalar no borra nada. La app da de baja el demonio con `SMAppService.unregister()`, lo que hace que launchd detenga el proceso antiguo, y lo vuelve a registrar con `register()`. En la siguiente petición, launchd arranca el binario incluido en la versión actual de la app.

### ¿Por qué hace falta?

`SMAppService` ejecuta el binario que hay **dentro** de `MaCleaner.app` (no lo copia a otra carpeta). Aun así, si el proceso antiguo sigue en marcha, sigue respondiendo con su código anterior hasta que se detiene. Una versión antigua no conoce las operaciones nuevas.

## Comprobar el estado desde Terminal

```sh
# ¿Está cargado y en ejecución?
sudo launchctl print system/com.tuempresa.Cleaner.Helper | head -20

# Registro de ítems en segundo plano (busca MaCleaner)
sudo sfltool dumpbtm | grep -A6 -i cleaner
```

## Solución de problemas

Empieza por **Mantenimiento y permisos › Diagnosticar el asistente**. Comprueba la firma de la app, que el asistente vaya dentro y firmado por el mismo equipo, la ubicación de la app, el registro en el sistema, el estado en launchd y la respuesta XPC. Si launchd lo arranca pero no responde, lo detecta comparando los arranques antes y después de la llamada. «Copiar informe» deja el resultado en el portapapeles.

| Síntoma | Causa probable | Solución |
|---|---|---|
| «El asistente no está dentro de la app» | La app se compiló sin el target `CleanerHelper`, o se ejecuta una copia incompleta. | Compila el esquema **MaCleaner** completo y ejecuta la app desde Xcode o desde el `.app` resultante. |
| Activo en Ajustes, pero «no responde» | La app se movió o renombró (por ejemplo, de `Cleaner.app` a `MaCleaner.app`), o se recompiló con otra firma. | **Reinstalar**. |
| Rechaza todas las conexiones | Firma ad hoc (*Sign to Run Locally*) sin Team ID. El demonio no puede verificar a la app y rechaza todo por diseño. | En *Signing & Capabilities*, elige tu equipo en los targets **MaCleaner** y **CleanerHelper**. |
| «No responde» aunque se reinstale; `sudo launchctl print system/com.tuempresa.Cleaner.Helper` muestra muchas `runs` y `last exit code = 0` | El demonio arranca y termina sin escuchar en su servicio Mach: launchd lo relanza sin parar y los mensajes de la app esperan para siempre. Pasaba en las versiones 1.0 a 1.1.0, cuyo `main.swift` era la plantilla de Xcode. | Usa una versión con `main.swift` que cree el `NSXPCListener` y llame a `dispatchMain()`, y pulsa **Reinstalar**. |
| Sigue en «Requiere aprobación» | No se activó en Ajustes. | Ajustes del Sistema › General › Ítems de inicio y extensiones › activa MaCleaner. |
| Aparecen entradas duplicadas de MaCleaner en Ítems de inicio | Varias compilaciones de la app en rutas distintas (DerivedData, Aplicaciones…). | Borra las copias antiguas de la app y pulsa **Reinstalar** en la que vayas a usar. |

### Último recurso: detenerlo a mano

Si la app no consigue reinstalarlo:

```sh
sudo launchctl bootout system/com.tuempresa.Cleaner.Helper
```

Después pulsa **Instalar** en la app.

> ⚠️ `sfltool resetbtm` restablece la aprobación de **todos** los ítems en segundo plano del Mac, no solo los de MaCleaner. Úsalo solo si nada de lo anterior funciona.

## Desinstalar

Pulsa **Reinstalar** y, cuando macOS pida aprobación, déjalo desactivado en *Ítems de inicio y extensiones*. Al borrar `MaCleaner.app`, macOS elimina también el registro del demonio.

## Para desarrolladores

- La versión esperada está en `HelperConstants.helperVersion`, compartida entre la app y el demonio. **Súbela cada vez que cambies `HelperProtocol` o `PrivilegedService`**: la app detecta la diferencia y ofrece reinstalar.
- `CleanerHelper/main.swift` crea el `NSXPCListener` del servicio Mach, le asigna `HelperListenerDelegate` (guardado en una variable global: el delegado es una referencia débil) y se queda en `dispatchMain()`. Sin esto el demonio termina al arrancar.
- La app consulta la versión con `HelperClient.installedVersion(timeout:)`, que devuelve `nil` si el demonio no responde en 3 segundos.
- Todas las llamadas XPC tienen un plazo máximo (`HelperClient.Timeout`): 10 s la versión, 2 min un servicio de inicio, 10 min un borrado y 30 min la purga de instantáneas. Al vencer, la app descarta la conexión y la siguiente llamada abre otra.
- El demonio termina solo tras 2 minutos sin operaciones en curso (`IdleMonitor`). launchd lo vuelve a arrancar en la siguiente petición, así que no hay un proceso root vivo sin necesidad. Cada método de `PrivilegedService` marca su actividad con `IdleMonitor.shared.begin()`/`end()`; los que siguen trabajando en un `Task` la terminan dentro de él.
