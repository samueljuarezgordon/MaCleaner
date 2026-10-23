# Cómo contribuir

## Estilo

- Swift 6 con aislamiento por defecto en `MainActor`. El dominio y el escáner son `nonisolated`; el trabajo pesado usa `@concurrent`.
- Async/await en lugar de Combine.
- Sangría de 4 espacios, `PascalCase` para tipos y `camelCase` para miembros.
- Comentarios en español, solo donde la lógica no sea evidente.
- Todos los textos visibles en español, con `LocalizedStringResource` cuando vengan del dominio.

## Añadir una categoría de limpieza

1. Añade el `case` a `CleaningCategory` en `Shared/Domain/CleaningModels.swift` y rellena `title`, `explanation`, `consequence`, `systemImage` y `module`.
2. Escribe el recolector en `Platforms/macOS/Scanner/` (o en el motor de iOS):
   - Asigna a cada elemento un `RiskLevel` y un `reason` que explique **por qué** tiene ese riesgo y **qué pasa** si se borra.
   - Usa `.moveToTrash` para todo lo que no se regenere solo.
3. Registra el *job* en `MacCleaningEngine.jobs`. El orden fija la prioridad ante duplicados.
4. Documenta la regla en `docs/CATEGORIES.md`.

## Reglas de seguridad

- No amplíes `HelperConstants.privilegedRoots` ni `launchItemRoots` sin revisar `docs/SECURITY.md`.
- Cualquier operación nueva del demonio debe llamar a `callerIsTrusted()` y validar sus argumentos dentro del propio demonio.
- Lo de riesgo alto nunca debe seleccionarse automáticamente.

## Vistas previas

`Shared/Presentation/Views/PreviewSupport.swift` (solo en Debug) contiene un motor de ejemplo con datos realistas para las vistas previas de Xcode.

## Pull requests

- Un cambio por PR, con descripción de qué cambia y por qué.
- Compila para macOS **y** para iOS antes de enviarlo.
