import AppKit
import PipoAppCore
import PipoUI
import Sparkle
import SwiftUI

@main
struct PipoApp: App {
    @NSApplicationDelegateAdaptor(PipoAppDelegate.self) private var appDelegate
    @State private var model = PipoModel.live()
    private let updater = PipoUpdater()

    var body: some Scene {
        Window("Pipo", id: "pipo") {
            PipoCompanionView(
                model: model,
                installUpdate: updater.isConfigured ? updater.checkForUpdates : nil
            )
            .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 620)
            .task {
                await model.start()
            }
        }
        .defaultSize(width: 560, height: 620)

        MenuBarExtra("Pipo", systemImage: "flag.fill") {
            PipoRootView(
                model: model,
                configuration: PipoUIConfiguration(
                    model: model,
                    installUpdate: updater.isConfigured ? updater.checkForUpdates : nil
                )
            )
                .frame(width: 420, height: 620)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class PipoUpdater {
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController

    init(bundle: Bundle = .main) {
        isConfigured = !(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        controller.checkForUpdates(nil)
    }
}

final class PipoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
