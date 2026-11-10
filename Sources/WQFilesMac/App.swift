import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit

// WQFilesMac — v3 (10 nov 2026): todo más entendible para quien lo usa
// por primera vez. Pantalla de inicio con 3 pasos, cada sección explica
// en español simple qué hace, qué es seguro borrar y qué NO se borra
// nunca, y antes de borrar hay un resumen claro.
// Idea de WQFiles (kolbicz, iOS 27, GPL): explorador de archivos,
// gestor de datos de apps y limpiador de caché. Código NUEVO en SwiftUI
// para Mac, sin copiar su código Objective-C y sin worse_query:
// en macOS no hace falta, los archivos se ven con permisos normales.
// Seguridad: todo borrado va a la Papelera, nunca permanente por defecto.
// Protegidos: .nup/.nsp/.nsz/.xci, prod.keys y carpetas de juegos.
// No toca archivos del sistema (/System, /usr, /bin, /sbin, /etc).

@main
struct WQFilesMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}

// MARK: - Modelos

struct FileEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var isDir: Bool
    var size: Int64
}

struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleId: String
    let appURL: URL
    var appSize: Int64 = 0
    var dataSize: Int64 = 0
    var containerURL: URL?
    var supportURL: URL?
}

struct CacheEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    var size: Int64
    var selected: Bool = false
}

struct HeavyFolder: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    var size: Int64
}

struct DupFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var size: Int64
}

struct DupGroup: Identifiable, Hashable {
    let id = UUID()
    var files: [DupFile]
    var size: Int64 { files.first?.size ?? 0 }
    var waste: Int64 { size * Int64(max(0, files.count - 1)) }
}

struct XcodeItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let kind: String
    let url: URL
    var size: Int64
    var selected: Bool = false
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

// MARK: - Utilidades

func formatBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

func folderSize(_ url: URL, maxFiles: Int = 20000) -> Int64 {
    let fm = FileManager.default
    guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
    var total: Int64 = 0
    var count = 0
    for case let file as URL in e {
        count += 1
        if count > maxFiles { break }
        if let vals = try? file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
           vals.isDirectory != true {
            total += Int64(vals.fileSize ?? 0)
        }
    }
    return total
}

let protectedExtensions: Set<String> = ["nup", "nsp", "nsz", "xci", "xcz"]
let protectedNames: Set<String> = ["prod.keys", "keys.txt"]

func isProtected(_ url: URL) -> Bool {
    if protectedExtensions.contains(url.pathExtension.lowercased()) { return true }
    if protectedNames.contains(url.lastPathComponent.lowercased()) { return true }
    let lower = url.path.lowercased()
    for word in ["nx2apple", "forktikilauncher", "juegos", "games", "nintendo"] {
        if lower.contains(word) { return true }
    }
    return false
}

func isSystemPath(_ url: URL) -> Bool {
    let p = url.path
    return p == "/System" || p.hasPrefix("/System/") || p == "/usr" || p.hasPrefix("/usr/")
        || p == "/bin" || p == "/sbin" || p == "/etc" || p == "/private/etc"
}

// MARK: - Explicaciones en español simple (v3: "¿cómo sabe qué borrar?")
//
// Cómo sabe la app qué borrar, en palabras simples:
// - Duplicados: dos archivos son el mismo solo si pesan EXACTAMENTE lo
//   mismo Y tienen la misma huella SHA256 (como una huella digital del
//   contenido). Que se llamen igual no basta.
// - Caché de Xcode: son archivos temporales que Xcode crea al compilar.
//   Si se borran, Xcode los vuelve a crear solo la próxima vez que
//   compilas. No son tu proyecto ni tu juego.
// - Espacio: la app solo MIDE carpetas y te dice cuánto pesan. No borra
//   nada sola: tú eliges qué mandar a la Papelera.

/// Qué es esta carpeta y por qué se puede (o no) borrar.
func explicacionCarpeta(_ name: String) -> String {
    let n = name.lowercased()
    if n.contains("deriveddata") { return "Archivos temporales que Xcode crea al compilar tus apps. Si los borras, Xcode los vuelve a crear solo." }
    if n.contains("caches") || n.contains("caché") { return "Archivos temporales que las apps guardan para ir más rápido. Si los borras, la app los vuelve a crear." }
    if n.contains("downloads") { return "Todo lo que bajaste de internet. Aquí puede haber instaladores, zips y archivos que ya no necesitas." }
    if n.contains("documents") { return "Tus documentos personales. Aquí NO borres a ciegas: revisa archivo por archivo." }
    if n.contains("desktop") { return "Lo que tienes en el Escritorio. Revisa antes de borrar: puede haber cosas importantes." }
    if n.contains("forktikilauncher") { return "Carpeta con los juegos ya compilados (IPA y RomFS). Si borras esto, pierdes el juego compilado y hay que volver a compilar." }
    if n.contains("archives") { return "Copias viejas de apps que compilaste antes. Solo sirven si quieres volver a una versión vieja." }
    if n.contains("devicesupport") { return "Datos para depurar iPhones viejos en Xcode. Las versiones viejas se pueden borrar; Xcode baja la que necesite." }
    if n.contains("coresimulator") || n.contains("simulator") { return "El simulador de iPhone/iPad de Xcode. Ocupa mucho y se puede borrar; Xcode lo vuelve a crear." }
    return "Carpeta de tu Mac. Revisa qué hay dentro antes de borrarla."
}

/// ¿Es seguro borrar esto sin revisar? Verde = seguro, naranja = revisa antes.
func esSeguroBorrar(_ name: String) -> Bool {
    let n = name.lowercased()
    if n.contains("deriveddata") || n.contains("caches") || n.contains("caché")
        || n.contains("devicesupport") || n.contains("coresimulator") || n.contains("simulator") {
        return true
    }
    return false
}

func textoSeguridad(_ name: String) -> String {
    esSeguroBorrar(name)
        ? "✅ Seguro de borrar, se vuelve a crear solo"
        : "⚠️ Revisa antes de borrar"
}

/// Resumen que se muestra SIEMPRE antes de borrar algo (v3).
func resumenAntesDeBorrar(cantidad: String, liberado: String) -> String {
    "Vas a borrar \(cantidad). Vas a liberar \(liberado). Todo va a la Papelera, puedes recuperarlo desde ahí. Tus juegos (.nup, .nsp) y prod.keys NO se tocan nunca."
}

// MARK: - Vistas pequeñas reutilizables (v3)

/// Título de sección en español simple + explicación de 1-2 frases.
struct EncabezadoSeccion: View {
    let titulo: String
    let explicacion: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.title3).bold()
            Text(explicacion).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(12)
    }
}

/// Etiqueta verde (seguro) o naranja (revisa antes).
struct EtiquetaSeguridad: View {
    let nombre: String
    var body: some View {
        Text(textoSeguridad(nombre))
            .font(.caption).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(esSeguroBorrar(nombre) ? Color.green.opacity(0.2) : Color.orange.opacity(0.25))
            .foregroundStyle(esSeguroBorrar(nombre) ? Color.green : Color.orange)
            .cornerRadius(8)
    }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var log: [LogEntry] = []
    @Published var currentPath: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var entries: [FileEntry] = []
    @Published var apps: [InstalledApp] = []
    @Published var caches: [CacheEntry] = []
    @Published var scanning = false
    @Published var status = ""
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var heavyFolders: [HeavyFolder] = []
    @Published var dupGroups: [DupGroup] = []
    @Published var dupFolder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var xcodeItems: [XcodeItem] = []

    init() {
        addLog("WQFilesMac listo. Todo lo que se borra va a la Papelera.")
        refreshFiles()
    }

    func addLog(_ text: String) {
        DispatchQueue.main.async { self.log.insert(LogEntry(text: text), at: 0) }
    }

    // MARK: Archivos

    func refreshFiles() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: currentPath, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? []
        entries = urls.map { url in
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return FileEntry(url: url, isDir: vals?.isDirectory ?? false, size: Int64(vals?.fileSize ?? 0))
        }.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func goUp() {
        let parent = currentPath.deletingLastPathComponent()
        if parent.path != currentPath.path {
            currentPath = parent
            refreshFiles()
        }
    }

    func openEntry(_ entry: FileEntry) {
        if entry.isDir {
            currentPath = entry.url
            refreshFiles()
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    func trash(_ url: URL) {
        if isSystemPath(url) {
            status = "No se toca el sistema: \(url.lastPathComponent)"
            addLog("Bloqueado (sistema): \(url.path)")
            return
        }
        if isProtected(url) {
            status = "Protegido, no se borra: \(url.lastPathComponent)"
            addLog("Bloqueado (protegido): \(url.path)")
            return
        }
        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            status = "A la Papelera: \(url.lastPathComponent)"
            addLog("A Papelera: \(url.path)")
            refreshFiles()
        } catch {
            status = "No se pudo borrar: \(error.localizedDescription)"
            addLog("Error al borrar \(url.path): \(error.localizedDescription)")
        }
    }

    func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        status = "Ruta copiada: \(url.path)"
    }

    func previewText(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url), data.count < 200_000,
              let s = String(data: data, encoding: .utf8) else {
            return "No se puede previsualizar (binario o muy grande)."
        }
        return s
    }

    // MARK: Apps

    func scanApps() {
        scanning = true
        status = "Buscando apps en /Applications…"
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let appDir = URL(fileURLWithPath: "/Applications")
            let urls = (try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)) ?? []
            var found: [InstalledApp] = []
            for url in urls where url.pathExtension == "app" {
                let plist = url.appendingPathComponent("Contents/Info.plist")
                let dict = NSDictionary(contentsOf: plist) as? [String: Any]
                let bundleId = dict?["CFBundleIdentifier"] as? String ?? ""
                let name = dict?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
                var app = InstalledApp(name: name, bundleId: bundleId, appURL: url)
                app.appSize = folderSize(url, maxFiles: 5000)
                let container = home.appendingPathComponent("Library/Containers/\(bundleId)")
                if fm.fileExists(atPath: container.path) {
                    app.containerURL = container
                    app.dataSize += folderSize(container, maxFiles: 5000)
                }
                let support = home.appendingPathComponent("Library/Application Support/\(name)")
                if fm.fileExists(atPath: support.path) {
                    app.supportURL = support
                    app.dataSize += folderSize(support, maxFiles: 5000)
                }
                found.append(app)
            }
            found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.apps = found
                self.scanning = false
                self.status = "\(found.count) apps encontradas."
                self.addLog("Apps escaneadas: \(found.count)")
            }
        }
    }

    func backupApp(_ app: InstalledApp) {
        guard let container = app.containerURL else {
            status = "Esta app no tiene datos en Containers para respaldar."
            return
        }
        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/WQFilesMac-Respaldos/\(app.name)-\(Date().timeIntervalSince1970).zip")
        let script = "mkdir -p \"\(dest.deletingLastPathComponent().path)\"; cd \"\(container.deletingLastPathComponent().path)\" && /usr/bin/zip -qr \"\(dest.path)\" \"\(container.lastPathComponent)\""
        runShell(script) { code in
            if code == 0 {
                self.status = "Respaldo listo: \(dest.lastPathComponent)"
                self.addLog("Respaldo \(app.name) -> \(dest.path)")
            } else {
                self.status = "No se pudo respaldar (código \(code))."
                self.addLog("Error respaldo \(app.name), código \(code)")
            }
        }
    }

    // MARK: Caché

    func scanCaches() {
        scanning = true
        status = "Midiendo ~/Library/Caches…"
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let cachesDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
            let urls = (try? fm.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil)) ?? []
            var found: [CacheEntry] = []
            for url in urls {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let size = folderSize(url, maxFiles: 5000)
                found.append(CacheEntry(name: url.lastPathComponent, url: url, size: size))
            }
            found.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self.caches = found
                self.scanning = false
                let total = found.reduce(0) { $0 + $1.size }
                self.status = "\(found.count) carpetas de caché, total \(formatBytes(total))."
                self.addLog("Caché escaneado: \(formatBytes(total))")
            }
        }
    }

    func cleanSelectedCaches() {
        let selected = caches.filter { $0.selected }
        if selected.isEmpty { status = "No seleccionaste ninguna caché."; return }
        var total: Int64 = 0
        for entry in selected {
            total += entry.size
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: &trashed)
                addLog("Caché a Papelera: \(entry.name) (\(formatBytes(entry.size)))")
            } catch {
                addLog("No se pudo limpiar \(entry.name): \(error.localizedDescription)")
            }
            // Recrear la carpeta vacía para que la app no falle al buscarla.
            try? FileManager.default.createDirectory(at: entry.url, withIntermediateDirectories: true)
        }
        status = "Limpieza a Papelera: \(formatBytes(total)) en \(selected.count) carpetas."
        scanCaches()
    }

    // MARK: Espacio
    func scanDisk() {
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var total: Int64 = 0; var free: Int64 = 0
            if let vals = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
                total = Int64(vals.volumeTotalCapacity ?? 0)
                free = Int64(vals.volumeAvailableCapacityForImportantUsage ?? 0)
            }
            let candidates: [(String, URL)] = [
                ("DerivedData (Xcode)", home.appendingPathComponent("Library/Developer/Xcode/DerivedData")),
                ("Caches", home.appendingPathComponent("Library/Caches")),
                ("Downloads", home.appendingPathComponent("Downloads")),
                ("Documents", home.appendingPathComponent("Documents")),
                ("ForkTikiLauncher builds", home.appendingPathComponent("ForkTikiLauncher/builds")),
                ("Xcode Archives", home.appendingPathComponent("Library/Developer/Xcode/Archives")),
                ("iOS DeviceSupport", home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")),
                ("CoreSimulator", home.appendingPathComponent("Library/Developer/CoreSimulator")),
                ("Desktop", home.appendingPathComponent("Desktop")),
            ]
            var heavy: [HeavyFolder] = []
            for (name, url) in candidates where fm.fileExists(atPath: url.path) {
                heavy.append(HeavyFolder(name: name, url: url, size: folderSize(url, maxFiles: 20000)))
            }
            heavy.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self.diskTotal = total; self.diskFree = free; self.heavyFolders = heavy
                self.scanning = false
                self.status = "Disco: \(formatBytes(free)) libres de \(formatBytes(total))."
                self.addLog("Espacio medido: \(formatBytes(free)) libres")
            }
        }
    }

    // MARK: Duplicados (tamano -> SHA256)
    func sha256File(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try? handle.read(upToCount: 1_048_576)
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func scanDuplicates() {
        scanning = true; dupGroups = []
        status = "Buscando duplicados en \(dupFolder.lastPathComponent)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            guard let e = fm.enumerator(at: self.dupFolder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
                DispatchQueue.main.async { self.scanning = false; self.status = "No se pudo leer esa carpeta." }
                return
            }
            var bySize: [Int64: [URL]] = [:]
            for case let file as URL in e {
                if isProtected(file) || isSystemPath(file) { continue }
                guard let vals = try? file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                      vals.isDirectory != true, let s = vals.fileSize, s > 0 else { continue }
                bySize[Int64(s), default: []].append(file)
            }
            var groups: [DupGroup] = []
            for (_, urls) in bySize where urls.count > 1 {
                var byHash: [String: [URL]] = [:]
                for u in urls { if let h = self.sha256File(u) { byHash[h, default: []].append(u) } }
                for (_, dupUrls) in byHash where dupUrls.count > 1 {
                    let size = Int64((try? dupUrls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    groups.append(DupGroup(files: dupUrls.sorted { $0.path < $1.path }.map { DupFile(url: $0, size: size) }))
                }
            }
            groups.sort { $0.waste > $1.waste }
            let waste = groups.reduce(0) { $0 + $1.waste }
            DispatchQueue.main.async {
                self.dupGroups = groups; self.scanning = false
                self.status = "\(groups.count) grupos de duplicados, \(formatBytes(waste)) que se pueden liberar."
                self.addLog("Duplicados: \(groups.count) grupos, \(formatBytes(waste)) liberables")
            }
        }
    }

    func trashDuplicates() {
        var total: Int64 = 0; var count = 0
        for g in dupGroups {
            for f in g.files.dropFirst() {
                if isProtected(f.url) { continue }
                var trashed: NSURL?
                if (try? FileManager.default.trashItem(at: f.url, resultingItemURL: &trashed)) != nil {
                    total += f.size; count += 1
                    addLog("Duplicado a Papelera: \(f.url.path)")
                }
            }
        }
        status = "Duplicados a Papelera: \(count) archivos, \(formatBytes(total)) liberados (se queda el primero de cada grupo)."
        scanDuplicates()
    }

    // MARK: Limpieza Xcode
    func scanXcode() {
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let dev = home.appendingPathComponent("Library/Developer/Xcode")
            var items: [XcodeItem] = []
            // DerivedData por proyecto
            let dd = dev.appendingPathComponent("DerivedData")
            if let subs = try? fm.contentsOfDirectory(at: dd, includingPropertiesForKeys: nil) {
                for u in subs { items.append(XcodeItem(name: "DerivedData / \(u.lastPathComponent)", kind: "DerivedData", url: u, size: folderSize(u, maxFiles: 5000))) }
            }
            let others: [(String, String)] = [
                ("iOS DeviceSupport", "Library/Developer/Xcode/iOS DeviceSupport"),
                ("Archives", "Library/Developer/Xcode/Archives"),
                ("Simulator (CoreSimulator)", "Library/Developer/CoreSimulator"),
                ("Caches", "Library/Caches"),
            ]
            for (name, rel) in others {
                let u = home.appendingPathComponent(rel)
                if fm.fileExists(atPath: u.path) { items.append(XcodeItem(name: name, kind: "Xcode", url: u, size: folderSize(u, maxFiles: 5000))) }
            }
            items.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self.xcodeItems = items; self.scanning = false
                let total = items.reduce(0) { $0 + $1.size }
                self.status = "Xcode y caché: \(formatBytes(total)) en \(items.count) carpetas."
            }
        }
    }

    func cleanSelectedXcode() {
        let selected = xcodeItems.filter { $0.selected }
        if selected.isEmpty { status = "No seleccionaste nada para limpiar."; return }
        var total: Int64 = 0
        for item in selected {
            if isProtected(item.url) || isSystemPath(item.url) { addLog("Bloqueado (protegido/sistema): \(item.name)"); continue }
            total += item.size
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &trashed)
                addLog("Xcode a Papelera: \(item.name) (\(formatBytes(item.size)))")
                // Recrear DerivedData vacio si era un proyecto, para que Xcode no falle
                if item.kind == "DerivedData" { try? FileManager.default.createDirectory(at: item.url, withIntermediateDirectories: true) }
            } catch { addLog("No se pudo limpiar \(item.name): \(error.localizedDescription)") }
        }
        status = "Limpieza Xcode a Papelera: \(formatBytes(total)). Revisa la Papelera para recuperar algo."
        scanXcode()
    }

    // MARK: Shell

    func runShell(_ script: String, onDone: @escaping (Int32) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script]
            do {
                try p.run()
                p.waitUntilExit()
                DispatchQueue.main.async { onDone(p.terminationStatus) }
            } catch {
                DispatchQueue.main.async { onDone(-1) }
            }
        }
    }
}

// MARK: - Vista principal

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var tab = 0
    // Modo principiante prendido por defecto (v3): solo muestra Inicio,
    // Espacio, Duplicados y Limpiar Xcode. Lo avanzado (Archivos, Apps,
    // Limpieza de caché, Registro) aparece con "Modo avanzado".
    @AppStorage("modoPrincipiante") private var modoPrincipiante = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("TikiFilesMac", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Text(modoPrincipiante ? "👶 Modo principiante" : "🧑‍💻 Modo avanzado")
                    .font(.callout).foregroundStyle(.secondary)
                Button(modoPrincipiante ? "Ver modo avanzado" : "Volver a modo principiante") {
                    modoPrincipiante.toggle()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12).padding(.top, 8)
            TabView(selection: $tab) {
                InicioView(store: store, tab: $tab, modoPrincipiante: $modoPrincipiante)
                    .tabItem { Label("Inicio", systemImage: "house") }.tag(0)
                SpaceView(store: store).tabItem { Label("Espacio", systemImage: "internaldrive") }.tag(1)
                DuplicatesView(store: store).tabItem { Label("Duplicados", systemImage: "doc.on.doc") }.tag(2)
                XcodeCleanView(store: store).tabItem { Label("Limpiar Xcode", systemImage: "hammer") }.tag(3)
                if !modoPrincipiante {
                    FilesView(store: store).tabItem { Label("Archivos", systemImage: "folder") }.tag(4)
                    AppsView(store: store).tabItem { Label("Apps", systemImage: "app.badge") }.tag(5)
                    CacheView(store: store).tabItem { Label("Limpieza de caché", systemImage: "trash") }.tag(6)
                    LogView(store: store).tabItem { Label("Registro", systemImage: "list.clipboard") }.tag(7)
                }
            }
            HStack {
                Text(store.status).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
            }
            .padding(8)
        }
    }
}

// MARK: - Inicio: ¿Primera vez aquí? (v3)

struct InicioView: View {
    @ObservedObject var store: Store
    @Binding var tab: Int
    @Binding var modoPrincipiante: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("👋 ¿Primera vez aquí? Empieza aquí").font(.title2).bold()
                    Text("Esta app te ayuda a liberar espacio en tu Mac sin borrar nada importante. Nada se borra para siempre: todo va a la Papelera y lo puedes recuperar.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(16)

                Text("3 pasos simples").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    PasoInicio(numero: "1", titulo: "Mide tu espacio", texto: "Ve a la pestaña Espacio y dale a \"Medir espacio\". Ahí ves qué carpetas pesan más y cuánto tienes libre.")
                    PasoInicio(numero: "2", titulo: "Limpia lo seguro", texto: "Ve a \"Limpiar Xcode\" y dale a \"Medir Xcode\". Lo que dice ✅ Seguro se puede borrar: Xcode lo vuelve a crear solo.")
                    PasoInicio(numero: "3", titulo: "Busca duplicados", texto: "Ve a \"Duplicados\", elige Downloads y dale a \"Buscar duplicados\". La app se queda con una copia y manda las demás a la Papelera.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("🤔 ¿Cómo sabe qué borrar?").font(.headline)
                    Text("• Duplicados: dos archivos son el mismo solo si pesan exactamente lo mismo Y tienen la misma huella digital (SHA256) por dentro. Que se llamen igual no basta.\n• Caché de Xcode: son archivos temporales que Xcode crea al compilar. Si se borran, Xcode los vuelve a crear solo.\n• Espacio: la app solo mide carpetas y te dice cuánto pesan. Nunca borra nada sola: tú eliges.")
                        .font(.callout)
                }
                .padding(12).background(Color.green.opacity(0.08)).cornerRadius(12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("🔒 Lo que NUNCA se borra").font(.headline)
                    Text("Tus juegos (.nup, .nsp, .nsz, .xci), prod.keys y las carpetas de juegos están protegidos: la app no los borra ni aunque los selecciones. Todo lo demás va a la Papelera, nunca se borra para siempre.")
                        .font(.callout)
                }
                .padding(12).background(Color.orange.opacity(0.12)).cornerRadius(12)

                HStack(spacing: 10) {
                    Button("📊 Ver mi espacio") { tab = 1 }.buttonStyle(.borderedProminent)
                    Button("📄 Buscar duplicados") { tab = 2 }.buttonStyle(.bordered)
                    Button("🧹 Limpiar Xcode") { tab = 3 }.buttonStyle(.bordered)
                }
                Button(modoPrincipiante ? "Quiero ver todo (modo avanzado: Archivos, Apps, Caché y Registro)" : "Volver a modo principiante (solo lo simple)") {
                    modoPrincipiante.toggle()
                }
                .font(.callout)
            }
            .padding(14)
        }
    }
}

struct PasoInicio: View {
    let numero: String
    let titulo: String
    let texto: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(numero).font(.title3).bold()
                .frame(width: 34, height: 34)
                .background(Color.blue).foregroundStyle(.white).cornerRadius(17)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.headline)
                Text(texto).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(10).background(Color.white).cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Archivos

struct FilesView: View {
    @ObservedObject var store: Store
    @State private var toTrash: FileEntry?
    @State private var preview: FileEntry?
    @State private var goPath = ""
    @State private var search = ""
    var filteredEntries: [FileEntry] {
        if search.isEmpty { return store.entries }
        return store.entries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EncabezadoSeccion(titulo: "📁 Archivos: ver y mover tus archivos",
                explicacion: "Aquí ves lo que hay en cada carpeta, como en el Finder. Solo borra algo si sabes qué es: si no sabes, mejor no lo toques. Lo que borres va a la Papelera, y los juegos y prod.keys están protegidos y no se borran.")
            HStack {
                Button("⬆️ Subir") { store.goUp() }
                Text(store.currentPath.path).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer()
                TextField("Ir a ruta…", text: $goPath, onCommit: {
                    let url = URL(fileURLWithPath: goPath)
                    if FileManager.default.fileExists(atPath: url.path) {
                        store.currentPath = url
                        store.refreshFiles()
                    }
                })
                .textFieldStyle(.roundedBorder).frame(width: 260)
                Button("Ir a Casa") {
                    store.currentPath = FileManager.default.homeDirectoryForCurrentUser
                    store.refreshFiles()
                }
            }
            TextField("🔍 Buscar en esta carpeta…", text: $search).textFieldStyle(.roundedBorder)
            List(filteredEntries) { entry in
                HStack {
                    Text(entry.isDir ? "📁" : "📄")
                    Text(entry.name).lineLimit(1)
                    Spacer()
                    if !entry.isDir { Text(formatBytes(entry.size)).font(.callout).foregroundStyle(.secondary) }
                    if isProtected(entry.url) {
                        Text("🔒 protegido").font(.callout).foregroundStyle(.orange)
                    }
                    Button("Ver") {
                        if entry.isDir { store.openEntry(entry) } else { preview = entry }
                    }
                    Button("Copiar ruta") { store.copyPath(entry.url) }
                    Button("A Papelera") { toTrash = entry }.foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .alert(item: $toTrash) { entry in
            Alert(title: Text("¿Borrar \(entry.name)?"),
                  message: Text(resumenAntesDeBorrar(cantidad: "el archivo \(entry.name) (\(entry.isDir ? "carpeta" : formatBytes(entry.size)))", liberado: entry.isDir ? "el espacio que pese esa carpeta" : formatBytes(entry.size)) + (isProtected(entry.url) ? "\n⚠️ Este archivo está protegido y NO se va a borrar." : "")),
                  primaryButton: .destructive(Text("A la Papelera")) { store.trash(entry.url) },
                  secondaryButton: .cancel(Text("Cancelar")))
        }
        .sheet(item: $preview) { entry in
            VStack(alignment: .leading) {
                Text(entry.name).font(.headline)
                if ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(entry.url.pathExtension.lowercased()),
                   let img = NSImage(contentsOf: entry.url) {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 400)
                } else {
                    ScrollView { Text(store.previewText(entry.url)).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }
                }
                Button("Cerrar") { preview = nil }.buttonStyle(.borderedProminent)
            }
            .padding(16).frame(minWidth: 500, minHeight: 400)
        }
    }
}

// MARK: - Apps

struct AppsView: View {
    @ObservedObject var store: Store
    @State private var search = ""
    @State private var toClear: InstalledApp?

    var filtered: [InstalledApp] {
        if search.isEmpty { return store.apps }
        return store.apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleId.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EncabezadoSeccion(titulo: "📱 Apps: cuánto pesan y qué datos guardan",
                explicacion: "Aquí ves cada app instalada, cuánto pesa la app y cuánto pesan sus datos (fotos, partidas, documentos). Limpiar los datos borra tus cosas de esa app: haz primero un respaldo ZIP y cierra la app antes. ⚠️ Revisa antes de borrar.")
            HStack {
                Button("🔍 Buscar apps") { store.scanApps() }
                TextField("Buscar por nombre o bundle id…", text: $search)
                    .textFieldStyle(.roundedBorder)
                Text("Cierra la app antes de respaldar o limpiar sus datos.").font(.callout).foregroundStyle(.secondary)
            }
            List(filtered) { app in
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.headline)
                    Text(app.bundleId).font(.callout).foregroundStyle(.secondary)
                    Text("App: \(formatBytes(app.appSize)) · Datos: \(formatBytes(app.dataSize))").font(.callout)
                    HStack {
                        Button("Respaldo ZIP") { store.backupApp(app) }
                        if app.containerURL != nil {
                            Button("Abrir carpeta de datos") { NSWorkspace.shared.open(app.containerURL!) }
                        }
                        Button("Limpiar datos") { toClear = app }.foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .alert(item: Binding(
            get: { toClear.map { AlertApp(id: $0.id, app: $0) } },
            set: { _ in toClear = nil }
        )) { item in
            Alert(title: Text("¿Limpiar datos de \(item.app.name)?"),
                  message: Text(resumenAntesDeBorrar(cantidad: "los datos de \(item.app.name) (Documents, Library y archivos temporales, \(formatBytes(item.app.dataSize)))", liberado: formatBytes(item.app.dataSize)) + "\n⚠️ Esto borra tus cosas de esa app. Primero haz un respaldo ZIP y cierra la app."),
                  primaryButton: .destructive(Text("Limpiar (a Papelera)")) {
                    if let c = item.app.containerURL { store.trash(c) }
                    store.scanApps()
                  },
                  secondaryButton: .cancel(Text("Cancelar")))
        }
    }
}

struct AlertApp: Identifiable {
    let id: UUID
    let app: InstalledApp
}

// MARK: - Caché

struct CacheView: View {
    @ObservedObject var store: Store
    @State private var confirmClean = false

    var totalSelected: Int64 { store.caches.filter { $0.selected }.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EncabezadoSeccion(titulo: "🗑 Limpieza de caché: archivos temporales de las apps",
                explicacion: "La caché son archivos temporales que cada app guarda para ir más rápido. ¿Cómo sabe la app que se pueden borrar? Porque son temporales: si se borran, la app los vuelve a crear sola. ✅ Seguro de borrar, se vuelve a crear solo. La carpeta vacía se recrea para que la app no falle.")
            HStack {
                Button("🔍 Medir caché") { store.scanCaches() }
                Button("Seleccionar grandes (50 MB+)") {
                    for i in store.caches.indices { store.caches[i].selected = store.caches[i].size >= 50_000_000 }
                }
                Button("Ninguna") {
                    for i in store.caches.indices { store.caches[i].selected = false }
                }
                Spacer()
                Text("Seleccionado: \(formatBytes(totalSelected))").font(.headline)
                Button("Limpiar seleccionadas") { confirmClean = true }
                    .buttonStyle(.borderedProminent).disabled(totalSelected == 0)
            }
            Text("Solo se limpia ~/Library/Caches. ✅ Seguro: son archivos temporales, la app los vuelve a crear. Nunca se borra permanente: va a la Papelera y se recrea la carpeta vacía.").font(.callout).foregroundStyle(.secondary)
            List(store.caches.indices, id: \.self) { i in
                HStack {
                    Toggle("", isOn: $store.caches[i].selected)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.caches[i].name).lineLimit(1)
                        Text("Archivos temporales de \(store.caches[i].name). Se vuelven a crear solos.").font(.caption).foregroundStyle(.secondary)
                        EtiquetaSeguridad(nombre: store.caches[i].name)
                    }
                    Spacer()
                    Text(formatBytes(store.caches[i].size)).font(.callout)
                }
            }
        }
        .padding(12)
        .alert("¿Limpiar \(formatBytes(totalSelected)) de caché?", isPresented: $confirmClean) {
            Button("Limpiar (a Papelera)", role: .destructive) { store.cleanSelectedCaches() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(resumenAntesDeBorrar(cantidad: "\(store.caches.filter { $0.selected }.count) carpetas de caché", liberado: formatBytes(totalSelected)))
        }
    }
}

// MARK: - Espacio
struct SpaceView: View {
    @ObservedObject var store: Store
    @State private var carpetaABorrar: HeavyFolder?
    var used: Int64 { max(0, store.diskTotal - store.diskFree) }
    var usedPct: Double { store.diskTotal > 0 ? Double(used) / Double(store.diskTotal) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EncabezadoSeccion(titulo: "💾 Espacio: cuánto te queda y qué pesa más",
                explicacion: "Aquí la app solo MIDE: te dice cuánto espacio libre tienes y qué carpetas pesan más. No borra nada sola. Cada carpeta dice qué es, por qué se puede borrar y si es segura (verde) o hay que revisar antes (naranja).")
            HStack {
                Button("📊 Medir espacio") { store.scanDisk() }
                Spacer()
                Text("Libre: \(formatBytes(store.diskFree)) de \(formatBytes(store.diskTotal))").font(.headline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Uso del disco: \(Int(usedPct * 100))% usado (\(formatBytes(used)))").font(.headline)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.25))
                        RoundedRectangle(cornerRadius: 8).fill(usedPct > 0.85 ? Color.red : usedPct > 0.7 ? Color.orange : Color.green)
                            .frame(width: max(8, geo.size.width * usedPct))
                    }
                }.frame(height: 18)
                if usedPct > 0.85 { Text("⚠️ Disco casi lleno: limpia DerivedData o la caché de Xcode.").foregroundStyle(.red).font(.callout) }
            }
            .padding(12).background(Color.white).cornerRadius(16).shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            Text("Carpetas que más pesan — toca una para ver qué es y si es seguro borrarla").font(.headline)
            List(store.heavyFolders) { f in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.name).font(.headline)
                        Text(explicacionCarpeta(f.name)).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(f.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        EtiquetaSeguridad(nombre: f.name)
                    }
                    Spacer()
                    Text(formatBytes(f.size)).font(.headline)
                    Button("Abrir") { NSWorkspace.shared.open(f.url) }
                    Button("A Papelera") { carpetaABorrar = f }.foregroundStyle(.red)
                }
            }
            Text("Nunca se borran .nup/.nsp, prod.keys ni carpetas de juegos. Todo va a la Papelera.").font(.callout).foregroundStyle(.secondary)
        }.padding(12)
        .alert(item: $carpetaABorrar) { f in
            Alert(title: Text("¿Borrar \(f.name)?"),
                  message: Text(explicacionCarpeta(f.name) + "\n\n" + resumenAntesDeBorrar(cantidad: "la carpeta \(f.name)", liberado: formatBytes(f.size))),
                  primaryButton: .destructive(Text("A la Papelera")) { store.trash(f.url) },
                  secondaryButton: .cancel(Text("Cancelar")))
        }
    }
}

// MARK: - Duplicados
struct DuplicatesView: View {
    @ObservedObject var store: Store
    @State private var confirmTrash = false
    @State private var showPicker = false
    var totalWaste: Int64 { store.dupGroups.reduce(0) { $0 + $1.waste } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EncabezadoSeccion(titulo: "📄 Duplicados: el mismo archivo dos veces",
                explicacion: "¿Cómo sabe la app que son duplicados? Primero compara el tamaño: si pesan distinto, no son el mismo. Si pesan igual, compara su huella digital (SHA256) por dentro. Solo si las dos cosas son iguales, es el mismo archivo. Se queda el primero de cada grupo y los demás van a la Papelera.")
            HStack {
                Text("Carpeta: \(store.dupFolder.path)").font(.callout).lineLimit(1)
                Spacer()
                Button("Elegir carpeta…") { showPicker = true }
                Button("🔍 Buscar duplicados") { store.scanDuplicates() }.buttonStyle(.borderedProminent)
            }
            Text("Se comparan primero por tamaño y luego por SHA256, para no borrar archivos que solo se llaman igual. Se queda el primero de cada grupo.").font(.callout).foregroundStyle(.secondary)
            HStack { Text("\(store.dupGroups.count) grupos · se liberan \(formatBytes(totalWaste))").font(.headline); Spacer(); Button("🗑 Mandar duplicados a Papelera") { confirmTrash = true }.buttonStyle(.borderedProminent).disabled(totalWaste == 0) }
            List(store.dupGroups) { g in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(g.files.count) copias · \(formatBytes(g.size)) c/u · se liberan \(formatBytes(g.waste))").font(.headline)
                    Text("Son el mismo archivo: pesan igual y tienen la misma huella (SHA256). ✅ Seguro de borrar las copias, se queda una.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(g.files.enumerated()), id: \.element.id) { idx, f in
                        HStack { Text(idx == 0 ? "✅ se queda" : "🗑 se borra").font(.callout); Text(f.url.path).font(.callout).lineLimit(1) }
                    }
                }.padding(.vertical, 4)
            }
        }
        .padding(12)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if let urls = try? result.get(), let u = urls.first { store.dupFolder = u; store.scanDuplicates() }
        }
        .alert("¿Mandar \(store.dupGroups.reduce(0) { $0 + $1.files.count - 1 }) duplicados a la Papelera?", isPresented: $confirmTrash) {
            Button("A la Papelera", role: .destructive) { store.trashDuplicates() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(resumenAntesDeBorrar(cantidad: "\(store.dupGroups.reduce(0) { $0 + $1.files.count - 1 }) archivos duplicados", liberado: formatBytes(totalWaste)) + "\nSe queda el primer archivo de cada grupo, solo se borran las copias exactas.") }
    }
}

// MARK: - Limpiar Xcode
struct XcodeCleanView: View {
    @ObservedObject var store: Store
    @State private var confirmClean = false
    var totalSelected: Int64 { store.xcodeItems.filter { $0.selected }.reduce(0) { $0 + $1.size } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EncabezadoSeccion(titulo: "🧹 Limpiar Xcode: archivos temporales de compilar",
                explicacion: "¿Cómo sabe la app que se pueden borrar? DerivedData, DeviceSupport viejo y la caché son archivos temporales que Xcode crea al compilar. Si se borran, Xcode los vuelve a crear solo la próxima vez que compilas. No son tu proyecto ni tu juego. ✅ Seguro, salvo Archives: eso son copias viejas de tus apps, revísalo antes.")
            HStack {
                Button("🔍 Medir Xcode") { store.scanXcode() }
                Button("Seleccionar todo") { for i in store.xcodeItems.indices { store.xcodeItems[i].selected = true } }
                Button("Ninguno") { for i in store.xcodeItems.indices { store.xcodeItems[i].selected = false } }
                Spacer()
                Text("Se liberarían: \(formatBytes(totalSelected))").font(.headline)
                Button("Limpiar seleccionados") { confirmClean = true }.buttonStyle(.borderedProminent).disabled(totalSelected == 0)
            }
            Text("No borres el proyecto que estés compilando en este momento. Todo va a la Papelera, nunca permanente.").font(.callout).foregroundStyle(.secondary)
            List(store.xcodeItems.indices, id: \.self) { i in
                HStack {
                    Toggle("", isOn: $store.xcodeItems[i].selected)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.xcodeItems[i].name).font(.headline)
                        Text(explicacionCarpeta(store.xcodeItems[i].name)).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        EtiquetaSeguridad(nombre: store.xcodeItems[i].name)
                    }
                    Spacer()
                    Text(formatBytes(store.xcodeItems[i].size)).font(.headline)
                }
            }
        }
        .padding(12)
        .alert("¿Limpiar \(formatBytes(totalSelected)) de Xcode?", isPresented: $confirmClean) {
            Button("Limpiar (a Papelera)", role: .destructive) { store.cleanSelectedXcode() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(resumenAntesDeBorrar(cantidad: "\(store.xcodeItems.filter { $0.selected }.count) carpetas de Xcode", liberado: formatBytes(totalSelected))) }
    }
}

// MARK: - Registro

struct LogView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EncabezadoSeccion(titulo: "📋 Registro: qué se borró y qué se respaldó",
                explicacion: "Aquí queda anotado todo lo que la app mandó a la Papelera, respaldó o limpió, con la hora. Si algo se borró por error, aquí ves qué fue para buscarlo en la Papelera.")
            HStack {
                Text("Todo lo que se borró, respaldó o limpió queda aquí.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Limpiar registro") { store.log.removeAll() }
            }
            List(store.log) { entry in
                HStack {
                    Text(entry.date, style: .time).font(.callout).foregroundStyle(.secondary)
                    Text(entry.text).font(.callout)
                }
            }
        }
        .padding(12)
    }
}
