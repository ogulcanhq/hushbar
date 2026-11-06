import AppKit
import CoreAudio
import Darwin

/// The user-facing app behind an audio process. Browsers and Electron apps play
/// sound from helper processes, so those are folded into the app that owns them.
struct AppIdentity {
    let key: String
    let name: String
    let icon: NSImage
    /// Has a Dock presence, as opposed to a daemon or menu bar agent.
    var isRegularApp = false

    static func resolve(pid: pid_t, audioBundleID: String) -> AppIdentity {
        // A process with its own Dock presence is its own app even when something else
        // launched it (Unity Editor from Unity Hub). So is a helper sharing a regular
        // app's bundle ID. Otherwise ask who the process works for.
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
           let identity = AppIdentity(app) {
            return identity
        }
        if !audioBundleID.isEmpty,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: audioBundleID)
               .first(where: { $0.activationPolicy == .regular }),
           let identity = AppIdentity(app) {
            return identity
        }
        if let app = NSRunningApplication(processIdentifier: responsiblePID(for: pid)),
           app.activationPolicy != .prohibited, let identity = AppIdentity(app) {
            return identity
        }

        let path = executablePath(of: pid)
        if let path, let appPath = outermostAppBundle(in: path), let bundle = Bundle(path: appPath) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            return AppIdentity(
                key: bundle.bundleIdentifier ?? appPath,
                name: name,
                icon: NSWorkspace.shared.icon(forFile: appPath))
        }

        let fallbackName = path.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? (audioBundleID.isEmpty ? String(localized: "Process \(Int(pid))") : audioBundleID)
        return AppIdentity(
            key: audioBundleID.isEmpty ? (path ?? "pid-\(pid)") : audioBundleID,
            name: fallbackName,
            icon: genericIcon)
    }

    private init?(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(
            key: bundleID,
            name: app.localizedName ?? bundleID,
            icon: app.icon ?? Self.genericIcon,
            isRegularApp: app.activationPolicy == .regular)
    }

    init(key: String, name: String, icon: NSImage, isRegularApp: Bool = false) {
        self.key = key
        self.name = name
        self.icon = icon
        self.isRegularApp = isRegularApp
    }

    private static var genericIcon: NSImage {
        NSWorkspace.shared.icon(for: .application)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    static func outermostAppBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// Private but long-stable libsystem call: maps an XPC service such as
    /// `com.apple.WebKit.GPU` to the app it works for, which the process tree doesn't show.
    private static func responsiblePID(for pid: pid_t) -> pid_t {
        typealias Function = @convention(c) (pid_t) -> pid_t
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return pid
        }
        let result = unsafeBitCast(symbol, to: Function.self)(pid)
        return result > 0 ? result : pid
    }
}
