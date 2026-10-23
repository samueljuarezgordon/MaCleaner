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
4. Vuelve a MaCleaner. El estado debe mostrar **«Versión 1.1.0 · responde correctamente»**.

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

| Síntoma | Causa probable | Solución |
|---|---|---|
| «El asistente no está dentro de la app» | La app se compiló sin el target `CleanerHelper`, o se ejecuta una copia incompleta. | Compila el esquema **MaCleaner** completo y ejecuta la app desde Xcode o desde el `.app` resultante. |
| Activo en Ajustes, pero «no responde» | La app se movió o renombró (por ejemplo, de `Cleaner.app` a `MaCleaner.app`), o se recompiló con otra firma. | **Reinstalar**. |
| Rechaza todas las conexiones | Firma ad hoc (*Sign to Run Locally*) sin Team ID. El demonio no puede verificar a la app y rechaza todo por diseño. | En *Signing & Capabilities*, elige tu equipo en los targets **MaCleaner** y **CleanerHelper**. |
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
- La app consulta la versión con `HelperClient.installedVersion(timeout:)`, que devuelve `nil` si el demonio no responde en 3 segundos.
