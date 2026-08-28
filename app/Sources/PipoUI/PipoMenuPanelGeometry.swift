import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
package final class PipoMenuHostLayout {
    package var usesWideHost = false
    package init() {}
    package var width: CGFloat { usesWideHost ? PipoMenuPanelGeometry.expandedSize.width : PipoMenuPanelGeometry.compactSize.width }
}

package enum PipoMenuPanelGeometry {
    package static let mainSize = CGSize(width: 380, height: 660)
    package static let inspectorWidth: CGFloat = 340
    package static let inspectorGap: CGFloat = 16
    package static let expandedLeadingInset: CGFloat = 24
    package static let compactSize = mainSize
    package static let expandedSize = CGSize(
        width: expandedLeadingInset + inspectorWidth + inspectorGap + mainSize.width,
        height: mainSize.height
    )
    package static let rightInset: CGFloat = 8
    package static let topGap: CGFloat = 6
    package static let cornerRadius: CGFloat = 16
    package static let expansionThreshold: CGFloat = 776
    package static let showDuration: TimeInterval = 0.22
    package static let hideDuration: TimeInterval = 0.18

    package static func frame(
        anchoredTo statusItemFrame: CGRect,
        in visibleFrame: CGRect,
        inspectorVisible: Bool,
        topGap: CGFloat = topGap
    ) -> CGRect {
        let expanded = inspectorVisible && usesExpandedInspector(anchoredTo: statusItemFrame, in: visibleFrame, topGap: topGap)
        let requested = expanded ? expandedSize : compactSize
        let availableWidth = max(0, visibleFrame.width - rightInset * 2)
        let availableHeight = max(0, visibleFrame.height - rightInset * 2)
        let size = CGSize(width: min(requested.width, availableWidth), height: min(requested.height, availableHeight))
        let rightX = visibleFrame.maxX - rightInset
        let topY = min(statusItemFrame.minY, visibleFrame.maxY) - topGap
        let originY = max(visibleFrame.minY + rightInset, topY - size.height)
        return CGRect(x: rightX - size.width, y: originY, width: size.width, height: size.height)
    }

    package static func usesExpandedInspector(
        anchoredTo statusItemFrame: CGRect,
        in visibleFrame: CGRect,
        topGap: CGFloat = topGap
    ) -> Bool {
        _ = statusItemFrame
        _ = topGap
        return visibleFrame.width >= expansionThreshold
    }

    package static func mainPaneFrame(in panelFrame: CGRect, inspectorVisible: Bool) -> CGRect {
        _ = inspectorVisible
        let width = min(mainSize.width, panelFrame.width)
        return CGRect(
            x: panelFrame.maxX - width,
            y: panelFrame.minY,
            width: width,
            height: panelFrame.height
        )
    }

    package static func inspectorPaneFrame(in panelFrame: CGRect) -> CGRect {
        let mainFrame = mainPaneFrame(in: panelFrame, inspectorVisible: true)
        let availableWidth = max(0, mainFrame.minX - panelFrame.minX - inspectorGap)
        let width = min(inspectorWidth, availableWidth)
        return CGRect(
            x: mainFrame.minX - inspectorGap - width,
            y: panelFrame.minY,
            width: width,
            height: panelFrame.height
        )
    }

    package static func offscreenRightFrame(from frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.maxX + rightInset, y: frame.minY, width: frame.width, height: frame.height)
    }
}
