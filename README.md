# WQFilesMac — v2

App para Mac como WQFiles (kolbicz/WQFiles, iOS 27), pero hecha desde cero en SwiftUI para macOS.

WQFiles original es un explorador de archivos, gestor de datos de apps y limpiador de caché para iOS 27, sin jailbreak, usando worse_query. En Mac **no se necesita worse_query ni jailbreak**: macOS ya permite ver archivos con permisos normales.

Esta app NO copia código de WQFiles (GPL, Objective-C para iOS). Es una app nueva en SwiftUI para Mac con la misma idea. **No es igual que la de celular**: la de iOS usa App Group y worse_query; esta usa permisos normales de macOS, y trae cosas que la de iOS no tiene para Mac: medir el disco, buscar duplicados y limpiar Xcode.

## Qué hace (v2)

- **Archivos:** explorador, buscador dentro de la carpeta, ver / copiar ruta / mandar a Papelera. Ir a cualquier ruta. Vista previa de texto **e imágenes** (png/jpg/gif/webp/heic).
- **Espacio:** espacio libre/total del disco interno, barra de uso (verde / naranja / rojo si pasa del 85%), y las carpetas que más pesan: DerivedData, Caches, Downloads, Documents, ForkTikiLauncher/builds, Archives, iOS DeviceSupport, CoreSimulator y Desktop, con tamaño en GB y botón para abrir o mandar a Papelera.
- **Duplicados:** elige una carpeta (por defecto `~/Downloads`, también `~/Documents`). Busca por tamaño y luego por **SHA256**, para no borrar archivos que solo se llaman igual. Muestra grupos con copias, tamaño y cuánto se libera. Botón para mandar a la Papelera todos menos el primero de cada grupo, con confirmación.
- **Limpiar Xcode:** mide por proyecto `~/Library/Developer/Xcode/DerivedData`, iOS DeviceSupport viejo, Archives, CoreSimulator (Simulator) y `~/Library/Caches`. Muestra cuánto se liberaría **antes** de limpiar. Limpia solo lo seleccionado, a la Papelera, nunca permanente.
- **Apps:** lista de apps en `/Applications` con tamaño, datos en `~/Library/Containers` y `~/Library/Application Support`, respaldo ZIP de Documents/Library a `~/Desktop/WQFilesMac-Respaldos/`.
- **Limpieza de caché:** tamaño de `~/Library/Caches` por app, seleccionar, limpiar a Papelera (nunca permanente), se recrea la carpeta vacía.
- **Registro:** log de todo lo borrado, respaldado y limpiado.
- **Diseño:** tarjetas blancas con esquinas redondeadas y sombra, no plano. Barra de disco con color según lo lleno que esté.

## Seguridad

- Todo borrado va a la **Papelera**, nunca permanente por defecto.
- **Protegidos, no se borran:** `.nup`, `.nsp`, `.nsz`, `.xci`, `.xcz`, `prod.keys`, `keys.txt`, y rutas con `nx2apple`, `forktikilauncher`, `juegos`, `games`, `nintendo`.
- No toca archivos del sistema (`/System`, `/usr`, `/bin`, `/sbin`, `/etc`).
- DerivedData se puede borrar sin miedo: Xcode lo vuelve a generar al compilar. No borres el proyecto que estés compilando en ese momento. Antes de limpiar datos de una app, avisa y recomienda hacer respaldo ZIP primero. Cierra la app antes de respaldar o limpiar sus datos.

## Compilar en terminal (Mac M1, Xcode 27.2)

```bash
cd ~/Downloads/wqfiles-mac
xcodegen generate
xcodebuild -project WQFilesMac.xcodeproj -scheme WQFilesMac -configuration Release build
```

La `.app` queda en:

```
/Users/tiki/Library/Developer/Xcode/DerivedData/WQFilesMac-*/Build/Products/Release/WQFilesMac.app
```

Para copiarla a un lugar fijo:

```bash
mkdir -p ~/Downloads/wqfiles-mac/build/Release
cp -R /Users/tiki/Library/Developer/Xcode/DerivedData/WQFilesMac-*/Build/Products/Release/WQFilesMac.app ~/Downloads/wqfiles-mac/build/Release/
open ~/Downloads/wqfiles-mac/build/Release/WQFilesMac.app
```

Si `xcodegen` no se encuentra, instálalo con:

```bash
/opt/homebrew/bin/brew install xcodegen
```

## Compartir

```bash
cd ~/Downloads/wqfiles-mac/build/Release
zip -r WQFilesMac.zip WQFilesMac.app
```

La primera vez, clic derecho > Abrir (Gatekeeper).

## Nota

No se pudo compilar aquí (no hay Xcode en esta máquina). Solo se verificó sintaxis básica: llaves 277/277, paréntesis 650/650. Si al compilar te da un error, pégalo tal cual.
