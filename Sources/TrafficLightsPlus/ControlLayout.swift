import CoreGraphics
import Foundation

struct ControlLayout {
    static let sizeRange = 18.0...48.0
    static let spacingAdjustmentRange = -8.0...32.0
    static let activationPadding: CGFloat = 6

    static func effectiveSize(preferred: Double) -> CGFloat {
        CGFloat(min(max(preferred, sizeRange.lowerBound), sizeRange.upperBound))
    }

    static func effectiveSpacingAdjustment(preferred: Double) -> CGFloat {
        CGFloat(min(
            max(preferred, spacingAdjustmentRange.lowerBound),
            spacingAdjustmentRange.upperBound
        ))
    }

    static func centerByAdjustingSystemSpacing(
        _ nativeCenter: CGPoint,
        action: WindowAction,
        adjustment: CGFloat
    ) -> CGPoint {
        let index = displayOrder(for: .macOS).firstIndex(of: action) ?? 0
        return CGPoint(
            x: nativeCenter.x + CGFloat(index) * adjustment,
            y: nativeCenter.y
        )
    }

    static func frameCentered(on nativeFrame: CGRect, controlSize: CGFloat) -> CGRect {
        CGRect(
            x: nativeFrame.midX - controlSize / 2,
            y: nativeFrame.midY - controlSize / 2,
            width: controlSize,
            height: controlSize
        )
    }

    static func frames(
        style: ControlStyle,
        controlSize: CGFloat,
        windowOrigin: CGPoint,
        windowSize: CGSize
    ) -> [WindowAction: CGRect] {
        let buttonWidth = controlSize
        let gap: CGFloat = style == .macOS ? 8 : 0
        let topInset: CGFloat = style == .edgeSquares ? 0 : 4
        let left: CGFloat

        switch style {
        case .macOS:
            left = windowOrigin.x + 12
        case .edgeSquares:
            left = windowOrigin.x
        }

        return Dictionary(uniqueKeysWithValues: displayOrder(for: style).enumerated().map { index, action in
            let spacing = buttonWidth + gap
            let frame = CGRect(
                x: left + CGFloat(index) * spacing,
                y: windowOrigin.y + topInset,
                width: buttonWidth,
                height: controlSize
            )
            return (action, frame)
        })
    }

    static func displayOrder(for style: ControlStyle) -> [WindowAction] {
        [.close, .minimize, .zoom]
    }

    static func unobscuredActions(
        controlFrames: [WindowAction: CGRect],
        coveringFrames: [CGRect]
    ) -> Set<WindowAction> {
        Set(controlFrames.compactMap { action, frame in
            coveringFrames.contains(where: { $0.intersects(frame) }) ? nil : action
        })
    }

    static func activationRegion(
        controlFrames: [WindowAction: CGRect],
        actions: Set<WindowAction>,
        padding: CGFloat = activationPadding
    ) -> CGRect? {
        let frames = actions.compactMap { controlFrames[$0] }
        guard var region = frames.first else { return nil }
        for frame in frames.dropFirst() { region = region.union(frame) }
        return region.insetBy(dx: -padding, dy: -padding)
    }

    static func interpolatedFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        let progress = min(max(progress, 0), 1)
        return CGRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }

    static func nextPresentationProgress(
        current: CGFloat,
        elapsed: TimeInterval,
        expanding: Bool,
        duration: TimeInterval
    ) -> CGFloat {
        guard duration > 0 else { return expanding ? 1 : 0 }
        let delta = CGFloat(max(elapsed, 0) / duration)
        return expanding ? min(1, current + delta) : max(0, current - delta)
    }

}
