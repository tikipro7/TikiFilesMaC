import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit

// WQFilesMac — v2 (10 nov 2026): Espacio, Duplicados, Limpieza Xcode, diseño con tarjetas
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
    @State private var showWelcome = true

    var body: some View {
        VStack(spacing: 0) {
            if showWelcome {
                HStack {
                    Label("¿Primera vez? Todo lo que borres va a la Papelera, nunca se borra para siempre. Los juegos (.nup/.nsp) y prod.keys están protegidos.", systemImage: "hand.wave.fill")
                        .font(.callout)
                    Spacer()
                    Button("Entendido") { showWelcome = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding(10)
                .background(Color.blue.opacity(0.12))
            }
            TabView(selection: $tab) {
                FilesView(store: store).tabItem { Label("Archivos", systemImage: "folder") }.tag(0)
                SpaceView(store: store).tabItem { Label("Espacio", systemImage: "internaldrive") }.tag(1)
                DuplicatesView(store: store).tabItem { Label("Duplicados", systemImage: "doc.on.doc") }.tag(2)
                XcodeCleanView(store: store).tabItem { Label("Limpiar Xcode", systemImage: "hammer") }.tag(3)
                AppsView(store: store).tabItem { Label("Apps", systemImage: "app.badge") }.tag(4)
                CacheView(store: store).tabItem { Label("Limpieza de caché", systemImage: "trash") }.tag(5)
                LogView(store: store).tabItem { Label("Registro", systemImage: "list.clipboard") }.tag(6)
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
                  message: Text("Va a la Papelera, no se borra para siempre. Puedes recuperarlo desde la Papelera."),
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
                  message: Text("Se borran Documents, Library y tmp de esa app. Primero haz un respaldo ZIP. Va a la Papelera."),
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
            Text("Solo se limpia ~/Library/Caches. Nunca se borra permanente: va a la Papelera y se recrea la carpeta vacía.").font(.callout).foregroundStyle(.secondary)
            List(store.caches.indices, id: \.self) { i in
                HStack {
                    Toggle("", isOn: $store.caches[i].selected)
                    Text(store.caches[i].name).lineLimit(1)
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
            Text("Las carpetas van a la Papelera, no se borran para siempre.")
        }
    }
}

// MARK: - Espacio
struct SpaceView: View {
    @ObservedObject var store: Store
    var used: Int64 { max(0, store.diskTotal - store.diskFree) }
    var usedPct: Double { store.diskTotal > 0 ? Double(used) / Double(store.diskTotal) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Text("Carpetas que más pesan").font(.headline)
            List(store.heavyFolders) { f in
                HStack {
                    VStack(alignment: .leading) { Text(f.name).font(.headline); Text(f.url.path).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Text(formatBytes(f.size)).font(.headline)
                    Button("Abrir") { NSWorkspace.shared.open(f.url) }
                    Button("A Papelera") { store.trash(f.url) }.foregroundStyle(.red)
                }
            }
            Text("Nunca se borran .nup/.nsp, prod.keys ni carpetas de juegos. Todo va a la Papelera.").font(.callout).foregroundStyle(.secondary)
        }.padding(12)
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
        } message: { Text("Se queda el primer archivo de cada grupo. Todo va a la Papelera, se puede recuperar.") }
    }
}

// MARK: - Limpiar Xcode
struct XcodeCleanView: View {
    @ObservedObject var store: Store
    @State private var confirmClean = false
    var totalSelected: Int64 { store.xcodeItems.filter { $0.selected }.reduce(0) { $0 + $1.size } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("🔍 Medir Xcode") { store.scanXcode() }
                Button("Seleccionar todo") { for i in store.xcodeItems.indices { store.xcodeItems[i].selected = true } }
                Button("Ninguno") { for i in store.xcodeItems.indices { store.xcodeItems[i].selected = false } }
                Spacer()
                Text("Se liberarían: \(formatBytes(totalSelected))").font(.headline)
                Button("Limpiar seleccionados") { confirmClean = true }.buttonStyle(.borderedProminent).disabled(totalSelected == 0)
            }
            Text("DerivedData se puede borrar sin miedo: Xcode lo vuelve a generar al compilar. No borres el proyecto actual si lo estás compilando ahora. DeviceSupport viejo, Archives y Simulator también se regeneran. Todo va a la Papelera, nunca permanente.").font(.callout).foregroundStyle(.secondary)
            List(store.xcodeItems.indices, id: \.self) { i in
                HStack {
                    Toggle("", isOn: $store.xcodeItems[i].selected)
                    VStack(alignment: .leading) { Text(store.xcodeItems[i].name).font(.headline); Text(store.xcodeItems[i].kind).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Text(formatBytes(store.xcodeItems[i].size)).font(.headline)
                }
            }
        }
        .padding(12)
        .alert("¿Limpiar \(formatBytes(totalSelected)) de Xcode?", isPresented: $confirmClean) {
            Button("Limpiar (a Papelera)", role: .destructive) { store.cleanSelectedXcode() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Las carpetas van a la Papelera, no se borran para siempre. Los juegos y prod.keys nunca se tocan.") }
    }
}

// MARK: - Registro

struct LogView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
