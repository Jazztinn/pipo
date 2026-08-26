import CoreGraphics

package enum PipoMenuPanelGeometry {
    package static let compactSize = CGSize(width: 420, height: 660)
    package static let expandedSize = CGSize(width: 760, height: 660)

    // Expanded CSS geometry: 12pt outer inset, 340pt inspector, 16pt gap,
    // then the canonical 380pt main pane.
    private static let expandedMainMidX: CGFloat = 12 + 340 + 16 + 190

    package static func frame(
        anchoredTo statusItemFrame: CGRect,
        in visibleFrame: CGRect,
        inspectorVisible: Bool,
        topGap: CGFloat = 6
    ) -> CGRect {
        let compactHeight = min(compactSize.height, visibleFrame.height)
        let compactFrame = clamp(
            CGRect(
                x: statusItemFrame.midX - compactSize.width / 2,
                y: statusItemFrame.minY - topGap - compactHeight,
                width: compactSize.width,
                height: compactHeight
            ),
            to: visibleFrame
        )
        guard inspectorVisible,
              let expandedFrame = expandedFrame(preservingMainFrom: compactFrame, in: visibleFrame)
        else { return compactFrame }
        return expandedFrame
    }

    package static func usesExpandedInspector(
        anchoredTo statusItemFrame: CGRect,
        in visibleFrame: CGRect,
        topGap: CGFloat = 6
    ) -> Bool {
        frame(
            anchoredTo: statusItemFrame,
            in: visibleFrame,
            inspectorVisible: true,
            topGap: topGap
        ).width == expandedSize.width
    }

    private static func expandedFrame(preservingMainFrom compactFrame: CGRect, in visibleFrame: CGRect) -> CGRect? {
        guard visibleFrame.width >= expandedSize.width else { return nil }
        let height = min(expandedSize.height, visibleFrame.height)
        let candidate = CGRect(
            x: compactFrame.midX - expandedMainMidX,
            y: compactFrame.maxY - height,
            width: expandedSize.width,
            height: height
        )
        guard candidate.minX >= visibleFrame.minX, candidate.maxX <= visibleFrame.maxX else { return nil }
        return candidate
    }

    private static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(max(result.minX, visibleFrame.minX), visibleFrame.maxX - result.width)
        result.origin.y = min(max(result.minY, visibleFrame.minY), visibleFrame.maxY - result.height)
        return result
    }
}
