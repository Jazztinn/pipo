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
            .task {
                await model.start()
            }
        }
        .defaultSize(width: 800, height: 680)

        MenuBarExtra {
            PipoRootView(
                model: model,
                configuration: PipoUIConfiguration(
                    model: model,
                    installUpdate: updater.isConfigured ? updater.checkForUpdates : nil
                ),
                hostMode: .menuBar
            )
        } label: {
            let count = model.snapshot.map {
                PipoDashboardRanking.urgentCount(snapshot: $0, state: model.localState)
            } ?? 0
            if count > 0 {
                Label("\(count)", systemImage: "flag.fill")
                    .accessibilityLabel("Pipo, \(count) urgent items")
            } else {
                Image(systemName: "flag.fill")
                    .accessibilityLabel("Pipo")
            }
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
