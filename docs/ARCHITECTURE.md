# Arquitectura

MaCleaner es una app SwiftUI multiplataforma (macOS, iPadOS, iOS) con un único target de app y un demonio privilegiado solo para macOS.

## Capas

```
┌─────────────────────────────────────────────────────────────┐
│ Presentación (compartida)                                   │
│ ContentView · OverviewView · ModuleDetailView · ItemInspector│
│ CleanBar / CleanReviewSheet · SettingsView                  │
│                  ▲ observa                                  │
│            CleanerViewModel (@Observable, MainActor)        │
└──────────────────┬──────────────────────────────────────────┘
                   │ any CleaningEngine
┌──────────────────▼──────────────────────────────────────────┐
│ Dominio (compartido, nonisolated)                           │
│ CleaningModule · CleaningCategory · RiskLevel               │
│ RemovalMethod · ScanItem · ScanSummary · CleaningReport     │
└───────┬──────────────────────────────────────────┬──────────┘
        │ macOS                                     │ iOS / iPadOS
┌───────▼───────────────────────┐   ┌───────────────▼──────────┐
│ MacCleaningEngine             │   │ IOSCleaningEngine        │
│  ├ MacScanContext             │   │  ├ SystemDataScanner     │
│  ├ MacScanCollectors (+Deep,  │   │  ├ PurgeableSpaceReclaimer│
│  │   +System)                 │   │  └ OwnCacheScanner       │
│                               │   └──────────────────────────┘
│  ├ BulkDirectoryScanner       │
│  ├ SimulatorInventory/Cleaner │
│  └ HelperClient ──XPC──► CleanerHelper (root)
└───────────────────────────────┘
```

`CleaningEngineFactory` es el único punto del código compartido que conoce los motores concretos.

## Contrato del motor

```swift
protocol CleaningEngine: Sendable {
    var supportedCategories: [CleaningCategory] { get }
    func scan(progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary
    func clean(_ items: [ScanItem]) async throws -> CleaningReport
}
```

- `scan` emite `.started`, `.finished` y `.metrics` para que la interfaz muestre el progreso categoría a categoría.
- Cada `ScanItem` lleva su `risk`, un `reason` en lenguaje llano y un `RemovalMethod` que decide **cómo** se elimina:

| `RemovalMethod` | Efecto | Recuperable |
|---|---|---|
| `.delete` | `FileManager.removeItem` | No |
| `.moveToTrash` | `FileManager.trashItem` | Sí |
| `.privileged` | Borrado por el demonio (lista blanca) | No |
| `.photoLibrary` | `PHAssetChangeRequest.deleteAssets` → «Eliminados recientemente» | Sí (30 días) |
| `.simulatorDevice(udid:)` | `simctl shutdown` + `simctl delete` | No |
| `.simulatorRuntime(identifier:)` | `simctl runtime delete` | No |
| `.uninstallApp(relatedPaths:)` | `NSWorkspace.recycle` de la app + datos a la Papelera | Sí |
| `.launchAgent(label:)` | `launchctl bootout gui/<uid>/<label>` + plist a la Papelera | Sí |
| `.systemLaunchItem(label:)` | `bootout` + borrado del plist por el demonio | No |

## Escaneo en macOS

`MacCleaningEngine` lanza en paralelo un *job* por grupo de categorías. El orden de la lista de jobs fija la prioridad en caso de duplicados: `removingOverlaps` descarta los elementos repetidos y los que están dentro de otro elemento, para no contar dos veces los mismos bytes.

`BulkDirectoryScanner` recorre los árboles por niveles (BFS) con `getattrlistbulk`, leyendo en una sola llamada el tamaño asignado y el tamaño privado (`ATTR_CMNEXT_PRIVATESIZE`). Así los bytes «liberables» excluyen los bloques compartidos con clones APFS. Los directorios ilegibles se ignoran; `MacScanContext.entries` marca la categoría como inaccesible cuando TCC bloquea la carpeta raíz.

Recolectores:

| Archivo | Categorías |
|---|---|
| `MacScanCollectors.swift` | Cachés, registros, DerivedData, soporte de dispositivos, archivos de Xcode, cachés de simuladores y de paquetes, descargas, restos de apps, archivos grandes y artefactos de proyectos, Papelera |
| `MacScanCollectors+Deep.swift` | Simuladores y runtimes, otros datos de Xcode, adjuntos de Mail, copias de iPhone/iPad, `ProjectArtifact` |
| `MacScanCollectors+System.swift` | Apps poco usadas o pesadas, agentes y demonios de inicio |

## Escaneo en iOS

`IOSCleaningEngine` ofrece dos categorías:

- **Datos del sistema purgables** (`SystemDataScanner`): un único elemento con lo que iOS dice que es purgable, `volumeAvailableCapacityForImportantUsage − volumeAvailableCapacity`. Su método de borrado, `.systemPurge`, ejecuta `PurgeableSpaceReclaimer` al final de la limpieza.
- **Caché de MaCleaner** (`OwnCacheScanner`): `cachesDirectory` y `tmp` de la propia app.

`PurgeableSpaceReclaimer` hace que iOS purgue pidiéndole espacio que no hay:

- Hace crecer un archivo de relleno en `tmp` con `fcntl(F_PREALLOCATE)`, o escribiendo ceros si no se admite. Pide tramos de hasta 512 MB aunque `statfs` diga que no caben: cada `ENOSPC` es una petición de purga. Con cada rechazo, el tramo se reduce a la mitad, hasta 4 MB.
- Trabaja por oleadas, de 4 como máximo. Cada una termina tras 25 s sin que iOS libere nada y borra el relleno (`defer`).
- Se detiene al cancelarse o con `abortIfRunning()`, que `MaCleanerApp` llama al pasar a segundo plano. Mientras dura, desactiva el bloqueo de pantalla.

La misma purga está en *Mantenimiento y consejos* (`StorageTipsView`), con un objetivo de bytes.

### Desactivado: Fototeca y carpetas

Con `IOSCleaningEngine.includesPhotosAndFiles = false`, estos motores no se usan, aunque siguen compilándose:

- `FilesEngine` recorre en paralelo las subcarpetas de las carpetas de `FolderAccessStore`.
- `PhotoLibraryEngine` busca vídeos grandes, capturas, grabaciones y ráfagas. Para los duplicados usa `VisualDuplicateDetector`: huellas de Vision normalizadas, agrupadas por proporción (fotos) o duración (vídeos) y comparadas por bloques con `vDSP_mmul`.
- `FeaturePrintCache` guarda las huellas entre análisis, y `BackgroundScanSession` (`BGContinuedProcessingTask`) permite que el análisis siga en segundo plano con una Live Activity.

## Estado de presentación

`CleanerViewModel` precalcula grupos y estadísticas una vez por análisis, no en cada `body`. Guarda la selección como `Set<ScanItem.ID>` y las exclusiones («Ignorar siempre») en `UserDefaults`. Las preferencias viven en `Preferences` y se leen con `@AppStorage` en las vistas.

## Concurrencia

- El módulo usa aislamiento por defecto en `MainActor` (Swift 6). Dominio, escáner y recolectores son `nonisolated`, y el trabajo pesado usa `@concurrent`.
- `ScanMetrics` usa `Mutex` (Synchronization) para actualizaciones pequeñas y frecuentes desde muchas tareas.
- `ProcessRunner` drena la salida del proceso en paralelo, para que un proceso con mucha salida no se bloquee con el pipe lleno.
