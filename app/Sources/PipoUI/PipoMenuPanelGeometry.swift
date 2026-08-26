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
    package static let compactSize = CGSize(width: 420, height: 660)
    package static let expandedSize = CGSize(width: 760, height: 660)
    package static let rightInset: CGFloat = 8
    package static let topGap: CGFloat = 6
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
        let leadingInset: CGFloat = inspectorVisible ? 368 : 28
        let trailingInset: CGFloat = 12
        let available = max(0, panelFrame.width - leadingInset - trailingInset)
        return CGRect(
            x: panelFrame.minX + leadingInset,
            y: panelFrame.minY,
            width: min(380, available),
            height: panelFrame.height
        )
    }

    package static func offscreenRightFrame(from frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.maxX + rightInset, y: frame.minY, width: frame.width, height: frame.height)
    }
}
