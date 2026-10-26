# Catálogo de categorías y reglas de riesgo

Cada categoría pertenece a un módulo de la barra lateral. Los textos *Qué es* y *Si lo borras* que ve el usuario están en `CleaningCategory.explanation` y `CleaningCategory.consequence`. El riesgo de cada elemento lo decide su recolector.

En la columna *Borrado*:

- **Definitivo**: la app lo borra directamente. Solo se usa con lo que se regenera solo.
- **Papelera**: se puede recuperar hasta que vacíes la Papelera.
- **Asistente**: lo borra el asistente privilegiado, siempre de forma definitiva y solo dentro de su lista blanca.

Cómo se usan en la app: [Guía de Mac](GUIA-MAC.md) y [Guía de iPhone y iPad](GUIA-IOS.md).

## macOS

### Basura del sistema

| Categoría | Dónde | Riesgo | Borrado |
|---|---|---|---|
| Cachés de usuario | `~/Library/Caches/*`, `~/Library/Containers/*/Data/Library/Caches` | Seguro. Revisar si la app está abierta, es de un gestor de paquetes o es de iCloud. | Definitivo |
| Cachés de apps | Carpetas `Cache`, `Code Cache`, `GPUCache`… en `~/Library/Application Support/<App>` | Seguro. Revisar si la app está abierta. | Definitivo |
| Cachés del sistema | `/Library/Caches/*` | Seguro | Asistente |
| Registros de usuario | `~/Library/Logs` | Seguro | Definitivo |
| Registros del sistema | `/Library/Logs`, `/private/var/log` | Seguro | Asistente |
| Adjuntos de Mail | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | Seguro | Definitivo |

### Desarrollo

| Categoría | Riesgo | Borrado |
|---|---|---|
| DerivedData de Xcode | Seguro | Definitivo |
| Soporte de dispositivos | Seguro si no se usa en 180 días; si no, Revisar | Definitivo |
| Archivos de Xcode (`.xcarchive`) | Riesgo alto (contienen los dSYM) | Papelera |
| Otros datos de Xcode | Seguro | Definitivo |
| **Simuladores** | Seguro: no arranca, nunca se arrancó o no se usa en 90 días. Revisar: uso reciente. Riesgo alto: encendido. | `simctl shutdown` + `simctl delete` |
| **Runtimes de simulador** | Seguro: no está listo o ningún simulador lo usa. Revisar: lo usan simuladores (se indica cuáles). | `simctl runtime delete` |
| Cachés de simuladores | Seguro | Definitivo |
| Cachés de paquetes | Revisar (se vuelven a descargar) | Definitivo |
| Dependencias y compilaciones | Seguro si el proyecto no se toca en 90 días; si no, Revisar | Definitivo |

Artefactos de proyecto reconocidos (`ProjectArtifact`):

| Carpeta | Condición | Se regenera con |
|---|---|---|
| `node_modules` | — | `npm install` |
| `Pods` | `Podfile` al lado | `pod install` |
| `.build` | `Package.swift` al lado | `swift build` |
| `target` | `Cargo.toml` al lado | `cargo build` |
| `.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`, `.angular` | `package.json` al lado | `npm run build` |
| `.gradle`, `build` | `build.gradle(.kts)` o `settings.gradle(.kts)` al lado | `./gradlew build` |
| `.dart_tool` | `pubspec.yaml` al lado | `flutter pub get` |
| `.venv`, `venv`, `env` | contiene `pyvenv.cfg` | `pip install -r requirements.txt` |
| `__pycache__` | — | se regenera al ejecutar |

### Aplicaciones

Se analizan las apps de `/Applications` y `~/Applications`, también dentro de carpetas de fabricante. Se excluyen las de Apple, MaCleaner y los instaladores de macOS.

- **Último uso**: el más reciente entre `kMDItemLastUsedDate` (Spotlight) y la última modificación de los datos de la app.
- **Poco usada**: sin uso en 90 días o sin uso registrado.
- **Pesada**: 1 GB o más contando sus datos.
- **Datos asociados**: `Application Support`, `Caches`, `Containers`, `Preferences/<id>.plist`, `Saved Application State`, `HTTPStorages`, `WebKit` y `Logs`, por identificador y, si el nombre tiene 4 o más letras, por nombre.

Al limpiar, la app va a la Papelera con `NSWorkspace.recycle` (pide la contraseña si es de root) y sus datos asociados también van a la Papelera.

| Situación | Riesgo |
|---|---|
| Abierta ahora | Riesgo alto |
| Usada en los últimos 90 días | Riesgo alto |
| Sin uso en 90 días o sin uso registrado | Revisar |

### Inicio y rendimiento

Se leen los plist de `~/Library/LaunchAgents`, `/Library/LaunchAgents` y `/Library/LaunchDaemons` (sin `com.apple.*`). El estado se obtiene de `launchctl list`.

- **Agentes de tu usuario** (`~/Library/LaunchAgents`): se detienen con `launchctl bootout gui/<uid>/<label>` y su plist va a la Papelera.
- **Servicios de terceros** (`/Library`): los agentes se detienen en tu sesión; los demonios, con `bootout system/<label>` desde el asistente, que además borra el plist. La etiqueta se lee del propio plist.

| Situación | Riesgo |
|---|---|
| El ejecutable ya no existe (huérfano) | Seguro |
| Desactivado (`Disabled = true`) | Seguro |
| No hay ninguna app instalada del fabricante | Revisar |
| Actualizador (`update`, `keystone`, `sparkle`…) | Revisar |
| Siempre activo (`KeepAlive`) | Revisar |
| Cualquier otro | Riesgo alto |

### Otros

| Categoría | Riesgo | Borrado |
|---|---|---|
| Instaladores | Revisar (las actualizaciones `.ipsw` del Finder son Seguro) | Papelera |
| Archivos comprimidos | Revisar si existe la carpeta descomprimida al lado; si no, Riesgo alto | Papelera |
| Restos de apps desinstaladas | Revisar; Riesgo alto si hay apps del mismo fabricante | Papelera |
| Archivos grandes (≥ 500 MB) | Riesgo alto | Papelera |
| Copias de iPhone y iPad | Riesgo alto; Revisar si tienen más de un año | Papelera |
| Papelera | Seguro | Definitivo |

Con **No usar la Papelera** (en Ajustes o en la hoja de revisión), lo que iría a la Papelera se borra definitivamente.

## iOS / iPadOS

### Basura del sistema

| Categoría | Regla | Riesgo | Borrado |
|---|---|---|---|
| Datos del sistema purgables | `volumeAvailableCapacityForImportantUsage − volumeAvailableCapacity` (lo que iOS considera prescindible) | Seguro | iOS los purga al pedirle MaCleaner el espacio (`PurgeableSpaceReclaimer`) |
| Caché de MaCleaner | Contenido de `cachesDirectory` y `tmp` de la propia app | Seguro | Definitivo |

### Desactivadas desde la 1.1.0

Activables con `IOSCleaningEngine.includesPhotosAndFiles`. En dispositivos reales su análisis no terminaba.

**Carpetas elegidas por el usuario** (*Ajustes › Carpetas analizadas*, con bookmarks de seguridad):

| Categoría | Regla | Riesgo | Borrado |
|---|---|---|---|
| Copias locales de iCloud Drive | `isUbiquitousItem` y descargado (`.current`), ≥ 1 MB | Seguro | `evictUbiquitousItem`: sigue en iCloud |
| Comprimidos e instaladores | `.zip`, `.rar`, `.7z`, `.ipa`, `.dmg`, `.pkg`, `.iso`, `.ipsw`… | Revisar si existe la carpeta descomprimida al lado; si no, Riesgo alto | «Eliminados recientemente» |
| Archivos grandes | ≥ 100 MB y no está en iCloud | Riesgo alto | «Eliminados recientemente» |

**Fototeca.** Nada se marca solo, ni al terminar el análisis ni con «Seleccionar lo seguro» desde la vista general: borrar de la Fototeca se sincroniza con iCloud y con los demás dispositivos.

| Categoría | Regla | Riesgo |
|---|---|---|
| Fotos duplicadas | Huella de Vision a distancia ≤ 0,1 y proporción parecida. Se conserva la copia más pesada | Revisar |
| Vídeos duplicados | Misma duración (± 1 s), proporción y portada | Revisar |
| Vídeos grandes | ≥ 200 MB | Riesgo alto |
| Capturas de pantalla | `mediaSubtypes` | Revisar |
| Grabaciones de pantalla | `mediaSubtypes` | Revisar |
| Fotos de ráfagas no elegidas | Ni la representativa ni una elegida por el usuario | Revisar |

Todo lo de la Fototeca va a «Eliminados recientemente» durante 30 días.
