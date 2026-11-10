# TikiFilesMac — Pasos (v3)

1. Copia la carpeta `TikiFilesMaC` a tu Mac, en `~/Downloads/TikiFilesMaC`, o clónala:
   ```bash
   cd ~/Downloads
   git clone https://github.com/tikipro7/TikiFilesMaC.git
   cd TikiFilesMaC
   ```
2. En Terminal:
   ```bash
   xcodegen generate
   xcodebuild -project WQFilesMac.xcodeproj -scheme WQFilesMac -configuration Release build
   ```
3. Abre la app desde DerivedData o cópiala a `build/Release/` (ver README.md).
4. **Primera vez: lee la pantalla de Inicio** ("¿Primera vez aquí? Empieza aquí"). Son 3 pasos:
   - **Paso 1 — Espacio:** dale a "Medir espacio". Ahí ves cuánto tienes libre y qué carpetas pesan más. Cada carpeta dice qué es y si es segura (verde) o hay que revisar antes (naranja).
   - **Paso 2 — Limpiar Xcode:** dale a "Medir Xcode", selecciona lo que diga "✅ Seguro de borrar" (DerivedData, caché, DeviceSupport), mira cuánto se libera y dale a "Limpiar seleccionados". Antes de borrar te sale un resumen: qué vas a borrar, cuánto liberas, y que todo va a la Papelera.
   - **Paso 3 — Duplicados:** elige Downloads, dale a "Buscar duplicados", revisa los grupos y dale a "Mandar duplicados a Papelera". Se queda el primero de cada grupo.
5. **Modo principiante (prendido por defecto):** solo ves Inicio, Espacio, Duplicados y Limpiar Xcode. Si quieres ver todo (Archivos, Apps, Limpieza de caché, Registro), dale a "Ver modo avanzado" arriba.
6. **¿Cómo sabe qué borrar?** Está explicado en la pantalla de Inicio y en cada sección:
   - Duplicados: mismo tamaño Y misma huella SHA256 por dentro.
   - Caché de Xcode: archivos temporales que Xcode vuelve a crear solo.
   - Espacio: la app solo mide; nunca borra nada sola.
7. Recuerda: todo va a la Papelera, nada se borra para siempre. Los juegos y `prod.keys` están protegidos.
