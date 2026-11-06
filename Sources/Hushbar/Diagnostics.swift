import AppKit
import CoreAudio
import Darwin
import SwiftUI

/// Command-line checks for the audio path, with no UI involved.
///
///     Hushbar --list                      audio processes and the app each resolves to
///     Hushbar --probe <pid> <gain> <sec>  route one process and print its levels each second
///     Hushbar --rows <sec>                the menu's rows each second; * marks playing
///     Hushbar --snapshot <png>            render the menu with sample apps, touching no audio
enum Diagnostics {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { return false }
        switch arguments[1] {
        case "--list":
            list()
        case "--probe":
            guard arguments.count == 5, let pid = pid_t(arguments[2]),
                  let gain = Float(arguments[3]), let seconds = Int(arguments[4]) else {
                print("usage: --probe <pid> <gain> <seconds>")
                return true
            }
            probe(pid: pid, gain: gain, seconds: seconds)
        case "--rows":
            guard arguments.count == 3, let seconds = Int(arguments[2]) else {
                print("usage: --rows <seconds>")
                return true
            }
            MainActor.assumeIsolated { rows(seconds: seconds) }
        case "--snapshot":
            guard arguments.count >= 3 else {
                print("usage: --snapshot <output.png>")
                return true
            }
            MainActor.assumeIsolated { snapshot(to: arguments[2]) }
        default:
            return false
        }
        return true
    }

    private static func processObjects() -> [AudioObjectID] {
        (try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, element: AudioObjectID(0))) ?? []
    }

    private static func list() {
        print("output=\((try? defaultOutputDeviceUID()) ?? "?") permission=\(CapturePermission.status)")
        for object in processObjects() {
            guard let pid = try? object.read(kAudioProcessPropertyPID, default: pid_t(-1)), pid > 0 else { continue }
            let playing = ((try? object.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) != 0
            let bundleID = (try? object.readString(kAudioProcessPropertyBundleID)) ?? ""
            let identity = AppIdentity.resolve(pid: pid, audioBundleID: bundleID)
            print("pid=\(pid) playing=\(playing) bundle=\(bundleID) app=\(identity.name) key=\(identity.key)")
        }
    }

    @MainActor
    private static func snapshot(to path: String) {
        _ = NSApplication.shared
        func icon(_ app: String) -> NSImage {
            NSWorkspace.shared.icon(forFile: "/System/Applications/\(app).app")
        }
        func row(_ name: String, _ setting: AppSetting, playing: Bool) -> AppRow {
            AppRow(id: name, name: name, icon: icon(name), setting: setting, isPlaying: playing)
        }
        let model = HushbarModel(previewRows: [
            row("FaceTime", AppSetting(), playing: true),
            row("Music", AppSetting(volume: 0.45), playing: true),
            row("News", AppSetting(isMuted: true), playing: true),
            row("Podcasts", AppSetting(volume: 0.8), playing: false),
        ])
        let host = NSHostingView(rootView: HushbarView(model: model)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.setFrameSize(host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.16, alpha: 1)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    @MainActor
    private static func rows(seconds: Int) {
        let model = HushbarModel()
        for second in 0...max(seconds, 0) {
            let summary = model.rows.map { "\($0.name)\($0.isPlaying ? "*" : "")" }.joined(separator: ", ")
            let levels = model.routeLevels.map { "\($0.input)->\($0.output)" }.joined(separator: " ")
            print("t=\(second)s \(summary) | routes: \(levels)")
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
    }

    private static func probe(pid: pid_t, gain: Float, seconds: Int) {
        if CapturePermission.status == .undetermined {
            var answered = false
            CapturePermission.request { _ in answered = true }
            while !answered {
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
        }
        print("permission=\(CapturePermission.status)")
        guard let object = processObjects().first(where: {
            (try? $0.read(kAudioProcessPropertyPID, default: pid_t(-1))) == pid
        }) else {
            print("error: no audio process for pid \(pid)")
            return
        }
        do {
            let route = try ProcessRoute(processObject: object, outputUID: try defaultOutputDeviceUID(), gain: gain)
            try route.setRunning(true)
            for second in 1...max(seconds, 1) {
                Thread.sleep(forTimeInterval: 1)
                print("t=\(second)s input=\(route.inputPeak) output=\(route.outputPeak)")
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }
    }
}
