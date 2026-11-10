# TikiFilesMac — v3 (antes WQFilesMac)

App para Mac como WQFiles (kolbicz/WQFiles, iOS 27), pero hecha desde cero en SwiftUI para macOS. Repo: **tikipro7/TikiFilesMaC**.

WQFiles original es un explorador de archivos, gestor de datos de apps y limpiador de caché para iOS 27, sin jailbreak, usando worse_query. En Mac **no se necesita worse_query ni jailbreak**: macOS ya permite ver archivos con permisos normales.

Esta app NO copia código de WQFiles (GPL, Objective-C para iOS). Es una app nueva en SwiftUI para Mac con la misma idea. **No es igual que la de celular**: la de iOS usa App Group y worse_query; esta usa permisos normales de macOS, y trae cosas que la de iOS no tiene para Mac: medir el disco, buscar duplicados y limpiar Xcode.

## v3: todo más entendible para quien la usa por primera vez

Luis preguntó: "pero como sabe que borrar, haz que sea mas entendble todo". Por eso la v3 explica todo en español simple, dentro de la app:

- **Pantalla de Inicio — "¿Primera vez aquí? Empieza aquí"**: 3 pasos simples (1. Mide tu espacio, 2. Limpia lo seguro, 3. Busca duplicados), con botones que te llevan directo a cada pestaña.
- **Cada sección explica en 1-2 frases** qué hace, qué es seguro borrar y qué NO se borra nunca.
- **Cada archivo/carpeta que se puede borrar muestra**: qué es, por qué se puede borrar, cuánto pesa, y una etiqueta:
  - 🟢 **"✅ Seguro de borrar, se vuelve a crear solo"** (DerivedData, caché, DeviceSupport, Simulator)
  - 🟠 **"⚠️ Revisa antes de borrar"** (Downloads, Documents, Escritorio, builds de ForkTikiLauncher, Archives, datos de apps)
- **Antes de borrar, un resumen claro**: "Vas a borrar X, vas a liberar Y GB, todo va a la Papelera, puedes recuperarlo, tus juegos NO se tocan".
- **Modo principiante prendido por defecto**: solo muestra Inicio, Espacio, Duplicados y Limpiar Xcode. Un botón "Ver modo avanzado" muestra también Archivos, Apps, Limpieza de caché y Registro.
- **"¿Cómo sabe qué borrar?" explicado en la app misma**:
  - Duplicados: mismo tamaño Y misma huella SHA256 por dentro. Que se llamen igual no basta.
  - Caché de Xcode: archivos temporales que Xcode vuelve a crear solo al compilar.
  - Espacio: la app solo mide carpetas. Nunca borra nada sola: tú eliges.

## Qué hace

- **Inicio:** 3 pasos, cómo sabe qué borrar, lo que nunca se borra, y botones a Espacio / Duplicados / Limpiar Xcode.
- **Espacio:** espacio libre/total del disco interno, barra de uso (verde / naranja / rojo si pasa del 85%), y las carpetas que más pesan: DerivedData, Caches, Downloads, Documents, ForkTikiLauncher/builds, Archives, iOS DeviceSupport, CoreSimulator y Desktop, cada una con su explicación, su etiqueta de seguridad y botón para abrir o mandar a Papelera (con confirmación y resumen).
- **Duplicados:** elige una carpeta (por defecto `~/Downloads`, también `~/Documents`). Busca por tamaño y luego por **SHA256**, para no borrar archivos que solo se llaman igual. Muestra grupos con copias, tamaño y cuánto se libera. Botón para mandar a la Papelera todos menos el primero de cada grupo, con confirmación y resumen.
- **Limpiar Xcode:** mide por proyecto `~/Library/Developer/Xcode/DerivedData`, iOS DeviceSupport viejo, Archives, CoreSimulator (Simulator) y `~/Library/Caches`. Cada ítem dice qué es y si es seguro. Muestra cuánto se liberaría **antes** de limpiar. Limpia solo lo seleccionado, a la Papelera, nunca permanente.
- **Archivos (modo avanzado):** explorador, buscador dentro de la carpeta, ver / copiar ruta / mandar a Papelera. Ir a cualquier ruta. Vista previa de texto **e imágenes** (png/jpg/gif/webp/heic).
- **Apps (modo avanzado):** lista de apps en `/Applications` con tamaño, datos en `~/Library/Containers` y `~/Library/Application Support`, respaldo ZIP de Documents/Library a `~/Desktop/WQFilesMac-Respaldos/`.
- **Limpieza de caché (modo avanzado):** tamaño de `~/Library/Caches` por app, cada una con su explicación y etiqueta de seguridad, seleccionar, limpiar a Papelera (nunca permanente), se recrea la carpeta vacía.
- **Registro (modo avanzado):** log de todo lo borrado, respaldado y limpiado.
- **Diseño:** tarjetas blancas con esquinas redondeadas y sombra, no plano. Barra de disco con color según lo lleno que esté.

## Seguridad

- Todo borrado va a la **Papelera**, nunca permanente por defecto.
- **Protegidos, no se borran:** `.nup`, `.nsp`, `.nsz`, `.xci`, `.xcz`, `prod.keys`, `keys.txt`, y rutas con `nx2apple`, `forktikilauncher`, `juegos`, `games`, `nintendo`.
- No toca archivos del sistema (`/System`, `/usr`, `/bin`, `/sbin`, `/etc`).
- DerivedData se puede borrar sin miedo: Xcode lo vuelve a generar al compilar. No borres el proyecto que estés compilando en ese momento. Antes de limpiar datos de una app, avisa y recomienda hacer respaldo ZIP primero. Cierra la app antes de respaldar o limpiar sus datos.

## Compilar en terminal (Mac M1, Xcode 27.2)

```bash
cd ~/Downloads/TikiFilesMaC
git pull
xcodegen generate
xcodebuild -project WQFilesMac.xcodeproj -scheme WQFilesMac -configuration Release build
```

La `.app` queda en:

```
/Users/tiki/Library/Developer/Xcode/DerivedData/WQFilesMac-*/Build/Products/Release/WQFilesMac.app
```

Para copiarla a un lugar fijo (usa la carpeta con la fecha de hoy, no el `*`, que puede agarrar una vieja):

```bash
mkdir -p ~/Downloads/TikiFilesMaC/build/Release
cp -R ~/Library/Developer/Xcode/DerivedData/WQFilesMac-fabontksrjyzahbehxazzrgyqkau/Build/Products/Release/WQFilesMac.app ~/Downloads/TikiFilesMaC/build/Release/
open ~/Downloads/TikiFilesMaC/build/Release/WQFilesMac.app
```

Si `xcodegen` no se encuentra, instálalo con:

```bash
/opt/homebrew/bin/brew install xcodegen
```

## Compartir

```bash
cd ~/Downloads/TikiFilesMaC/build/Release
zip -r TikiFilesMac.zip WQFilesMac.app
```

La primera vez, clic derecho > Abrir (Gatekeeper).

## Nota

No se pudo compilar aquí (no hay Xcode en esta máquina). Solo se verificó sintaxis básica: llaves 316/316, paréntesis 697/697. Si al compilar te da un error, pégalo tal cual.
