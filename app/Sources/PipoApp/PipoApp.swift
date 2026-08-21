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
final class PipoUpdater: NSObject, SPUUpdaterDelegate {
    let isConfigured: Bool
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: isConfigured,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var channelObserver: NSObjectProtocol?

    init(bundle: Bundle = .main) {
        isConfigured = !(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
        super.init()
        _ = controller
        channelObserver = NotificationCenter.default.addObserver(
            forName: .pipoUpdateChannelChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.controller.updater.resetUpdateCycleAfterShortDelay() }
        }
    }

    deinit {
        if let channelObserver { NotificationCenter.default.removeObserver(channelObserver) }
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        switch UserDefaults.standard.string(forKey: "pipo.updates.channel") {
        case "beta": "https://raw.githubusercontent.com/Jazztinn/pipo/main/appcast-beta.xml"
        default: "https://raw.githubusercontent.com/Jazztinn/pipo/main/appcast.xml"
        }
    }
}

extension Notification.Name {
    static let pipoUpdateChannelChanged = Notification.Name("com.jazztinn.pipo.update-channel-changed")
}

final class PipoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
