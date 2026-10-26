# Guía de uso: MaCleaner para Mac

Todo lo que hace la app de Mac, pantalla por pantalla: cómo instalarla, cómo analizar y limpiar con seguridad, qué hace cada herramienta de mantenimiento y qué hacer cuando algo no va bien.

> ¿Buscas la versión de iPhone y iPad? Está en [GUIA-IOS.md](GUIA-IOS.md).

## Índice

1. [Requisitos](#1-requisitos)
2. [Instalar y actualizar](#2-instalar-y-actualizar)
3. [Primeros pasos: permisos](#3-primeros-pasos-permisos)
4. [La ventana principal](#4-la-ventana-principal)
5. [Elegir qué analizar](#5-elegir-qué-analizar)
6. [Analizar](#6-analizar)
7. [Revisar los resultados](#7-revisar-los-resultados)
8. [Limpiar](#8-limpiar)
9. [Mantenimiento](#9-mantenimiento)
10. [Ajustes](#10-ajustes)
11. [Atajos de teclado](#11-atajos-de-teclado)
12. [Qué no hace MaCleaner](#12-qué-no-hace-macleaner)
13. [Problemas frecuentes](#13-problemas-frecuentes)

---

## 1. Requisitos

| | |
|---|---|
| Mac | Con Apple silicon |
| Sistema | macOS 27 o posterior |
| Espacio | Unos 10 MB para la app |
| Opcional | Contraseña de administrador para aprobar el asistente privilegiado |

MaCleaner no necesita conexión a internet: no envía nada a ningún servidor.

## 2. Instalar y actualizar

### Instalar

1. Descarga `MaCleaner-<versión>-macOS.zip` de la [última release](https://github.com/samueljuarezgordon/MaCleaner/releases/latest).
2. Haz doble clic en el ZIP y arrastra **MaCleaner.app** a **Aplicaciones**.
3. Ábrela. La app está firmada, pero todavía **no está notarizada por Apple**, así que la primera vez macOS dirá que no puede verificarla:
   1. Pulsa **Aceptar**.
   2. Abre **Ajustes del Sistema › Privacidad y seguridad**, baja hasta *Seguridad* y pulsa **Abrir igualmente** junto a MaCleaner.
   3. Confirma con tu contraseña. Solo se hace una vez.

#### Comprobar la descarga (opcional)

Cada release incluye `SHA256SUMS.txt`. En Terminal, desde la carpeta de descargas:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

Debe decir `OK` junto al ZIP.

### Actualizar

1. Cierra MaCleaner (⌘Q).
2. Sustituye `MaCleaner.app` en Aplicaciones por la nueva.
3. Ábrela y entra en **Mantenimiento y permisos**. Si el asistente privilegiado muestra un aviso, pulsa **Reinstalar** (ver [Asistente privilegiado](#asistente-privilegiado)).

> Ten **una sola copia** de MaCleaner. Si hay varias (en Descargas, en el escritorio, en una carpeta de compilación de Xcode…), macOS puede registrar el asistente de otra copia.

### Desinstalar

1. En **Mantenimiento y permisos**, pulsa **Reinstalar** y, cuando macOS pida aprobación, déjalo **desactivado** en *Ítems de inicio y extensiones*. Así el asistente deja de estar autorizado.
2. Lleva `MaCleaner.app` a la Papelera. macOS elimina también el registro del asistente.
3. Opcional: borra sus preferencias con `defaults delete com.tuempresa.Cleaner`.

## 3. Primeros pasos: permisos

MaCleaner funciona sin permisos especiales, pero con dos de ellos el análisis y la limpieza son completos. Ambos se gestionan en **Mantenimiento y permisos** (barra lateral, sección *Herramientas*).

| Permiso | Sin él | Con él |
|---|---|---|
| **Acceso total al disco** | No se pueden medir Mail, las copias de iPhone/iPad, los contenedores de apps ni otras carpetas protegidas. Esas categorías salen como *«Hay zonas que no se pudieron analizar»*. | Análisis completo. MaCleaner solo **lee** para medir. |
| **Asistente privilegiado** | No se pueden borrar cachés y registros del sistema, purgar instantáneas de Time Machine ni quitar servicios de inicio de `/Library`. | Todo lo anterior, con las garantías descritas en [SECURITY.md](SECURITY.md). |

### Acceso total al disco

1. En *Permisos*, pulsa **Abrir Ajustes…** junto a *Acceso total al disco*.
2. Activa **MaCleaner** en la lista. Si no aparece, pulsa **+** y elígela en Aplicaciones.
3. Vuelve a MaCleaner: la fila se marca como **Activo** sola.

### Asistente privilegiado

Es un pequeño proceso que se ejecuta como administrador (root) solo para las tres operaciones de la tabla. Rechaza cualquier petición que no venga de MaCleaner firmada por el mismo equipo y solo borra dentro de una lista cerrada de carpetas.

1. En *Asistente privilegiado*, pulsa **Instalar**.
2. macOS abre **Ajustes del Sistema › General › Ítems de inicio y extensiones**. En *Permitir en segundo plano*, activa **MaCleaner** e introduce tu contraseña.
3. Vuelve a MaCleaner. Debe aparecer **«Versión X · responde correctamente»**.

Qué significa cada estado de la tarjeta:

| Lo que ves | Qué pasa | Qué hacer |
|---|---|---|
| **Activo** y «Versión X · responde correctamente» | Todo bien. | Nada. |
| Botón **Instalar** | No está registrado. | Pulsa **Instalar**. |
| Botón **Aprobar en Ajustes…** | Registrado, pendiente de tu aprobación. | Actívalo en *Ítems de inicio y extensiones*. |
| «Está activa la versión X, pero esta versión de MaCleaner necesita la Y» | Sigue en marcha el asistente de una versión anterior. | **Reinstalar**. |
| «Aparece activo en Ajustes, pero no responde» | Está aprobado, pero no contesta a la app. | **Reinstalar**. Si persiste, **Diagnosticar el asistente**. |

No hace falta dejarlo funcionando: se cierra solo tras 2 minutos sin uso y macOS lo vuelve a abrir cuando la app lo necesita.

#### Diagnosticar el asistente

Debajo de la tarjeta, **Diagnosticar el asistente** comprueba la cadena entera y dice en qué punto falla:

| Comprobación | Qué mira | Si falla |
|---|---|---|
| Firma de la app | Que MaCleaner esté firmada con un Team ID. | Una compilación con firma ad hoc nunca podrá usar el asistente: hay que firmarla con un equipo. |
| Asistente dentro de la app | Que `CleanerHelper` y su plist de launchd estén en el bundle y firmados por el mismo equipo que la app. | Copia incompleta o firmada por otro equipo. Vuelve a descargar o compilar la app completa. |
| Ubicación de la app | Si se ejecuta desde Aplicaciones. | Aviso: con varias copias, borra las que no uses y reinstala en la buena. |
| Registro en el sistema | El estado de `SMAppService`. | Instalar o aprobar en Ajustes. |
| Respuesta del asistente | Que conteste en 5 s y con la versión que espera la app. | Reinstalar. |
| Proceso en launchd | Estado, número de arranques y última salida. Compara los arranques antes y después de llamar. | Si launchd lo arranca pero no responde, el binario registrado no atiende: reinstala con la versión actual. |

**Copiar informe** deja el resultado en el portapapeles para pegarlo en una incidencia. Más detalle en [HELPER.md](HELPER.md).

## 4. La ventana principal

```
┌──────────────────┬──────────────────────────────────────────────┐
│ Análisis         │                                              │
│ inteligente      │   Pantalla principal o detalle del módulo   │
│                  │                                              │
│ LIMPIEZA         │                                              │
│  Basura del sist.│                                              │
│  Desarrollo      │                                              │
│  Aplicaciones    │                                              │
│  …               │                                              │
│                  │                                              │
│ HERRAMIENTAS     │                                              │
│  Mantenimiento y │                                              │
│  permisos        │                                              │
│                  ├──────────────────────────────────────────────┤
│ Disco de arranque│   Barra de limpieza (al seleccionar algo)   │
└──────────────────┴──────────────────────────────────────────────┘
```

- **Análisis inteligente**: pantalla de inicio. Antes de analizar muestra el uso del disco y *Qué analizar*; durante el análisis, el progreso; después, el resumen.
- **Limpieza**: un módulo por grupo de categorías. Cada uno muestra cuántos elementos tiene.
- **Mantenimiento y permisos**: permisos, asistente y operaciones del sistema.
- **Disco de arranque** (abajo): espacio libre y total.

Los módulos de Mac:

| Módulo | Qué contiene |
|---|---|
| **Basura del sistema** | Cachés de usuario, de apps y del sistema, registros de usuario y del sistema, adjuntos de Mail. |
| **Desarrollo** | DerivedData, soporte de dispositivos, archivos de Xcode, otros datos de Xcode, simuladores, runtimes, cachés de simuladores, cachés de paquetes, dependencias y compilaciones de tus proyectos. |
| **Aplicaciones** | Apps poco usadas y apps que ocupan mucho (contando sus datos). |
| **Inicio y rendimiento** | Agentes de tu usuario y servicios de terceros que arrancan solos. |
| **Descargas** | Instaladores y archivos comprimidos. |
| **Restos de apps** | Datos de apps que ya no tienes. |
| **Archivos grandes** | Archivos personales de más de 500 MB y copias de iPhone/iPad. |
| **Papelera** | Lo que ya está en la Papelera. |

Qué incluye exactamente cada categoría y cómo se decide su riesgo: [CATEGORIES.md](CATEGORIES.md).

## 5. Elegir qué analizar

En la pantalla de inicio, la tarjeta **Qué analizar** muestra un icono por módulo:

- **Haz clic en un módulo** para incluirlo o quitarlo entero.
- **Usa su menú (⋯)** para elegir categorías sueltas. El símbolo cambia: ✓ todo, − en parte, ○ nada.
- **Todo** y **Nada** marcan o desmarcan todos los módulos.

La elección se guarda entre sesiones y también se puede cambiar en **Ajustes** (⌘,). Las categorías que añadan futuras versiones vendrán activadas.

## 6. Analizar

Pulsa **Analizar** (o ⌘R). Mientras analiza verás:

- **Encontrado**: el espacio liberable descubierto hasta ahora y cuántos archivos se han recorrido.
- **Una fila por categoría**: pendiente, en curso (con porcentaje si lo sabe) o terminada con su tamaño.

**Detener** (⌘.) cancela el análisis y conserva los resultados que ya hubiera.

Para no repetirlo todo, cada módulo tiene **Analizar solo …** o **Volver a analizar**: se analiza solo ese módulo y se conservan los resultados de los demás.

### Cómo mide

- Recorre las carpetas con `getattrlistbulk`, que lee miles de entradas por llamada.
- Cuenta **los bytes que se liberarían de verdad**. Si un archivo es un clon APFS que comparte bloques con otro, esos bloques no cuentan: el inspector avisa cuando un elemento ocupa más de lo que liberaría.
- No cuenta dos veces lo mismo: si un elemento está dentro de otro, solo queda el de fuera.

## 7. Revisar los resultados

### El resumen

Al terminar, **Análisis inteligente** muestra:

- El total que puedes liberar, cuándo se analizó, cuántos elementos y en cuánto tiempo.
- Una **barra por riesgo** y su leyenda.
- Los atajos de selección: **Solo lo seguro**, **Seguro y a revisar**, **Nada**.
- Un aviso si alguna zona no se pudo analizar por falta de permisos, con un botón a **Revisar permisos**.
- Una tarjeta por módulo con su tamaño, su barra de riesgo y cuántos elementos hay seleccionados.

### Los niveles de riesgo

| Nivel | Qué significa | ¿Se marca solo? |
|---|---|---|
| 🟢 **Seguro** | Se regenera solo. Borrarlo no tiene consecuencias visibles. | Sí (por defecto) |
| 🟠 **Revisar** | Recuperable, pero con coste: volver a descargar, compilar o configurar. | Solo si lo eliges en Ajustes |
| 🔴 **Riesgo alto** | Puede ser tu única copia o necesario para que algo funcione. | Nunca |

### El detalle de un módulo

Al abrir un módulo verás sus categorías como secciones, cada una con sus elementos. En cada fila: casilla para incluirlo, nombre, ubicación, riesgo, fecha y tamaño.

| Acción | Cómo |
|---|---|
| Incluir o quitar un elemento | Casilla, o **doble clic** en la fila |
| Incluir o quitar una categoría entera | Casilla de la cabecera de la sección |
| Seleccionar por riesgo en este módulo | Menú **Seleccionar** (incluye *Todo, incluido riesgo alto*) |
| Buscar | Campo de búsqueda de la barra de herramientas |
| Filtrar por riesgo | Menú **Filtrar** |
| Ordenar | Menú **Ordenar**: tamaño, nombre, fecha o riesgo |
| Ver el archivo | **Espacio** (Vista rápida) |
| Más opciones | **Clic derecho**: incluir/quitar, *Mostrar en el Finder*, *Vista rápida*, *Copiar ruta(s)*, *Ignorar siempre* |
| Panel de detalles | ⌥⌘I |

Se pueden seleccionar varias filas con ⇧ y ⌘ para actuar sobre todas a la vez.

### El panel de detalles

Con un elemento resaltado, el panel lateral explica:

- **Qué es** la categoría y **qué pasa si lo borras**.
- **Por qué** tiene ese riesgo (por ejemplo: *«No lo arrancas desde hace 5 meses»*).
- **Cómo se elimina**: definitivo, a la Papelera, con simctl, con el asistente…
- Cuánto **se liberará** y, si comparte bloques APFS, cuánto ocupa en total.
- **Incluir en la limpieza**, **Mostrar en el Finder** e **Ignorar siempre**.

Con varias filas resaltadas, resume cuántas hay de cada riesgo.

### Ignorar siempre

*Ignorar siempre* oculta el elemento ahora y en los próximos análisis. Se deshace en **Ajustes › Elementos ignorados**.

### Inicio y rendimiento

Este módulo no libera espacio: desactiva procesos que arrancan solos. En lugar de bytes muestra cuántos procesos hay y cuántos se desactivarán. Las apps que se abren al iniciar sesión (*Ítems de inicio*) no se pueden listar desde fuera: el módulo ofrece **Abrir Ítems de inicio…** para gestionarlas en Ajustes del Sistema.

## 8. Limpiar

### Revisar antes de limpiar

Con algo seleccionado aparece abajo la **barra de limpieza** (*N elementos seleccionados*). Pulsa **Revisar y limpiar** (⌘⌫). La hoja de revisión muestra:

- **Por nivel de riesgo**: cuánto hay de cada uno.
- **Cómo se eliminará**: cuánto va a la **Papelera** (recuperable) y cuánto se **borra definitivamente**.
- **No usar la Papelera**: borra definitivamente también lo que iría a la Papelera, solo en esta limpieza.
- Si hay procesos de inicio, cuántos se detendrán.
- Si hay elementos de **riesgo alto**, la lista y el botón **Quitar los de riesgo alto**.

Pulsa **Limpiar** para empezar, o **Cancelar** para volver.

### Cómo se elimina cada cosa

| Tipo | Qué hace MaCleaner | ¿Recuperable? |
|---|---|---|
| Cachés, registros, artefactos de compilación | Borrado directo | No (se regeneran solos) |
| Instaladores, comprimidos, restos de apps, archivos grandes, copias de iPhone/iPad, archivos de Xcode (`.xcarchive`) | A la Papelera | Sí, hasta que la vacíes |
| Contenido de la Papelera | Borrado directo | No |
| Apps | La app y sus datos (cachés, preferencias, contenedores…) a la Papelera | Sí |
| Cachés y registros del sistema | Los borra el asistente privilegiado | No |
| Simuladores y runtimes | `simctl delete` / `simctl runtime delete` | No (Xcode puede volver a crearlos o descargarlos) |
| Agentes de tu usuario | Se detienen y su plist va a la Papelera | Sí |
| Servicios de terceros de `/Library` | Se detienen y el asistente borra su plist | No |

### El progreso, elemento a elemento

Al pulsar **Limpiar**, la app vuelve a **Análisis inteligente** y muestra:

- **Arriba**: una barra de progreso, *«X de N elementos · Y liberados»* y cuántos han tenido problemas.
- **El elemento en curso**: su nombre, qué se está haciendo (*Moviendo a la Papelera*, *Eliminando el runtime (simctl)*, *Borrando con el asistente privilegiado*…), su ubicación y un cronómetro.
- **La lista completa**, con el estado de cada elemento:

| Icono | Estado |
|---|---|
| ◌ punteado | En cola |
| Indicador girando | En curso |
| ✓ verde | Eliminado (o ya no existía) |
| 🗑 verde | En la Papelera |
| ⚡︎ verde | Proceso de inicio desactivado |
| ⚠︎ naranja | Falló: debajo se explica por qué |
| − gris | No se llegó a intentar |

Se procesa de mayor a menor tamaño, para que lo que más espacio libera vaya primero.

#### Cuando algo se atasca

Si un elemento lleva **más de 15 segundos**, el cronómetro se pone naranja y aparece **«Está tardando más de lo normal»** con lo que suele retenerlo:

| Tipo de elemento | Causa habitual |
|---|---|
| Borrar o mover a la Papelera | Una carpeta con muchísimos archivos o en uso por otra app. Cierra la app a la que pertenece. |
| Apps | macOS espera tu contraseña en otra ventana, o la app sigue abierta. |
| Simuladores y runtimes | `simctl` espera a CoreSimulator. Cierra Xcode y el Simulador. |
| Elementos del sistema | El asistente sigue trabajando o no responde. |
| Agentes de inicio | El servicio tarda en detenerse. Cierra su app. |

Antes del primer elemento del sistema, MaCleaner comprueba en 5 segundos que el asistente responde. Si no, esos elementos fallan enseguida con el motivo en vez de quedarse esperando. Además, cada llamada al asistente tiene un plazo máximo.

#### Detener

**Detener** (en la pantalla o en la barra de herramientas como *Detener limpieza*) corta la limpieza al instante:

- Lo que no se llegó a tocar queda como *«No se llegó a eliminar: limpieza detenida»* y sigue en los resultados.
- Si un elemento estaba a medias, la app deja de esperarlo; macOS puede terminar ese borrado en segundo plano.

### El informe final

Al terminar verás:

- **Liberados X**: lo que se ha borrado definitivamente.
- Lo que se ha movido a la **Papelera**, con el botón **Abrir la Papelera**. Ese espacio se libera al vaciarla.
- Cuántos **procesos de inicio** se han desactivado.
- Los elementos que **no se pudieron eliminar**, con el motivo de cada uno (se puede seleccionar y copiar el texto).
- **Ver lo que queda** y **Analizar de nuevo**.

## 9. Mantenimiento

**Mantenimiento y permisos** reúne operaciones del sistema que no son elementos sueltos. Cada tarjeta explica **qué se borra**, **para qué servía** y **qué pasa después**; las que liberan espacio muestran antes cuánto se recuperará y, al terminar, cuánto se liberó de verdad. **Volver a medir** actualiza las estimaciones.

| Acción | Qué hace | Riesgo | Necesita |
|---|---|---|---|
| **Instantáneas locales de Time Machine** | Pide a macOS que purgue las instantáneas que guarda en tu disco entre copias (`tmutil thinlocalsnapshots`). La cifra es un máximo: lo decide macOS. Tus copias del disco de Time Machine no se tocan. | Revisar | Asistente |
| **Simuladores y runtimes inutilizables** | Borra runtimes dañados o incompletos y simuladores cuyo runtime ya no existe. | Seguro | — |
| **Restablecer todos los simuladores** | Apaga y deja vacíos todos los simuladores (apps, cuentas, ajustes). Siguen existiendo. | Revisar | — |
| **Reconstruir la base de datos de apps** | Vacía y reconstruye LaunchServices. Arregla apps repetidas en «Abrir con», iconos incorrectos o archivos que se abren con la app equivocada. | Seguro | — |
| **Restablecer Vista rápida y miniaturas** | Reinicia los generadores y la caché de miniaturas. | Seguro | — |

Antes de ejecutar, una confirmación repite qué se borra y qué pasa después.

### Mientras se ejecuta

La tarjeta muestra:

- **El paso en curso** (por ejemplo, *«macOS está purgando las instantáneas (tmutil thinlocalsnapshots)»*) y un **cronómetro**.
- **El avance medido**, cuando se puede medir. Al purgar instantáneas, cada 3 segundos: *«Quedan N instantáneas · X liberados»*.
- **Lo que la bloquea**, si se detecta. Por ejemplo, *«Time Machine está haciendo una copia ahora mismo»*: macOS no suelta las instantáneas hasta que la copia termine.
- Si tarda más de lo normal (1 minuto para las instantáneas y LaunchServices, 30 segundos para el resto), qué suele retenerla.
- **Dejar de esperar**: la app deja de esperar. Lo que ya se pidió a macOS puede seguir en segundo plano.

**Detalles técnicos**, al final de la pantalla, guarda el registro de cada acción con la hora de cada paso y la salida de los comandos.

### Por qué la purga de instantáneas puede liberar poco

- Solo se purgan instantáneas de **Time Machine** (`com.apple.TimeMachine.…`). Las de actualizaciones de macOS (`com.apple.os.update-…`) las gestiona el sistema.
- La cifra *«liberables como máximo»* es todo el espacio purgable que informa macOS, que incluye más cosas que las instantáneas.
- Si Time Machine está haciendo una copia, espera a que termine.

Para ver tus instantáneas: `tmutil listlocalsnapshots /`.

## 10. Ajustes

Abre **MaCleaner › Ajustes…** (⌘,).

| Sección | Opción | Qué hace |
|---|---|---|
| **Qué analizar** | Un interruptor por módulo y por categoría | Lo mismo que *Qué analizar* en la pantalla de inicio. |
| **Al terminar el análisis** | *Seleccionar automáticamente*: **Solo lo seguro** (por defecto), **Lo seguro y lo que hay que revisar** o **Nada: lo elijo yo** | Qué se marca solo al terminar. Lo de riesgo alto nunca. |
| **Limpieza** | **No usar la Papelera** | Lo que iría a la Papelera se borra definitivamente. También se puede cambiar en cada limpieza. |
| **Elementos ignorados** | Lista con **Dejar de ignorar** y **Dejar de ignorar todo** | Vuelven a aparecer en el próximo análisis. |
| **Privacidad** | — | Recordatorio de que todo ocurre en tu Mac, y la versión instalada. |

## 11. Atajos de teclado

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

Las acciones de selección y limpieza están también en el menú **Limpieza**.

## 12. Qué no hace MaCleaner

- **No borra nada sin tu revisión.** Toda limpieza pasa por la hoja de revisión.
- **No toca archivos de Apple ni del sistema protegido.** El asistente solo borra dentro de `/Library/Caches`, `/Library/Logs` y `/private/var/log`, y plists de terceros de `/Library/LaunchAgents` y `/Library/LaunchDaemons` (nunca `com.apple.*`).
- **No vacía la Papelera.** Lo que va a la Papelera se puede recuperar hasta que tú la vacíes.
- **No lista los Ítems de inicio de otras apps** (`SMAppService`): no hay API pública. Se gestionan en Ajustes del Sistema.
- **No se conecta a internet** ni envía telemetría.

## 13. Problemas frecuentes

**macOS dice que no puede verificar MaCleaner.**
La app no está notarizada. Sigue los pasos de [Instalar](#instalar): *Privacidad y seguridad › Abrir igualmente*.

**«Hay zonas que no se pudieron analizar».**
Falta *Acceso total al disco*. Pulsa **Revisar permisos** y actívalo. Después, vuelve a analizar.

**El asistente «no responde».**
Pulsa **Reinstalar** y apruébalo en *Ítems de inicio y extensiones*. Si sigue igual, **Diagnosticar el asistente** te dice en qué paso falla. Guía completa: [HELPER.md](HELPER.md).

**La limpieza se queda en un elemento.**
Mira el aviso naranja del elemento en curso: dice qué suele retenerlo. Si no avanza, pulsa **Detener**: el resto queda sin tocar y puedes reintentarlo después.

**Al desinstalar una app pide la contraseña.**
Es normal en apps instaladas por el administrador (por ejemplo, algunas del App Store): macOS la pide igual que el Finder.

**Liberé espacio, pero el disco sigue igual de lleno.**
- Lo que fue a la **Papelera** se libera al vaciarla.
- macOS puede tardar unos segundos en actualizar el espacio libre.
- Las instantáneas de Time Machine retienen espacio de archivos ya borrados hasta que se purgan.

**Un simulador o runtime no se borra.**
Cierra Xcode y el Simulador y vuelve a intentarlo. Si es un runtime en uso por simuladores, aparece como *Revisar* e indica cuáles lo usan.

**Quiero recuperar algo que limpié.**
Si fue a la Papelera, ábrela y usa *Devolver*. Lo borrado definitivamente (cachés, registros, artefactos) se regenera solo; los simuladores se pueden volver a crear en Xcode.
