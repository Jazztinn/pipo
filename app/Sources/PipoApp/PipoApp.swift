import AppKit
import PipoAppCore
import PipoUI
import Sparkle
import SwiftUI

@main
struct PipoApp: App {
    @NSApplicationDelegateAdaptor(PipoAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Pipo Settings", id: "pipo") {
            PipoRootView(
                model: appDelegate.model,
                configuration: PipoUIConfiguration(
                    model: appDelegate.model,
                    installUpdate: appDelegate.installUpdate
                ),
                hostMode: .window
            )
            .frame(minWidth: 680, idealWidth: 820, minHeight: 480, idealHeight: 600)
        }
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)
        .commands { PipoCommands() }
    }
}

private struct PipoCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "pipo")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
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

@MainActor
final class PipoAppDelegate: NSObject, NSApplicationDelegate {
    let model = PipoModel.live()
    let updater = PipoUpdater()
    private var menuBarController: PipoMenuBarController?
    private var didStartModel = false

    var installUpdate: (@MainActor () -> Void)? {
        updater.isConfigured ? updater.checkForUpdates : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        menuBarController = PipoMenuBarController(model: model, installUpdate: installUpdate)
        guard !didStartModel else { return }
        didStartModel = true
        Task { await model.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let window = sender.windows.first(where: { $0.title == "Pipo Settings" }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
