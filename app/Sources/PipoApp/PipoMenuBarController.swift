import AppKit
import Observation
import PipoAppCore
import PipoUI
import SwiftUI

@MainActor
final class PipoMenuBarController: NSObject, NSWindowDelegate {
    private let model: PipoModel
    private let installUpdate: (@MainActor () -> Void)?
    private let menuHostLayout = PipoMenuHostLayout()
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
    private var motionTask: Task<Void, Never>?
    private var wideHostForSession = false
    private var visibility: Visibility = .hidden

    private enum Visibility { case hidden, showing, shown, hiding }

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
        button.image = PipoBrandAssets.hollowTemplateLogo
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
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.onCancel = { [weak self] in self?.hidePanel() }

        let root = PipoRootView(
            model: model,
            configuration: PipoUIConfiguration(model: model, installUpdate: installUpdate),
            hostMode: .menuBar,
            menuHostLayout: menuHostLayout,
            onMenuInspectorVisibilityChanged: { [weak self] visible in
                self?.setInspectorVisible(visible) ?? false
            },
            onMenuDismiss: { [weak self] in
                self?.hidePanel()
            }
        )
        let hostingView = NSHostingView(rootView: root)
        // Window frame is authoritative. SwiftUI intrinsic width must never
        // resize or recenter the WKWebView while inspector state changes.
        hostingView.sizingOptions = []
        hostingView.frame = CGRect(origin: .zero, size: PipoMenuPanelGeometry.compactSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    private func installEventMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window === self.panel,
               self.wideHostForSession,
               !self.inspectorVisible,
               event.locationInWindow.x < 368
            {
                self.hidePanel()
                return nil
            }
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
        switch visibility {
        case .hidden, .hiding: showPanel()
        case .showing, .shown: hidePanel()
        }
    }

    private func showPanel() {
        inspectorVisible = false
        guard let anchor = statusItemScreenFrame, let visibleFrame = currentVisibleFrame else { return }
        wideHostForSession = PipoMenuPanelGeometry.usesExpandedInspector(anchoredTo: anchor, in: visibleFrame)
        menuHostLayout.usesWideHost = wideHostForSession
        let target = PipoMenuPanelGeometry.frame(anchoredTo: anchor, in: visibleFrame, inspectorVisible: wideHostForSession)
        if !panel.isVisible {
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.setFrame(PipoMenuPanelGeometry.offscreenRightFrame(from: target, in: visibleFrame), display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.makeKey()
        }
        visibility = .showing
        animatePanel(to: target, alpha: 1, duration: PipoMenuPanelGeometry.showDuration, curve: .show) { [weak self] in
            guard let self, self.visibility == .showing else { return }
            self.visibility = .shown
        }
    }

    private func hidePanel() {
        guard panel.isVisible, visibility != .hidden else { return }
        guard let visibleFrame = currentVisibleFrame else {
            panel.orderOut(nil)
            visibility = .hidden
            return
        }
        inspectorVisible = false
        visibility = .hiding
        let hidden = PipoMenuPanelGeometry.offscreenRightFrame(from: panel.frame, in: visibleFrame)
        animatePanel(to: hidden, alpha: 0, duration: PipoMenuPanelGeometry.hideDuration, curve: .hide) { [weak self] in
            guard let self, self.visibility == .hiding else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.visibility = .hidden
        }
    }

    private func repositionVisiblePanel() {
        guard panel.isVisible else { return }
        motionTask?.cancel()
        guard visibility != .hiding else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            visibility = .hidden
            return
        }
        if wideHostForSession,
           let anchor = statusItemScreenFrame,
           let visibleFrame = currentVisibleFrame,
           !PipoMenuPanelGeometry.usesExpandedInspector(anchoredTo: anchor, in: visibleFrame)
        {
            // Never squeeze a live 760pt WKWebView. Close; next open selects
            // the 420pt overlay host for this display.
            hidePanel()
            return
        }
        applyFrame(useWideHost: wideHostForSession, animated: false)
        panel.alphaValue = 1
        visibility = .shown
    }

    @discardableResult
    private func setInspectorVisible(_ visible: Bool) -> Bool {
        inspectorVisible = visible
        // Host width is selected before orderFront and remains immutable for
        // this open session. Inspector visibility changes DOM only.
        return wideHostForSession
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

    private func applyFrame(useWideHost: Bool, animated: Bool) {
        guard let anchor = statusItemScreenFrame, let visibleFrame = currentVisibleFrame else { return }
        let target = PipoMenuPanelGeometry.frame(
            anchoredTo: anchor,
            in: visibleFrame,
            inspectorVisible: useWideHost
        )
        guard animated else {
            motionTask?.cancel()
            panel.setFrame(target, display: true)
            return
        }
        animatePanel(
            to: target,
            alpha: panel.alphaValue,
            duration: useWideHost ? PipoMenuPanelGeometry.showDuration : PipoMenuPanelGeometry.hideDuration,
            curve: useWideHost ? .show : .hide
        )
    }

    private enum MotionCurve {
        case show, hide

        var controlPoints: (Double, Double, Double, Double) {
            switch self {
            case .show: (0.16, 1, 0.3, 1)
            case .hide: (0.4, 0, 1, 1)
            }
        }
    }

    private func animatePanel(
        to targetFrame: CGRect,
        alpha targetAlpha: CGFloat,
        duration: TimeInterval,
        curve: MotionCurve,
        completion: (@MainActor () -> Void)? = nil
    ) {
        motionTask?.cancel()
        let startFrame = panel.frame
        let startAlpha = panel.alphaValue
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || duration == 0 {
            panel.setFrame(targetFrame, display: true)
            panel.alphaValue = targetAlpha
            completion?()
            return
        }
        motionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = Date()
            while !Task.isCancelled {
                let raw = min(1, Date().timeIntervalSince(started) / duration)
                let progress = Self.cubicBezierProgress(raw, controlPoints: curve.controlPoints)
                self.panel.setFrame(Self.interpolate(from: startFrame, to: targetFrame, progress: progress), display: true)
                self.panel.alphaValue = startAlpha + (targetAlpha - startAlpha) * progress
                if raw >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled else { return }
            self.panel.setFrame(targetFrame, display: true)
            self.panel.alphaValue = targetAlpha
            completion?()
        }
    }

    private static func interpolate(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }

    private static func cubicBezierProgress(
        _ raw: Double,
        controlPoints: (Double, Double, Double, Double)
    ) -> CGFloat {
        guard raw > 0 else { return 0 }
        guard raw < 1 else { return 1 }
        let (x1, y1, x2, y2) = controlPoints
        func component(_ t: Double, _ first: Double, _ second: Double) -> Double {
            let inverse = 1 - t
            return 3 * inverse * inverse * t * first + 3 * inverse * t * t * second + t * t * t
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<14 {
            let candidate = (lower + upper) / 2
            if component(candidate, x1, x2) < raw { lower = candidate } else { upper = candidate }
        }
        return CGFloat(component((lower + upper) / 2, y1, y2))
    }

    private var statusItemScreenFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private var currentVisibleFrame: CGRect? {
        guard let anchor = statusItemScreenFrame else { return NSScreen.main?.visibleFrame }
        return statusItem.button?.window?.screen?.visibleFrame
            ?? NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) })?.visibleFrame
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
