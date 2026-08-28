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
                    installUpdate: appDelegate.installUpdate,
                    updatePresentation: appDelegate.updatePresentation
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
    let presentation: PipoUpdatePresentationModel
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: isConfigured,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var channelObserver: NSObjectProtocol?
    private var probeTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let lastProbeKey = "pipo.updates.last-information-probe"

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        presentation: PipoUpdatePresentationModel = PipoUpdatePresentationModel()
    ) {
        isConfigured = !(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
        self.defaults = defaults
        self.presentation = presentation
        super.init()
        _ = controller
        channelObserver = NotificationCenter.default.addObserver(
            forName: .pipoUpdateChannelChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.presentation.resetForChannelChange()
                self.defaults.removeObject(forKey: Self.lastProbeKey)
                self.controller.updater.resetUpdateCycleAfterShortDelay()
            }
        }
    }

    deinit {
        probeTask?.cancel()
        if let channelObserver { NotificationCenter.default.removeObserver(channelObserver) }
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        controller.checkForUpdates(nil)
    }

    func start() {
        guard isConfigured, probeTask == nil else { return }
        probeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.probeIfDue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PipoUpdateProbePolicy.interval))
                guard !Task.isCancelled else { return }
                self?.probeIfDue()
            }
        }
    }

    func stop() {
        probeTask?.cancel()
        probeTask = nil
    }

    private func probeIfDue(now: Date = .now) {
        guard controller.updater.canCheckForUpdates else { return }
        guard PipoUpdateProbePolicy.isDue(
            lastProbe: defaults.object(forKey: Self.lastProbeKey) as? Date,
            now: now
        ) else { return }
        defaults.set(now, forKey: Self.lastProbeKey)
        controller.updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        presentation.presentUpdate(
            version: item.displayVersionString,
            build: item.versionString,
            critical: item.isCriticalUpdate
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        presentation.clearUpdateNotice()
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
    private var isStopping = false

    var installUpdate: (@MainActor () -> Void)? {
        updater.isConfigured ? updater.checkForUpdates : nil
    }

    var updatePresentation: PipoUpdatePresentationModel { updater.presentation }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        menuBarController = PipoMenuBarController(
            model: model,
            installUpdate: installUpdate,
            updatePresentation: updatePresentation
        )
        updater.start()
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isStopping else { return .terminateLater }
        isStopping = true
        updater.stop()
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
