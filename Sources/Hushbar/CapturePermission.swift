import AppKit
import Darwin

/// The "System Audio Recording" permission. Without it a tap still silences the app
/// but delivers only silence, so muting works and partial volume does not.
/// macOS has no public API to query it, so this calls TCC directly.
enum CapturePermission {
    enum Status {
        case granted, denied, undetermined
    }

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static var status: Status {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        guard let symbol = dlsym(framework, "TCCAccessPreflight") else { return .undetermined }
        switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .undetermined
        }
    }

    static func request(completion: @escaping (Bool) -> Void) {
        typealias Callback = @convention(block) (Bool) -> Void
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping Callback) -> Void
        guard let symbol = dlsym(framework, "TCCAccessRequest") else {
            completion(false)
            return
        }
        unsafeBitCast(symbol, to: Request.self)(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
