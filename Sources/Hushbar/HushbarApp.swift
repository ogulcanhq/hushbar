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
        MenuBarExtra("Hushbar", systemImage: "slider.vertical.3") {
            HushbarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
