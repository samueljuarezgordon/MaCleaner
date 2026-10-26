# Catálogo de categorías y reglas de riesgo

Cada categoría pertenece a un módulo de la barra lateral. Los textos *Qué es* y *Si lo borras* que ve el usuario están en `CleaningCategory.explanation` y `CleaningCategory.consequence`. El riesgo de cada elemento lo decide su recolector.

## macOS

### Basura del sistema

| Categoría | Dónde | Riesgo | Borrado |
|---|---|---|---|
| Cachés de usuario | `~/Library/Caches/*`, `~/Library/Containers/*/Data/Library/Caches` | Seguro. Revisar si la app está abierta, es de un gestor de paquetes o es de iCloud. | Definitivo |
| Cachés de apps | Carpetas `Cache`, `Code Cache`, `GPUCache`… en `~/Library/Application Support/<App>` | Seguro. Revisar si la app está abierta. | Definitivo |
| Cachés del sistema | `/Library/Caches/*` | Seguro | Asistente |
| Registros | `~/Library/Logs`, `/Library/Logs`, `/private/var/log` | Seguro | Definitivo / asistente |
| Adjuntos de Mail | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | Seguro | Definitivo |

### Desarrollo

| Categoría | Riesgo |
|---|---|
| DerivedData | Seguro |
| Soporte de dispositivos | Seguro si no se usa en 180 días; si no, Revisar |
| Archivos de Xcode (`.xcarchive`) | Riesgo alto (contienen los dSYM). Van a la Papelera. |
| Otros datos de Xcode | Seguro |
| **Simuladores** | Seguro: no arranca, nunca se arrancó o no se usa en 90 días. Revisar: uso reciente. Riesgo alto: encendido. |
| **Runtimes** | Seguro: no está listo o ningún simulador lo usa. Revisar: lo usan simuladores (se indica cuáles). |
| Cachés de simuladores | Seguro |
| Cachés de paquetes | Revisar (se vuelven a descargar) |
| Dependencias y compilaciones | Seguro si el proyecto no se toca en 90 días; si no, Revisar |

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

| Situación | Riesgo |
|---|---|
| Abierta ahora | Riesgo alto |
| Usada en los últimos 90 días | Riesgo alto |
| Sin uso en 90 días o sin uso registrado | Revisar |

### Inicio y rendimiento

Se leen los plist de `~/Library/LaunchAgents`, `/Library/LaunchAgents` y `/Library/LaunchDaemons` (sin `com.apple.*`). El estado se obtiene de `launchctl list`.

| Situación | Riesgo |
|---|---|
| El ejecutable ya no existe (huérfano) | Seguro |
| Desactivado (`Disabled = true`) | Seguro |
| No hay ninguna app instalada del fabricante | Revisar |
| Actualizador (`update`, `keystone`, `sparkle`…) | Revisar |
| Siempre activo (`KeepAlive`) | Revisar |
| Cualquier otro | Riesgo alto |

### Otros

| Categoría | Riesgo |
|---|---|
| Instaladores | Revisar (las actualizaciones `.ipsw` del Finder son Seguro) |
| Comprimidos | Revisar si existe la carpeta descomprimida al lado; si no, Riesgo alto |
| Restos de apps | Revisar; Riesgo alto si hay apps del mismo fabricante |
| Archivos grandes (≥ 500 MB) | Riesgo alto |
| Copias de iPhone/iPad | Riesgo alto; Revisar si tienen más de un año |
| Papelera | Seguro |

## iOS / iPadOS

### Basura del sistema

| Categoría | Regla | Riesgo | Borrado |
|---|---|---|---|
| Datos del sistema purgables | `volumeAvailableCapacityForImportantUsage − volumeAvailableCapacity` (lo que iOS considera prescindible) | Seguro | iOS los purga al pedirle MaCleaner el espacio (`PurgeableSpaceReclaimer`) |
| Caché de MaCleaner | Contenido de `cachesDirectory` y `tmp` de la propia app | Seguro | Definitivo |

### Desactivadas en la 1.1.0

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
