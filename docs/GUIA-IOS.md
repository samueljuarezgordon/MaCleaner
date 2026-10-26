# Guía de uso: MaCleaner para iPhone y iPad

Cómo instalar MaCleaner en iPhone o iPad, qué puede limpiar de verdad dentro de los límites de iOS, cómo funciona la purga de los *Datos del sistema* y qué hacer si algo no sale como esperabas.

> ¿Buscas la versión de Mac? Está en [GUIA-MAC.md](GUIA-MAC.md).

## Índice

1. [Lo primero: qué se puede hacer en iOS](#1-lo-primero-qué-se-puede-hacer-en-ios)
2. [Requisitos](#2-requisitos)
3. [Instalar](#3-instalar)
4. [La pantalla principal](#4-la-pantalla-principal)
5. [Analizar](#5-analizar)
6. [Revisar los resultados](#6-revisar-los-resultados)
7. [Limpiar](#7-limpiar)
8. [Cómo funciona la purga de los Datos del sistema](#8-cómo-funciona-la-purga-de-los-datos-del-sistema)
9. [Mantenimiento y consejos](#9-mantenimiento-y-consejos)
10. [Ajustes](#10-ajustes)
11. [Funciones desactivadas en esta versión](#11-funciones-desactivadas-en-esta-versión)
12. [Problemas frecuentes](#12-problemas-frecuentes)

---

## 1. Lo primero: qué se puede hacer en iOS

iOS encierra cada app en su propio espacio (*sandbox*). Ninguna app, tampoco MaCleaner, puede ver ni borrar los archivos de otras apps, desinstalar apps o tocar los archivos del sistema. Lo que sí puede hacer MaCleaner:

| Qué | Cómo |
|---|---|
| **Que iOS vacíe los *Datos del sistema* purgables**: cachés de otras apps y de Safari, temporales, streaming, restos de actualizaciones y, con *Optimizar almacenamiento*, los originales de Fotos que ya están en iCloud. | Pidiéndole a iOS más espacio del que hay libre: iOS purga para atender la petición. Ver [sección 8](#8-cómo-funciona-la-purga-de-los-datos-del-sistema). |
| **Vaciar la caché de MaCleaner.** | Borrando sus propios temporales. |
| **Guiarte en lo que solo se hace desde Ajustes** (descargar apps sin usar, Mensajes, Safari, Fotos…). | Con explicaciones y un acceso directo a Ajustes. |

Lo que **no** puede hacer ninguna app en iOS:

- Ver o borrar una a una las cachés de otras apps o los *Datos del sistema*.
- Borrar lo que iOS no marca como purgable: registros del sistema, índices, voces de Siri…
- Desinstalar apps o gestionar procesos de inicio.

**No se borra ninguna foto ni documento.** La purga solo afecta a lo que iOS considera prescindible.

## 2. Requisitos

| | |
|---|---|
| Dispositivo | iPhone o iPad |
| Sistema | iOS / iPadOS 27 o posterior |
| Instalación | Sideloadly o AltStore con tu Apple ID, o Xcode en un Mac |

Una sola app sirve para iPhone y iPad. No necesita conexión a internet ni envía datos a ningún servidor.

## 3. Instalar

Todavía no está en el App Store ni en TestFlight. Cada release incluye `MaCleaner-<versión>-iOS.ipa`, **sin firmar**: hay que firmarla al instalarla.

### Opción A: Sideloadly o AltStore (sin Xcode)

1. Descarga `MaCleaner-<versión>-iOS.ipa` de la [última release](https://github.com/samueljuarezgordon/MaCleaner/releases/latest).
2. Conecta el iPhone o iPad al ordenador.
3. Abre la IPA con Sideloadly o AltStore e inicia sesión con tu Apple ID. La herramienta la firma y la instala.
4. Con un Apple ID gratuito, la firma caduca a los **7 días**: repite el paso 3 para renovarla. Tus datos de la app se conservan.

### Opción B: Xcode

1. Clona el repositorio y abre `Cleaner.xcodeproj`.
2. En *Signing & Capabilities* del target **MaCleaner**, elige tu equipo.
3. Conecta el dispositivo, elígelo como destino y pulsa ⌘R.

### La primera vez en el dispositivo

1. **Confía en el desarrollador**: *Ajustes › General › VPN y gestión de dispositivos* › tu Apple ID › **Confiar**.
2. **Activa el Modo de desarrollador** si iOS lo pide: *Ajustes › Privacidad y seguridad › Modo de desarrollador*. El dispositivo se reinicia.

### Actualizar

Instala la IPA nueva por encima, con la misma herramienta y el mismo Apple ID. No hace falta borrar la anterior.

## 4. La pantalla principal

En iPhone la navegación es una lista; en iPad, una barra lateral con el contenido a la derecha.

| Apartado | Qué es |
|---|---|
| **Análisis inteligente** | Inicio: espacio del dispositivo, *Qué analizar*, progreso y resumen. |
| **Basura del sistema** | Los *Datos del sistema purgables* y la caché de MaCleaner. |
| **Mantenimiento y consejos** | La purga con un objetivo, guías y consejos de Ajustes. |
| **Ajustes** | Qué analizar, qué se selecciona solo, elementos ignorados. |

La tarjeta **Almacenamiento** muestra el espacio libre y, aparte, cuánto considera iOS **purgable**.

## 5. Analizar

1. En **Análisis inteligente**, revisa **Qué analizar**: toca un módulo para incluirlo o quitarlo; su menú (⋯) permite elegir categorías sueltas. La elección se guarda.
2. Pulsa **Analizar**.

El análisis de iOS tarda un instante: lee la cifra de espacio purgable que da el propio iOS y mide la caché de MaCleaner. Mientras dura, la pantalla no se bloquea. Al terminar, el dispositivo vibra.

## 6. Revisar los resultados

El resumen muestra el total que se puede liberar, una barra por riesgo y una tarjeta por módulo. Toca **Basura del sistema** para ver el detalle:

| Elemento | Qué es | Riesgo |
|---|---|---|
| **Datos del sistema purgables** | Lo que iOS considera prescindible ahora mismo. La cifra la decide iOS. | 🟢 Seguro |
| **Caché de MaCleaner** | Temporales y caché de la propia app. | 🟢 Seguro |

- **Toca un elemento** para ver sus detalles: qué es, por qué tiene ese riesgo, qué pasa después y cómo se elimina.
- Usa su casilla para incluirlo o quitarlo de la limpieza.
- Mantén pulsado para el menú contextual: incluir o quitar, **Ignorar siempre**.

Los niveles de riesgo son los mismos que en Mac:

| Nivel | Qué significa | ¿Se marca solo? |
|---|---|---|
| 🟢 **Seguro** | Se regenera solo. | Sí (por defecto) |
| 🟠 **Revisar** | Recuperable, con coste. | Solo si lo eliges en Ajustes |
| 🔴 **Riesgo alto** | Puede ser tu única copia. | Nunca |

## 7. Limpiar

1. Con algo seleccionado, aparece abajo la barra de limpieza. Pulsa **Revisar y limpiar**.
2. La hoja de revisión muestra cuánto hay de cada riesgo y cómo se eliminará. Pulsa **Limpiar**.
3. La app vuelve a **Análisis inteligente** y muestra **Limpiando**. Si incluiste los *Datos del sistema*, verás el aviso: *«Purgando los datos del sistema por oleadas. Mantén MaCleaner abierta y en pantalla…»*.
4. Al terminar, el dispositivo vibra y aparece el informe: **Liberados X** y, si algo falló, el motivo.

Mientras limpia:

- **No salgas de la app ni bloquees la pantalla.** La pantalla no se apaga sola, pero si cambias de app, la purga se detiene y libera su espacio de relleno.
- iOS puede avisar de que **el almacenamiento está casi lleno**. Es normal: es lo que hace que iOS purgue.
- No hagas fotos ni descargues nada hasta que termine.

La purga va al final de la limpieza, para aprovechar el espacio que se acaba de liberar.

## 8. Cómo funciona la purga de los Datos del sistema

iOS vacía sus cachés cuando una app necesita espacio que no hay. Es el mismo mecanismo que el truco de *«alquilar una película más grande que el espacio libre»*, hecho de forma controlada y medida:

1. **Pide espacio.** MaCleaner hace crecer un archivo de relleno dentro de su propio espacio. Reserva bloques sin escribir datos (`F_PREALLOCATE`) o, si no se admite, escribe ceros. Pide aunque no quepa: cada petición rechazada hace que iOS purgue para atenderla.
2. **Mantiene la presión.** Con el almacenamiento lleno, vuelve a pedir cada 250 ms: lo que iOS libera se ocupa al momento.
3. **Repite por oleadas.** Cuando iOS lleva 25 s sin liberar nada, borra el relleno y empieza otra oleada. Como con el truco de la película, cada oleada suele sacar algo más.
4. **Para** al llegar al objetivo, tras 4 oleadas, cuando una oleada libera menos de 200 MB o a los 5 minutos.
5. **Mide** el espacio ganado de verdad con el relleno ya borrado.

### Salvaguardas

- Si la app pasa a segundo plano, la purga se detiene y borra el relleno al momento.
- Al abrir la app se borra cualquier relleno que hubiera quedado de una sesión interrumpida.
- La pantalla no se bloquea mientras dura.
- El relleno vive dentro de la app: nunca toca tus datos.

### Por qué a veces libera poco o nada

- **Acabas de purgar o de reiniciar**: iOS ya ha vaciado sus cachés y no tiene más que soltar. Prueba al cabo de unos días de uso.
- **La cifra purgable es una estimación de iOS.** iOS decide qué y cuánto suelta.
- **Fotos con *Descargar y conservar originales***: iOS nunca libera tus fotos. Con *Optimizar almacenamiento* sí puede liberar los originales que ya están en iCloud (tus fotos no se borran: se vuelven a descargar al abrirlas).

## 9. Mantenimiento y consejos

### Desde MaCleaner: Liberar espacio purgable

La misma purga, con más control:

1. Elige **Cuánto liberar**: **Todo lo posible** o **Hasta 1, 5, 10 o 20 GB**. Con un límite, el almacenamiento está lleno menos tiempo.
2. Despliega **Caché de Fotos en iCloud** para ver si tus originales de Fotos pueden entrar en la purga y dónde cambiarlo (*Ajustes › Apps › Fotos*).
3. Pulsa **Liberar todo lo posible** (o **Liberar hasta X GB**) y confirma con **Liberar espacio**.

Durante la purga verás la oleada en curso (*«llenando el espacio libre…»* o *«almacenamiento lleno, iOS está purgando…»*), el tamaño del relleno y cuánto ha liberado iOS. **Detener** la corta en cualquier momento. Al terminar: *«Liberados X»* o *«iOS no tenía nada más que purgar ahora mismo»*.

### Guías

**Desinstalar apps pesadas sin perder datos**: guía paso a paso de *Desinstalar app* (*Offload*) en *Ajustes › General › Almacenamiento*. La app se borra, pero sus documentos y datos se conservan, y se vuelve a descargar al tocar su icono.

### Desde Ajustes

Cosas que solo puedes hacer tú desde Ajustes. Cada consejo explica **qué se borra**, **para qué servía**, **qué pasa después** y **dónde** está, con un botón **Abrir Ajustes**:

| Consejo | Riesgo | Dónde |
|---|---|---|
| Descargar apps sin usar | 🟢 Seguro | *Ajustes › General › Almacenamiento › Descargar apps sin usar* |
| Vaciar «Eliminados recientemente» | 🟠 Revisar | *Fotos › Colecciones › Eliminados recientemente* |
| Conservar mensajes 1 año | 🟠 Revisar | *Ajustes › Apps › Mensajes › Conservar mensajes* |
| Borrar datos de Safari | 🟠 Revisar | *Ajustes › Apps › Safari › Borrar historial y datos* |
| Descargas de música y vídeo | 🟢 Seguro | En cada app (Música, TV, Spotify, Netflix…) |
| Optimizar el almacenamiento de Fotos | 🟢 Seguro | *Ajustes › Apps › Fotos › Optimizar almacenamiento* |

## 10. Ajustes

| Sección | Opción | Qué hace |
|---|---|---|
| **Qué analizar** | Un interruptor por módulo y por categoría | Lo mismo que *Qué analizar* en la pantalla de inicio. |
| **Al terminar el análisis** | **Solo lo seguro** (por defecto), **Lo seguro y lo que hay que revisar** o **Nada: lo elijo yo** | Qué se marca solo. Lo de riesgo alto, nunca. |
| **Limpieza** | **No usar la Papelera** | Sin efecto práctico con las categorías actuales de iOS, que no usan papelera. |
| **Elementos ignorados** | **Dejar de ignorar** / **Dejar de ignorar todo** | Vuelven a aparecer en el próximo análisis. |
| **Privacidad** | — | Todo ocurre en el dispositivo, y la versión instalada. |

## 11. Funciones desactivadas en esta versión

Desde la 1.1.0 están desactivados la **Fototeca** (fotos y vídeos duplicados, capturas, grabaciones, ráfagas, vídeos grandes), **iCloud Drive** y los **archivos grandes y comprimidos** de carpetas elegidas. En dispositivos reales su análisis no terminaba. El código sigue en el proyecto para retomarlo; sus reglas están en [CATEGORIES.md](CATEGORIES.md#desactivadas-desde-la-110).

## 12. Problemas frecuentes

**La app no abre o dice «Desarrollador no fiable».**
Confía en tu Apple ID en *Ajustes › General › VPN y gestión de dispositivos* y activa el *Modo de desarrollador*.

**Dejó de abrirse a la semana.**
La firma de un Apple ID gratuito caduca a los 7 días. Vuelve a instalar la IPA con Sideloadly o AltStore.

**«Datos del sistema: iOS no ha liberado nada esta vez».**
iOS no tenía nada que soltar. Suele pasar justo después de otra purga o de reiniciar. Prueba más tarde.

**«La purga se detuvo antes de terminar porque MaCleaner dejó de estar en pantalla».**
Saliste de la app o se bloqueó la pantalla. Vuelve a intentarlo sin salir de MaCleaner.

**iOS avisa de «Almacenamiento casi lleno» durante la purga.**
Es normal y dura solo mientras se purga. Al terminar, el relleno se borra.

**Los *Datos del sistema* de Ajustes no bajan tanto como esperaba.**
Ajustes cuenta cosas que iOS no marca como purgables (registros, índices, voces de Siri…) y que ninguna app puede borrar. MaCleaner solo consigue lo que iOS acepta purgar.

**¿Puedo usarlo en el simulador de iOS?**
Para probar la interfaz, sí. **No ejecutes la purga en el simulador**: su disco es el de tu Mac.
