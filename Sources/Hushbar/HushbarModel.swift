import AppKit
import CoreAudio
import Darwin
import ServiceManagement
import SwiftUI

@MainActor
final class HushbarModel: ObservableObject {
    @Published private(set) var rows: [AppRow] = []
    @Published private(set) var permission = CapturePermission.status
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    private struct TrackedProcess {
        let identity: AppIdentity
        let listener: PropertyListener?
        var isPlaying: Bool
    }

    private static let settingsKey = "appSettings"

    private var processes: [AudioObjectID: TrackedProcess] = [:]
    private var routes: [AudioObjectID: ProcessRoute] = [:]
    private var settings: [String: AppSetting] = [:]
    private var appsSeenPlaying: Set<String> = []
    private var outputUID: String?
    private var systemListeners: [PropertyListener] = []
    private var deviceRateListener: PropertyListener?
    private var isRequestingPermission = false
    private var routeCheckTimer: Timer?

    #if HUSHBAR_DIAGNOSTICS
    /// A model with fixed rows and no audio, for rendering the UI.
    init(previewRows: [AppRow]) {
        rows = previewRows
    }
    #endif

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode([String: AppSetting].self, from: data) {
            settings = saved
        }

        systemListeners = [
            PropertyListener(object: .system, selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
                self?.onMain { $0.syncProcesses() }
            },
            PropertyListener(object: .system, selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
                self?.onMain { $0.outputDeviceChanged() }
            },
        ].compactMap { $0 }

        outputDeviceChanged()
        syncProcesses()

        routeCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.onMain { $0.checkRoutedProcesses() }
        }
    }

    /// IsRunning stays true when an app using the mic starts or stops playing, with no
    /// notification. A route that missed that would leave the app silent, so check them.
    private func checkRoutedProcesses() {
        for object in routes.keys {
            let isPlaying = ((try? object.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) != 0
            if isPlaying != processes[object]?.isPlaying {
                syncProcesses()
                return
            }
        }
    }

    #if HUSHBAR_DIAGNOSTICS
    var routeLevels: [(input: Float, output: Float)] {
        routes.values.map { ($0.inputPeak, $0.outputPeak) }
    }
    #endif

    /// Core Audio delivers listener callbacks on the main queue, as requested in `PropertyListener`.
    private nonisolated func onMain(_ body: @MainActor (HushbarModel) -> Void) {
        MainActor.assumeIsolated { body(self) }
    }

    // MARK: - Actions

    func toggleMute(_ key: String) {
        var setting = settings[key] ?? AppSetting()
        setting.isMuted.toggle()
        store(setting, for: key)
        reconcileRoutes()
    }

    /// While dragging, routes are created but never torn down, so passing through 100% can't glitch.
    func setVolume(_ volume: Float, for key: String) {
        var setting = settings[key] ?? AppSetting()
        setting.volume = volume
        store(setting, for: key)
        reconcileRoutes(allowTeardown: false)
    }

    func finishVolumeChange() {
        reconcileRoutes()
    }

    func resetAll() {
        settings = [:]
        saveSettings()
        rebuildRows()
        reconcileRoutes()
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshPermission() {
        permission = CapturePermission.status
        reconcileRoutes()
    }

    // MARK: - Process tracking

    private func syncProcesses() {
        guard let objects = try? AudioObjectID.system.readArray(
            kAudioHardwarePropertyProcessObjectList, element: AudioObjectID(0)) else { return }

        let current = Set(objects)
        for gone in Set(processes.keys).subtracting(current) {
            processes[gone] = nil
            routes[gone] = nil
        }

        for object in objects {
            let isPlaying = ((try? object.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) != 0
            if processes[object] != nil {
                processes[object]?.isPlaying = isPlaying
            } else if let identity = identity(of: object) {
                // IsRunningOutput sends no change notifications; IsRunning does.
                let listener = PropertyListener(object: object, selector: kAudioProcessPropertyIsRunning) { [weak self] in
                    self?.onMain { $0.syncProcesses() }
                }
                processes[object] = TrackedProcess(identity: identity, listener: listener, isPlaying: isPlaying)
            }
            if isPlaying, let key = processes[object]?.identity.key {
                appsSeenPlaying.insert(key)
            }
        }

        rebuildRows()
        reconcileRoutes()
    }

    private func identity(of object: AudioObjectID) -> AppIdentity? {
        guard let pid = try? object.read(kAudioProcessPropertyPID, default: pid_t(-1)),
              pid > 0, pid != getpid() else { return nil }
        let bundleID = (try? object.readString(kAudioProcessPropertyBundleID)) ?? ""
        return AppIdentity.resolve(pid: pid, audioBundleID: bundleID)
    }

    private func rebuildRows() {
        rows = makeRows(
            processes: processes.values.map { ($0.identity, $0.isPlaying) },
            seenPlaying: appsSeenPlaying,
            settings: settings)
    }

    // MARK: - Routing

    private func outputDeviceChanged() {
        routes.removeAll()
        outputUID = try? defaultOutputDeviceUID()
        deviceRateListener = (try? AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultOutputDevice, default: AudioDeviceID(kAudioObjectUnknown)))
            .flatMap { device in
                PropertyListener(object: device, selector: kAudioDevicePropertyNominalSampleRate) { [weak self] in
                    self?.onMain { model in
                        model.routes.removeAll()
                        model.reconcileRoutes()
                    }
                }
            }
        reconcileRoutes()
    }

    private func reconcileRoutes(allowTeardown: Bool = true) {
        guard let outputUID else { return }
        var failure: String?

        for (object, process) in processes {
            let setting = settings[process.identity.key] ?? AppSetting()
            guard setting.needsRoute(permission: permission) else {
                if allowTeardown {
                    routes[object] = nil
                } else {
                    routes[object]?.setGain(setting.gain)
                }
                continue
            }

            requestPermissionIfNeeded()
            do {
                let route: ProcessRoute
                if let existing = routes[object] {
                    route = existing
                    route.setGain(setting.gain)
                } else {
                    route = try ProcessRoute(processObject: object, outputUID: outputUID, gain: setting.gain)
                    routes[object] = route
                }
                try route.setRunning(process.isPlaying)
            } catch {
                routes[object] = nil
                failure = String(localized: "Couldn't control \(process.identity.name)'s audio: \(error.localizedDescription)")
            }
        }
        errorMessage = failure
    }

    private func requestPermissionIfNeeded() {
        guard permission == .undetermined, !isRequestingPermission else { return }
        isRequestingPermission = true
        CapturePermission.request { [weak self] _ in
            guard let self else { return }
            self.isRequestingPermission = false
            self.refreshPermission()
        }
    }

    // MARK: - Persistence

    private func store(_ setting: AppSetting, for key: String) {
        settings[key] = setting.isDefault ? nil : setting
        saveSettings()
        rebuildRows()
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}
