import SwiftUI

struct HushbarView: View {
    @ObservedObject var model: HushbarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Volume Mixer")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            if model.permission == .denied {
                PermissionNotice()
                Divider()
            }

            if model.rows.isEmpty {
                Text("No apps are using audio right now.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.rows) { row in
                            AppRowView(row: row, model: model)
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let error = model.errorMessage {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchesAtLogin($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Reset") { model.resetAll() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .onAppear { model.refreshPermission() }
    }
}

private struct AppRowView: View {
    let row: AppRow
    @ObservedObject var model: HushbarModel

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: row.icon)
                .resizable()
                .frame(width: 26, height: 26)
                .opacity(row.isPlaying ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.name)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(row.isPlaying ? .primary : .secondary)

                Slider(
                    value: Binding(
                        get: { Double(row.setting.volume) },
                        set: { model.setVolume(Float($0), for: row.id) }),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing { model.finishVolumeChange() }
                    })
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(row.setting.isMuted)
                    .accessibilityLabel(Text("\(row.name) volume"))
            }

            Text(verbatim: "\(Int((row.setting.volume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Button {
                model.toggleMute(row.id)
            } label: {
                Image(systemName: row.setting.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(row.setting.isMuted ? .red : .primary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.setting.isMuted ? Text("Unmute") : Text("Mute"))
            .accessibilityLabel(row.setting.isMuted ? Text("Unmute \(row.name)") : Text("Mute \(row.name)"))
        }
    }
}

private struct PermissionNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Muting works, but volume control needs the System Audio Recording permission.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") { CapturePermission.openSystemSettings() }
                .controlSize(.small)
        }
        .padding(14)
    }
}
