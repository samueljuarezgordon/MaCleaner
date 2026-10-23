<p align="center">
  <img src="docs/images/icono.png" width="128" alt="Icono de MaCleaner">
</p>

<h1 align="center">MaCleaner</h1>

<p align="center">
  Limpieza profunda para macOS, iPadOS e iOS que te explica qué es cada cosa,<br>
  para qué servía y qué riesgo tiene borrarla. Nada se elimina sin que lo revises.
</p>

---

![Resumen del análisis](docs/images/resumen.png)

## Índice

- [Descargar e instalar](#descargar-e-instalar)
- [Qué hace](#qué-hace)
- [Capturas](#capturas)
- [Modelo de riesgo](#modelo-de-riesgo)
- [Requisitos](#requisitos)
- [Compilar y ejecutar](#compilar-y-ejecutar)
- [Permisos en macOS](#permisos-en-macos)
- [Atajos de teclado](#atajos-de-teclado)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Limitaciones conocidas](#limitaciones-conocidas)
- [Documentación](#documentación)

## Descargar e instalar

### macOS (Apple silicon, macOS 27 o posterior)

1. Descarga `MaCleaner-<versión>-macOS.zip` de la [última release](https://github.com/samueljuarezgordon/MaCleaner/releases/latest).
2. Descomprímelo y arrastra **MaCleaner.app** a **Aplicaciones**.
3. Ábrela. Como aún no está notarizada por Apple, la primera vez macOS dirá que no puede verificar al desarrollador:
   - Pulsa **Aceptar**.
   - Ve a **Ajustes del Sistema › Privacidad y seguridad** y, abajo, pulsa **Abrir igualmente** junto a MaCleaner.
   - Confirma con tu contraseña. Solo hace falta la primera vez.
4. Opcional: en *Mantenimiento y permisos*, concede **Acceso total al disco** e instala el **asistente privilegiado** ([guía](docs/HELPER.md)).

Para comprobar la descarga:

```sh
shasum -a 256 MaCleaner-*-macOS.zip   # compárala con SHA256SUMS.txt de la release
```

### iPhone y iPad

Todavía no hay versión en el App Store ni en TestFlight. Para instalarla en tu dispositivo, compílala desde Xcode (ver [Compilar y ejecutar](#compilar-y-ejecutar)) con tu iPhone o iPad conectado.

## Qué hace

### macOS

| Módulo | Qué analiza |
|---|---|
| **Basura del sistema** | Cachés de usuario, de apps (Chromium/Electron) y del sistema, registros y adjuntos de Mail. |
| **Desarrollo** | DerivedData, soporte de dispositivos, archivos de Xcode, cachés de Xcode, **cada simulador y cada runtime** con su tamaño y último uso, cachés de paquetes (npm, pnpm, Gradle, Cargo, Go, Maven, NuGet, Conda…) y artefactos de proyectos (`node_modules`, `Pods`, `.build`, `target`, `.next`, `.venv`…). |
| **Aplicaciones** | Apps que no usas desde hace más de 3 meses y apps de más de 1 GB contando sus datos. Se desinstalan junto con sus cachés, preferencias y contenedores. |
| **Inicio y rendimiento** | Agentes y demonios de terceros (`~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`). Detecta huérfanos, restos de apps desinstaladas, actualizadores y procesos siempre activos. |
| **Descargas** | Instaladores (`.dmg`, `.pkg`, `.ipsw`…), comprimidos y apps sin mover a Aplicaciones. |
| **Restos de apps** | Datos de apps que ya no están instaladas y copias residuales. |
| **Archivos grandes** | Archivos personales de más de 500 MB y copias de seguridad de iPhone/iPad. |
| **Papelera** | Lo que ya está en la Papelera. |

**Mantenimiento** (con estimación de lo que se libera antes de ejecutar y medición real después):

- Purgar instantáneas locales de Time Machine.
- Eliminar simuladores y runtimes inutilizables.
- Restablecer todos los simuladores.
- Reconstruir la base de datos de LaunchServices (arregla duplicados en «Abrir con»).
- Restablecer Vista rápida y miniaturas.

### iPadOS e iOS

iOS no permite que ninguna app acceda a los archivos de otras apps, las desinstale ni gestione procesos. Dentro de esos límites, MaCleaner ofrece la misma interfaz y:

- **Fototeca**: fotos duplicadas (Vision), vídeos grandes, capturas de pantalla, grabaciones de pantalla y fotos descartadas de ráfagas.
- **Consejos de espacio**: guía de lo que solo se puede hacer desde Ajustes (descargar apps sin usar, «Eliminados recientemente», Mensajes, Safari…), con el mismo formato de *qué se borra / para qué servía / qué pasa después*.

### En todas las plataformas

- Cada elemento muestra su **riesgo**, **por qué** lo tiene, **qué pasa si lo borras** y **cómo se elimina** (definitivo o recuperable).
- Hoja de **revisión antes de limpiar**: desglose por riesgo, qué es recuperable y aviso de los elementos de riesgo alto.
- **Ignorar siempre**: oculta elementos en futuros análisis (se gestiona en Ajustes).
- Selección múltiple, menú contextual, búsqueda, filtro por riesgo, orden por tamaño/nombre/fecha/riesgo y Vista rápida con la barra espaciadora (macOS).
- Todo el análisis ocurre en el dispositivo. No hay red ni telemetría.

## Capturas

| Desarrollo: simuladores y runtimes | Inicio y rendimiento | Revisión antes de limpiar |
|---|---|---|
| ![Desarrollo](docs/images/desarrollo.png) | ![Inicio](docs/images/inicio.png) | ![Revisión](docs/images/revision.png) |

## Modelo de riesgo

| Nivel | Significado | Selección por defecto |
|---|---|---|
| 🟢 **Seguro** | Se regenera solo. Borrarlo no tiene consecuencias visibles. | Sí |
| 🟠 **Revisar** | Recuperable, pero con coste: volver a descargarlo, compilar o configurar. | No |
| 🔴 **Riesgo alto** | Puede ser tu única copia o necesario para que algo funcione. | Nunca |

El catálogo completo de categorías y las reglas que asignan cada riesgo están en [docs/CATEGORIES.md](docs/CATEGORIES.md).

## Requisitos

| | Versión |
|---|---|
| Xcode | 27 o posterior |
| macOS (destino) | 27.0 |
| iOS / iPadOS (destino) | 27.0 |
| Swift | 6 (aislamiento por defecto en `MainActor`) |

## Compilar y ejecutar

1. Abre `Cleaner.xcodeproj` y selecciona el esquema **MaCleaner**.
2. En *Signing & Capabilities* elige tu equipo en los targets **MaCleaner** y **CleanerHelper**. El asistente privilegiado exige una firma con Team ID: con firma ad hoc rechaza todas las conexiones.
3. Si vas a distribuirla, sustituye el identificador de ejemplo `com.tuempresa.Cleaner` en:
   - `PRODUCT_BUNDLE_IDENTIFIER` de ambos targets,
   - `Cleaner/SharedXPC/HelperConstants.swift`,
   - `LaunchDaemons/com.tuempresa.Cleaner.Helper.plist` (nombre del archivo y `Label`/`MachServices`).
4. Elige *My Mac* o un dispositivo/simulador iOS y pulsa ⌘R.

El icono se genera desde un símbolo de SF Symbols con `Tools/make-icon.swift`:

```sh
swiftc Tools/make-icon.swift -o /tmp/make-icon
/tmp/make-icon Cleaner/Assets.xcassets/AppIcon.appiconset
```

## Permisos en macOS

| Permiso | Para qué | Cómo |
|---|---|---|
| **Acceso total al disco** | Analizar Mail, copias de iPhone, contenedores de apps y otras carpetas protegidas. | Mantenimiento y permisos › Abrir Ajustes… |
| **Asistente privilegiado** | Borrar cachés y registros del sistema, purgar instantáneas y quitar servicios de terceros de `/Library`. | Mantenimiento y permisos › Instalar (se aprueba en Ajustes › General › Ítems de inicio). Tras actualizar la app, **Reinstalar**. |

Instrucciones paso a paso, reinstalación y solución de problemas: **[docs/HELPER.md](docs/HELPER.md)**. La app también las incluye en *Mantenimiento y permisos › Cómo instalar o reinstalar el asistente*.

La app no usa el sandbox de macOS: el escáner de disco, la sonda de TCC y el registro del demonio son incompatibles con él. El diseño de seguridad del asistente está en [docs/SECURITY.md](docs/SECURITY.md).

## Atajos de teclado

| Atajo | Acción |
|---|---|
| ⌘R | Analizar / volver a analizar |
| ⌘. | Detener el análisis |
| ⌘⌫ | Revisar y limpiar |
| ⌥⌘1 | Seleccionar solo lo seguro |
| ⌥⌘2 | Seleccionar lo seguro y lo que hay que revisar |
| ⌥⌘0 | No seleccionar nada |
| ⌥⌘I | Mostrar u ocultar el panel de detalles |
| Espacio | Vista rápida del elemento resaltado |
| Doble clic | Incluir o quitar de la limpieza |
| ⌘, | Ajustes |

## Estructura del proyecto

```
Cleaner/
├── MaCleanerApp.swift            Punto de entrada, menús y escena de Ajustes
├── ContentView.swift             NavigationSplitView y barra lateral
├── Shared/
│   ├── Domain/                   Modelo: categorías, riesgo, métodos de borrado, motor
│   ├── Presentation/             CleanerViewModel, preferencias y vistas compartidas
│   └── Concurrency/              Métricas y utilidades de async/await
├── Platforms/
│   ├── macOS/
│   │   ├── Scanner/              Escáner de disco (getattrlistbulk) y recolectores
│   │   ├── Developer/            Inventario y limpieza de simuladores, reparaciones
│   │   ├── Privileges/           Acceso total al disco, instalación y cliente XPC
│   │   ├── MacCleaningEngine.swift
│   │   └── MaintenanceView.swift
│   └── iOS/                      Motor de la Fototeca y consejos de espacio
└── SharedXPC/                    Protocolo y validación compartidos con el asistente
CleanerHelper/                    Demonio privilegiado (root) con lista blanca
LaunchDaemons/                    launchd.plist del demonio (SMAppService)
Tools/make-icon.swift             Generador del icono
docs/                             Documentación técnica
```

Más detalle en [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Limitaciones conocidas

- **Último uso de las apps**: se lee de Spotlight (`kMDItemLastUsedDate`). Si Spotlight no lo tiene, se usa la última modificación de los datos de la app como indicio.
- **Ítems de inicio de sesión** (*Login Items* de `SMAppService`): no hay API pública para listar los de otras apps, así que se abren los Ajustes del Sistema.
- **Instantáneas de Time Machine**: macOS decide cuánto libera; la cifra es un máximo.
- **Apps del App Store** propiedad de root: pueden pedir la contraseña al moverse a la Papelera.
- **iOS/iPadOS**: el sandbox limita la limpieza a la Fototeca (ver arriba).

## Documentación

- [Arquitectura](docs/ARCHITECTURE.md)
- [Catálogo de categorías y reglas de riesgo](docs/CATEGORIES.md)
- [Asistente privilegiado: instalar, reinstalar y solucionar problemas](docs/HELPER.md)
- [Seguridad del asistente privilegiado](docs/SECURITY.md)
- [Cómo contribuir](CONTRIBUTING.md)
- [Historial de cambios](CHANGELOG.md)

## Licencia

Todavía no se ha elegido una licencia. Hasta entonces, todos los derechos están reservados.
