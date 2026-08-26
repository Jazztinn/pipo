import AppKit
import Observation
import PipoAppCore
import PipoUI
import SwiftUI

@MainActor
final class PipoMenuBarController: NSObject, NSWindowDelegate {
    private let model: PipoModel
    private let installUpdate: (@MainActor () -> Void)?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = PipoMenuPanel(
        contentRect: CGRect(origin: .zero, size: PipoMenuPanelGeometry.compactSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var inspectorVisible = false
    private var globalMouseMonitor: Any?
    private var localEventMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(model: PipoModel, installUpdate: (@MainActor () -> Void)?) {
        self.model = model
        self.installUpdate = installUpdate
        super.init()
        configureStatusItem()
        configurePanel()
        installEventMonitors()
        observeUrgency()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "flag", accessibilityDescription: "Pipo")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Pipo"
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp])
        updateStatusItem()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.onCancel = { [weak self] in self?.hidePanel() }

        let root = PipoRootView(
            model: model,
            configuration: PipoUIConfiguration(model: model, installUpdate: installUpdate),
            hostMode: .menuBar,
            onMenuInspectorVisibilityChanged: { [weak self] visible in
                self?.setInspectorVisible(visible) ?? false
            },
            onMenuDismiss: { [weak self] in
                self?.hidePanel()
            }
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = CGRect(origin: .zero, size: PipoMenuPanelGeometry.compactSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    private func installEventMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window !== self.panel,
               event.window !== self.statusItem.button?.window
            {
                self.hidePanel()
            }
            return event
        }
        workspaceObservers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.repositionVisiblePanel() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.repositionVisiblePanel() }
            },
        ]
    }

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        inspectorVisible = false
        applyFrame(inspectorVisible: false)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        inspectorVisible = false
        panel.orderOut(nil)
    }

    private func repositionVisiblePanel() {
        guard panel.isVisible else { return }
        _ = setInspectorVisible(inspectorVisible)
    }

    @discardableResult
    private func setInspectorVisible(_ visible: Bool) -> Bool {
        inspectorVisible = visible
        let expanded: Bool
        if visible, let anchor = statusItemScreenFrame, let visibleFrame = currentVisibleFrame {
            expanded = PipoMenuPanelGeometry.usesExpandedInspector(anchoredTo: anchor, in: visibleFrame)
        } else {
            expanded = false
        }
        applyFrame(inspectorVisible: expanded)
        return expanded
    }

    private func observeUrgency() {
        withObservationTracking {
            _ = model.snapshot
            _ = model.localState
            updateStatusItem()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeUrgency() }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let count = model.snapshot.map {
            PipoDashboardRanking.urgentCount(snapshot: $0, state: model.localState)
        } ?? 0
        statusItem.length = count > 0 ? NSStatusItem.variableLength : NSStatusItem.squareLength
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
        button.title = count > 0 ? " \(count)" : ""
        button.setAccessibilityLabel(count > 0 ? "Pipo, \(count) urgent items" : "Pipo")
        repositionVisiblePanel()
    }

    private func applyFrame(inspectorVisible: Bool) {
        guard let anchor = statusItemScreenFrame, let visibleFrame = currentVisibleFrame else { return }
        let target = PipoMenuPanelGeometry.frame(
            anchoredTo: anchor,
            in: visibleFrame,
            inspectorVisible: inspectorVisible
        )
        panel.setFrame(target, display: true)
    }

    private var statusItemScreenFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private var currentVisibleFrame: CGRect? {
        guard let anchor = statusItemScreenFrame else { return NSScreen.main?.visibleFrame }
        return NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) })?.visibleFrame
            ?? statusItem.button?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
    }
}

private final class PipoMenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
