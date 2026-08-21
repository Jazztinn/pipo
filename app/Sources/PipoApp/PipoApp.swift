import AppKit
import PipoAppCore
import PipoUI
import Sparkle
import SwiftUI

@main
struct PipoApp: App {
    @NSApplicationDelegateAdaptor(PipoAppDelegate.self) private var appDelegate
    @State private var model = PipoModel.live()

    var body: some Scene {
        MenuBarExtra("Pipo", systemImage: "flag.fill") {
            PipoRootView(model: model)
                .frame(width: 420, height: 620)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PipoSettingsView(model: model)
                .frame(width: 460, height: 420)
        }
    }
}

final class PipoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

