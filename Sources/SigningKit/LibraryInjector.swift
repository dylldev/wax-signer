import Foundation

/// Adds libraries (`.dylib`, `.framework`, or the dylibs inside a `.deb`) to an unpacked app: the files go into
/// `Frameworks/` and the main executable gets a load command for each, so iOS loads them at launch. Runs before
/// signing, so the signer signs the new files too.
enum LibraryInjector {
    /// Returns one note per library added. All checks happen before any file is written: a failure changes nothing.
    static func inject(_ libraries: [URL], into app: URL) throws -> [String] {
        let fm = FileManager.default
        let info = try readInfo(app)
        guard let exeName = info["CFBundleExecutable"] as? String else { throw SigningError.bundle("The app has no executable to add libraries to.") }
        let exeURL = app.appendingPathComponent(exeName)
        var exe = try MachO(FatMachO.thin(Data(contentsOf: exeURL)))
        guard !exe.isEncrypted else {
            throw SigningError.bundle("This app is encrypted by the App Store, so libraries cannot be added. Use a decrypted copy.")
        }

        // 1. Work out every file to copy and every name to load, writing nothing yet.
        struct Item { let source: URL; let destination: URL; let loadName: String; let note: String }
        var items: [Item] = []
        var cleanup: [URL] = []
        defer { for u in cleanup { try? fm.removeItem(at: u) } }
        let frameworks = app.appendingPathComponent("Frameworks", isDirectory: true)
        let viaRpath = exe.hasFrameworksRpath

        for library in libraries {
            switch library.pathExtension.lowercased() {
            case "dylib":
                try requireMachO(library)
                let file = library.lastPathComponent
                items.append(Item(source: library, destination: frameworks.appendingPathComponent(file),
                                  loadName: viaRpath ? "@rpath/\(file)" : "@executable_path/Frameworks/\(file)", note: "Added \(file)"))
            case "framework":
                let fwInfo = try readInfo(library)
                guard let fwExe = fwInfo["CFBundleExecutable"] as? String else { throw SigningError.bundle("\(library.lastPathComponent) has no executable.") }
                try requireMachO(library.appendingPathComponent(fwExe))
                let dir = library.lastPathComponent
                items.append(Item(source: library, destination: frameworks.appendingPathComponent(dir),
                                  loadName: (viaRpath ? "@rpath/" : "@executable_path/Frameworks/") + "\(dir)/\(fwExe)", note: "Added \(dir)"))
            case "deb":
                let tmp = fm.temporaryDirectory.appendingPathComponent("wax-deb-\(UUID().uuidString)", isDirectory: true)
                cleanup.append(tmp)
                for dylib in try DebExtractor.dylibs(inDeb: library, to: tmp) {
                    try requireMachO(dylib)
                    let file = dylib.lastPathComponent
                    items.append(Item(source: dylib, destination: frameworks.appendingPathComponent(file),
                                      loadName: viaRpath ? "@rpath/\(file)" : "@executable_path/Frameworks/\(file)",
                                      note: "Added \(file) from \(library.lastPathComponent)"))
                }
            default:
                throw SigningError.bundle("\(library.lastPathComponent) is not a .dylib, .framework or .deb.")
            }
        }
        for item in items { try exe.addLoadDylib(item.loadName) }   // throws when the header is full, before any write

        // 2. Write.
        try fm.createDirectory(at: frameworks, withIntermediateDirectories: true)
        for item in items {
            if fm.fileExists(atPath: item.destination.path) { try fm.removeItem(at: item.destination) }
            try fm.copyItem(at: item.source, to: item.destination)
        }
        let attrs = try fm.attributesOfItem(atPath: exeURL.path)
        try exe.data.write(to: exeURL, options: .atomic)
        if let mode = attrs[.posixPermissions] { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: exeURL.path) }
        return items.map(\.note)
    }

    private static func requireMachO(_ file: URL) throws {
        guard let h = try? FileHandle(forReadingFrom: file), let head = try? h.read(upToCount: 4), MachO.looksLikeMachO(head) else {
            throw SigningError.bundle("\(file.lastPathComponent) is not a compiled library for iOS.")
        }
        try? h.close()
    }

    private static func readInfo(_ bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw SigningError.bundle("\(bundle.lastPathComponent) has an unreadable Info.plist.")
        }
        return plist
    }
}
