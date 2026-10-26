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
│      HelperDiagnostics      │
└───────────────────────────────┘
```

`CleaningEngineFactory` es el único punto del código compartido que conoce los motores concretos.

## Contrato del motor

```swift
protocol CleaningEngine: Sendable {
    var supportedCategories: [CleaningCategory] { get }
    func scan(categories: Set<CleaningCategory>,
              progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary
    func clean(_ items: [ScanItem],
               progress: AsyncStream<CleaningProgress>.Continuation) async throws -> CleaningReport
}
```

- `scan` analiza solo las categorías pedidas y emite `.started`, `.finished`, `.fraction` y `.metrics` para el progreso categoría a categoría.
- `clean` elimina en el orden recibido y emite `.started(id, step:)` (también al cambiar de paso) y `.finished(id, CleaningItemOutcome)` por elemento. El motor de iOS limpia por grupos y no emite eventos; la interfaz lo trata como antes.
- Ninguno de los dos cierra el stream: lo cierra `CleanerViewModel`.
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

## Limpieza en macOS

`MacCleaningEngine.clean` procesa los elementos uno a uno:

1. Si la tarea está cancelada, marca el resto como `.skipped` y termina con un informe parcial.
2. Si el elemento ya no existe, lo da por `.alreadyGone`.
3. Antes del primer elemento `.privileged` o `.systemLaunchItem`, comprueba en 5 s que el asistente responde (`installedVersion(timeout:)`). Si no, esos elementos fallan al momento con el motivo.
4. Emite `.started` con `RemovalMethod.progressStep` y ejecuta `remove(_:helper:)` dentro de `abandoningOnCancel`.
5. Emite `.finished` con el resultado y suma los bytes al informe.

Los elementos `.privileged` se piden al asistente de uno en uno: cuesta una validación de firma por elemento, pero permite seguir el avance y ver cuál se atasca.

`abandoningOnCancel` (`Shared/Concurrency/ResumeOnce.swift`) espera una operación pero deja de esperarla en cuanto se cancela la tarea, aunque la operación no atienda a la cancelación (un `removeItem` enorme, `simctl`, una llamada XPC). La operación sigue en segundo plano y solo se abandona su resultado.

`CleanerViewModel.cleanSelection` ordena la selección de mayor a menor, consume el progreso en una tarea **no hija** (para que los últimos `.skipped` lleguen aunque se cancele) y, al terminar, quita de los resultados solo lo que se eliminó de verdad. `CleaningProgressView` muestra la cola, el elemento en curso con un cronómetro y, pasados 15 s, `RemovalMethod.stallHint`.

## Mantenimiento en macOS

`MaintenanceModel.perform` publica una `Activity` (paso, inicio, avance medido y bloqueo detectado) que pinta `ActivityPanel`. Cada paso se espera con `abandoningOnCancel`, así que **Dejar de esperar** responde al momento.

Al purgar instantáneas:

- Comprueba antes que el asistente responde.
- `watchThinning` consulta cada 3 s `tmutil listlocalsnapshots /` (cuenta las `com.apple.TimeMachine.*`), el espacio libre y `tmutil status` (`Running = 1` significa que hay una copia en curso, que retiene las instantáneas).

Cada acción tiene su `stallThreshold` y su `stallHint`. El registro de *Detalles técnicos* lleva la hora de cada línea.

## Asistente privilegiado

```
App (usuario)                         launchd                     CleanerHelper (root)
─────────────                         ───────                     ────────────────────
SMAppService.daemon.register() ──►  registra el plist
HelperClient.call(timeout:) ── mensaje al servicio Mach ──►  arranca BundleProgram
                                                               main.swift: NSXPCListener(machServiceName:)
                                                               HelperListenerDelegate valida la firma
                                                               PrivilegedService atiende y responde
                                                               IdleMonitor: 2 min sin trabajo → exit(0)
```

- `main.swift` crea el listener, lo retiene junto con su delegado (referencia débil) y se queda en `dispatchMain()`. **Sin listener, launchd relanza el proceso sin fin y los mensajes nunca reciben respuesta ni error**: fue el fallo de las versiones 1.0 a 1.1.0.
- `IdleMonitor` cuenta operaciones en curso. Los métodos de `PrivilegedService` llaman a `begin()`/`end()`; los que siguen en un `Task` (purga, servicios de inicio) terminan su actividad dentro de él.
- `HelperClient.call(timeout:)` pone un plazo a cada llamada (`HelperClient.Timeout`). Al vencer, invalida la conexión y la siguiente llamada abre otra.
- `HelperDiagnostics` comprueba en orden: Team ID de la app, presencia y firma del asistente en el bundle, ubicación, `SMAppService.status`, respuesta XPC y `launchctl print system/<label>` antes y después de la llamada. Si los arranques suben sin respuesta, el binario registrado no escucha.

## Estado de presentación

`CleanerViewModel` precalcula grupos y estadísticas una vez por análisis, no en cada `body`. Guarda la selección como `Set<ScanItem.ID>` y las exclusiones («Ignorar siempre») en `UserDefaults`. Las preferencias viven en `Preferences` y se leen con `@AppStorage` en las vistas.

## Concurrencia

- El módulo usa aislamiento por defecto en `MainActor` (Swift 6). Dominio, escáner y recolectores son `nonisolated`, y el trabajo pesado usa `@concurrent`.
- `ScanMetrics` usa `Mutex` (Synchronization) para actualizaciones pequeñas y frecuentes desde muchas tareas.
- `ProcessRunner` drena la salida del proceso en paralelo, para que un proceso con mucha salida no se bloquee con el pipe lleno.
