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
            PipoRootView(
                model: model,
                configuration: PipoUIConfiguration(
                    model: model,
                    installUpdate: updater.isConfigured ? updater.checkForUpdates : nil
                ),
                hostMode: .window
            )
            .frame(minWidth: 736, idealWidth: 800, minHeight: 660, idealHeight: 680)
            .onAppear {
                appDelegate.configureMenuBar(
                    model: model,
                    installUpdate: updater.isConfigured ? updater.checkForUpdates : nil
                )
            }
            .task {
                await model.start()
            }
        }
        .defaultSize(width: 800, height: 680)
        .windowResizability(.contentSize)

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
    private var menuBarController: PipoMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    @MainActor
    func configureMenuBar(model: PipoModel, installUpdate: (@MainActor () -> Void)?) {
        guard menuBarController == nil else { return }
        menuBarController = PipoMenuBarController(model: model, installUpdate: installUpdate)
    }
}
