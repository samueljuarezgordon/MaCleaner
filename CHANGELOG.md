# Historial de cambios

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
