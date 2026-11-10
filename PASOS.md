# WQFilesMac — Pasos (v2)

1. Copia la carpeta `wqfiles-mac` a tu Mac, en `~/Downloads/wqfiles-mac`.
2. En Terminal:
   ```bash
   cd ~/Downloads/wqfiles-mac
   xcodegen generate
   xcodebuild -project WQFilesMac.xcodeproj -scheme WQFilesMac -configuration Release build
   ```
3. Abre la app desde DerivedData o cópiala a `build/Release/` (ver README.md).
4. Pestañas:
   - **Archivos:** navega, busca en la carpeta, ve archivos de texto e imágenes, manda a Papelera lo que no quieras.
   - **Espacio:** mide el disco (libre/total), mira la barra de uso y las carpetas que más pesan. Si está en rojo (más del 85%), limpia DerivedData o caché.
   - **Duplicados:** elige carpeta (por defecto Downloads), dale a "Buscar duplicados", revisa los grupos y dale a "Mandar duplicados a Papelera". Se queda el primero de cada grupo.
   - **Limpiar Xcode:** dale a "Medir Xcode", selecciona DerivedData viejo / DeviceSupport / Archives / Simulator, mira cuánto se libera y dale a "Limpiar seleccionados".
   - **Apps:** busca apps, respalda sus datos en ZIP, limpia datos (con aviso).
   - **Limpieza de caché:** mide `~/Library/Caches`, selecciona y limpia a Papelera.
   - **Registro:** revisa qué se borró o respaldó.
5. Recuerda: todo va a la Papelera, nada se borra para siempre. Los juegos y `prod.keys` están protegidos.
