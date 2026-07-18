import CoreGraphics
import Testing
@testable import TrafficLightsPlus

@Test func dockClickTrackingRequiresTheAlreadyFrontmostApplication() {
    #expect(DockClickController.shouldTrackClick(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "COM.EXAMPLE.EDITOR"
    ))
    #expect(!DockClickController.shouldTrackClick(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Browser"
    ))
    #expect(!DockClickController.shouldTrackClick(
        featureEnabled: false,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor"
    ))
}

@Test func dockClickCandidateRejectsDragsAndDifferentDockItems() {
    let candidate = DockClickCandidate(
        pid: 42,
        bundleIdentifier: "com.example.Editor",
        location: CGPoint(x: 100, y: 800),
        timestamp: 10
    )

    #expect(candidate.matches(
        bundleIdentifier: "COM.EXAMPLE.EDITOR",
        location: CGPoint(x: 104, y: 803),
        timestamp: 10.2
    ))
    #expect(!candidate.matches(
        bundleIdentifier: "com.example.Browser",
        location: CGPoint(x: 104, y: 803),
        timestamp: 10.2
    ))
    #expect(!candidate.matches(
        bundleIdentifier: "com.example.Editor",
        location: CGPoint(x: 120, y: 800),
        timestamp: 10.2
    ))
    #expect(!candidate.matches(
        bundleIdentifier: "com.example.Editor",
        location: CGPoint(x: 100, y: 800),
        timestamp: 11.1
    ))
}
