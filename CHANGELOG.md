# Historial de cambios

## Sin publicar

### Documentación
- Guías de uso nuevas, pantalla por pantalla: [Mac](docs/GUIA-MAC.md) y [iPhone y iPad](docs/GUIA-IOS.md). Cubren instalación, permisos, análisis, revisión, limpieza con su progreso, mantenimiento, ajustes y problemas frecuentes.
- README reorganizado como portada, con enlaces a cada guía.
- Arquitectura al día: contrato del motor con progreso, limpieza elemento a elemento, mantenimiento y ciclo de vida del asistente.
- Asistente: diagnóstico desde la app explicado línea a línea y cómo leer `launchctl print`.
- Seguridad: ciclo de vida del demonio y cómo comprobar que rechaza clientes no autorizados.
- Contribuir: compilar las dos plataformas, añadir métodos de borrado, probar el asistente sin la app y publicar una release.
- Catálogo de categorías: cómo se elimina cada una.

### iPhone y iPad
- La tarjeta y la barra lateral del espacio decían «Disco de arranque» y «purgables por macOS». Ahora dicen «Almacenamiento» y «purgables por iOS».

## 1.2.0 — 2026-10-26

### Mac: el asistente privilegiado por fin responde
- El demonio arrancaba y terminaba al instante sin atender a la app (`main.swift` era la plantilla de Xcode), así que nunca respondía: la purga de instantáneas y el borrado de cachés y registros del sistema se quedaban esperando para siempre. Ahora escucha en su servicio XPC.
- Todas las llamadas al asistente tienen un plazo máximo: si no contesta, la app lo dice en lugar de esperar para siempre.
- El asistente se cierra solo tras 2 minutos sin uso y macOS lo vuelve a abrir cuando hace falta.
- **Diagnosticar el asistente** (Mantenimiento y permisos): comprueba firma, bundle, ubicación, registro, launchd y respuesta, y dice en qué paso falla. El informe se puede copiar.

### Mac: progreso y bloqueos de cada eliminación
- La limpieza muestra cada elemento: en cola, en curso (con su paso y el tiempo que lleva), eliminado, en la Papelera o con el motivo del fallo. Se ven en todo momento los elementos hechos y el espacio liberado.
- Si un elemento tarda más de 15 s, se avisa y se explica qué suele retenerlo (una app abierta, una contraseña pendiente, Xcode o el Simulador abiertos, el asistente privilegiado…).
- «Detener» corta la limpieza al momento y deja sin tocar el resto, que aparece como no eliminado.
- Antes del primer elemento del sistema se comprueba que el asistente privilegiado responde: si no, esos elementos fallan enseguida con el motivo en lugar de quedarse esperando. Los elementos del sistema se borran de uno en uno para ver cuál se atasca.
- Mantenimiento: cada acción muestra el paso en curso, el tiempo transcurrido y un botón «Dejar de esperar». Al purgar instantáneas se ven las que quedan y el espacio liberado, y se avisa si una copia de Time Machine en curso las está reteniendo. Los detalles técnicos llevan hora.

## 1.1.0 — 2026-10-26

### iPhone y iPad: limpieza de la basura del sistema
- **Datos del sistema purgables** en el análisis y la limpieza normales. MaCleaner hace que iOS vacíe las cachés de otras apps y de Safari, los temporales, el streaming, los restos de actualizaciones y, con *Optimizar almacenamiento*, los originales de Fotos que ya están en iCloud. No se borra ninguna foto ni documento.
- La purga funciona de verdad: pide a iOS más espacio del que hay libre (como el truco de «alquilar una película enorme»), insiste mientras iOS libere y lo repite por oleadas. Tarda entre 1 y 5 minutos.
- **Mantenimiento y consejos**: purga manual con un objetivo (1, 5, 10 o 20 GB, o todo lo posible), consejos de Ajustes y guía paso a paso para desinstalar apps pesadas sin perder sus datos (*Offload*).
- Limpieza de la caché y los temporales de la propia app.

### iPhone y iPad: calidad de vida
- Al pulsar «Limpiar» se vuelve a la pantalla principal para ver el progreso.
- La pantalla no se bloquea durante el análisis ni la limpieza: al bloquearse, iOS suspendía la app.
- Vibración al terminar el análisis y la limpieza.
- La purga se detiene y borra su archivo temporal si la app pasa a segundo plano.

### iPhone y iPad: desactivado en esta versión
Fototeca (duplicados de fotos y vídeos, capturas, ráfagas, vídeos grandes), iCloud Drive, archivos grandes y comprimidos. En dispositivos reales su análisis no terminaba. El código sigue en el proyecto detrás de `IOSCleaningEngine.includesPhotosAndFiles`, con estas mejoras ya hechas para cuando se retome:
- Fotos y vídeos nunca se marcan solos, ninguna categoría de fotos es «segura» y todas avisan de que el borrado se sincroniza con iCloud.
- Vídeos duplicados, aunque estén recomprimidos.
- Comparación de duplicados con Accelerate, huellas guardadas entre análisis y análisis en segundo plano con Live Activity.

### Todas las plataformas
- **Qué analizar**: elige módulos y categorías desde la pantalla de inicio o Ajustes. La elección se guarda.
- Analizar un solo módulo conserva los resultados del resto.
- Los avisos de progreso del análisis ya no se pueden perder (una categoría podía parecer en curso para siempre).

### Correcciones
- iPhone/iPad: la purga fallaba con «No queda espacio en el dispositivo» y, después, apenas liberaba nada: dejaba 300 MB de margen y nunca pedía más espacio del que había, así que iOS no llegaba a purgar.

## 1.0.2 — 2026-10-23

### Correcciones
- La cuadrícula «Qué se analiza» de la pantalla de inicio ya no sale desordenada: celdas alineadas y una descripción corta por módulo.
- Listas, fechas y números en español. Antes salían en inglés («and», «5 days ago», «65.59 GB») porque el idioma base del proyecto era el inglés.

## 1.0.1 — 2026-10-23

- La app detecta la versión del asistente privilegiado en ejecución y avisa si está desactualizado o no responde.
- Nuevo botón **Reinstalar** y guía paso a paso en *Mantenimiento y permisos*.
- Mensajes de error claros cuando una limpieza necesita reinstalar el asistente.
- Nuevo manual: [docs/HELPER.md](docs/HELPER.md).
- El asistente privilegiado ahora lleva número de versión en su Info.plist.
- Primera release descargable para macOS.

## 1.0 — 2026-10-23

### Novedades
- Interfaz al estilo CleanMyMac con `NavigationSplitView`, Liquid Glass, modo claro y oscuro.
- Resumen con barra de riesgo, tarjetas por módulo y atajos de selección.
- Panel de detalles por elemento: riesgo, motivo, qué es, qué pasa si se borra y cómo se elimina.
- Hoja de revisión antes de limpiar, con opción de no usar la Papelera.
- **Aplicaciones**: apps poco usadas o pesadas, desinstaladas junto con sus datos.
- **Inicio y rendimiento**: agentes y demonios de terceros, con detección de huérfanos, actualizadores y restos.
- **Desarrollo**: cada simulador y runtime con su tamaño, último uso y riesgo; artefactos de proyectos (`Pods`, `.build`, `target`, `.venv`…).
- Adjuntos de Mail, copias de iPhone/iPad, actualizaciones `.ipsw` y más cachés de paquetes.
- **Mantenimiento**: estimación previa y medición real de lo liberado; reconstruir LaunchServices y restablecer Quick Look.
- **iOS / iPadOS**: capturas, grabaciones de pantalla y fotos de ráfagas; pantalla de consejos de espacio.
- Ajustes: selección por defecto, Papelera, elementos ignorados.
- Menú *Limpieza* con atajos de teclado, menú contextual, selección múltiple, orden, filtro y Vista rápida.
- Icono creado a partir de SF Symbols.

### Seguridad
- El asistente privilegiado (1.1.0) añade `removeLaunchItem`, limitado a plists de terceros en `/Library/LaunchAgents` y `/Library/LaunchDaemons`.
