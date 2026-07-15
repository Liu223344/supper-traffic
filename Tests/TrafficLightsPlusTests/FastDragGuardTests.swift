import CoreGraphics
import Testing
@testable import TrafficLightsPlus

@Test func fastDragGuardSuppressesLargeMovementUntilStable() {
    var guardState = FastDragGuard()

    let slow = guardState.observe(delta: CGPoint(x: 4, y: 3), now: 1.0, enabled: true)
    let fast = guardState.observe(delta: CGPoint(x: 12, y: 2), now: 2.0, enabled: true)
    let settling = guardState.observe(delta: .zero, now: 2.04, enabled: true)
    let stable = guardState.observe(delta: .zero, now: 2.07, enabled: true)

    #expect(!slow)
    #expect(fast)
    #expect(settling)
    #expect(!stable)
}

@Test func disablingFastDragGuardClearsSuppression() {
    var guardState = FastDragGuard()
    _ = guardState.observe(delta: CGPoint(x: 20, y: 0), now: 3.0, enabled: true)

    let disabled = guardState.observe(delta: .zero, now: 3.01, enabled: false)

    #expect(!disabled)
    #expect(guardState.suppressedUntil == 0)
}
