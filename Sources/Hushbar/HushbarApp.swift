import SwiftUI

@main
enum Entry {
    static func main() {
        if Diagnostics.runIfRequested() { return }
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
