import SwiftUI

@main
enum Entry {
    static func main() {
        #if HUSHBAR_DIAGNOSTICS
        if Diagnostics.runIfRequested() { return }
        #endif
        HushbarApp.main()
    }
}

struct HushbarApp: App {
    @StateObject private var model = HushbarModel()

    var body: some Scene {
        MenuBarExtra {
            HushbarView(model: model)
        } label: {
            // Without an explicit label, VoiceOver reads the symbol's name, "slider.vertical.3".
            Image(systemName: "slider.vertical.3")
                .accessibilityLabel("Hushbar")
        }
        .menuBarExtraStyle(.window)
    }
}
