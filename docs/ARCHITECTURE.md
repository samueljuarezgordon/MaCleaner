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
│ MacCleaningEngine             │   │ PhotoLibraryEngine       │
│  ├ MacScanContext             │   │  ├ AssetSizeResolver     │
│  ├ MacScanCollectors (+Deep,  │   │  └ VisualDuplicateDetector│
│  │   +System)                 │   └──────────────────────────┘
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

`IOSCleaningEngine` combina dos motores. Si falta el permiso de uno (Fotos o carpetas), el otro sigue funcionando y sus categorías se marcan como inaccesibles.

- `FilesEngine` recorre con `FileManager.enumerator` las carpetas guardadas en `FolderAccessStore`, activando el permiso de seguridad de cada una. Para limpiar, activa el permiso de todas mientras borra.
- `PhotoLibraryEngine` se describe a continuación.

`PurgeableSpaceReclaimer` no es una categoría sino una acción de mantenimiento (ver el README). Reserva espacio con `fcntl(F_PREALLOCATE)` en el directorio temporal de la app, sondea `volumeAvailableCapacity` cada 0,5 s y libera la reserva siempre (`defer`), también al cancelarse.

`PhotoLibraryEngine` pide acceso de lectura y escritura a la Fototeca, calcula el tamaño real de cada asset (todos sus recursos) y:

1. Agrupa duplicados con `VNGenerateImageFeaturePrintRequest` + *union-find*, y conserva la copia más pesada.
2. Filtra vídeos de más de 200 MB.
3. Usa `mediaSubtypes` para capturas y grabaciones de pantalla.
4. Busca con `includeAllBurstAssets` las fotos de ráfagas que no son la representativa ni una elegida por el usuario.

## Estado de presentación

`CleanerViewModel` precalcula grupos y estadísticas una vez por análisis, no en cada `body`. Guarda la selección como `Set<ScanItem.ID>` y las exclusiones («Ignorar siempre») en `UserDefaults`. Las preferencias viven en `Preferences` y se leen con `@AppStorage` en las vistas.

## Concurrencia

- El módulo usa aislamiento por defecto en `MainActor` (Swift 6). Dominio, escáner y recolectores son `nonisolated`, y el trabajo pesado usa `@concurrent`.
- `ScanMetrics` usa `Mutex` (Synchronization) para actualizaciones pequeñas y frecuentes desde muchas tareas.
- `ProcessRunner` drena la salida del proceso en paralelo, para que un proceso con mucha salida no se bloquee con el pipe lleno.
