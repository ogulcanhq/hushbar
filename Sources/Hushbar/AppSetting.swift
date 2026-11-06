import AppKit

struct AppSetting: Codable, Equatable {
    var volume: Float = 1
    var isMuted = false

    var isDefault: Bool { volume >= 1 && !isMuted }

    /// Squared so the slider tracks perceived loudness rather than amplitude.
    var gain: Float { isMuted ? 0 : volume * volume }

    /// Default settings bypass Hushbar entirely. Without the capture permission a tap
    /// delivers silence, so partial volume is left alone rather than silencing the app.
    func needsRoute(permission: CapturePermission.Status) -> Bool {
        if isMuted { return true }
        return !isDefault && permission != .denied
    }
}

struct AppRow: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let setting: AppSetting
    let isPlaying: Bool
}

/// Folds audio processes into one row per app. Regular apps are always listed. Daemons
/// and menu bar agents appear once they've played or been adjusted, and stay so a
/// slider doesn't vanish between sounds.
func makeRows(
    processes: [(identity: AppIdentity, isPlaying: Bool)],
    seenPlaying: Set<String>,
    settings: [String: AppSetting]
) -> [AppRow] {
    var grouped: [String: (identity: AppIdentity, isPlaying: Bool)] = [:]
    for process in processes {
        let key = process.identity.key
        guard process.identity.isRegularApp || seenPlaying.contains(key)
                || settings[key]?.isDefault == false else { continue }
        grouped[key] = (process.identity, process.isPlaying || grouped[key]?.isPlaying == true)
    }
    return grouped
        .map { key, value in
            AppRow(
                id: key,
                name: value.identity.name,
                icon: value.identity.icon,
                setting: settings[key] ?? AppSetting(),
                isPlaying: value.isPlaying)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
