import CoreGraphics
import Foundation

struct FastDragGuard {
    static let displacementThreshold: CGFloat = 8
    static let recoveryDelay: TimeInterval = 0.06

    private(set) var suppressedUntil = 0.0

    mutating func observe(
        delta: CGPoint,
        now: TimeInterval,
        enabled: Bool
    ) -> Bool {
        guard enabled else {
            suppressedUntil = 0
            return false
        }

        if max(abs(delta.x), abs(delta.y)) > Self.displacementThreshold {
            suppressedUntil = max(suppressedUntil, now + Self.recoveryDelay)
        }
        if now >= suppressedUntil {
            suppressedUntil = 0
            return false
        }
        return true
    }

    mutating func reset() {
        suppressedUntil = 0
    }
}
