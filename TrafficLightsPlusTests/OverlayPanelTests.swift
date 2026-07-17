import AppKit
import ApplicationServices
import Testing
@testable import TrafficLightsPlus

@MainActor
@Test func overlayContentFillsResizedPanel() {
    let panel = OverlayPanel(action: .close)
    panel.setFrame(NSRect(x: 100, y: 100, width: 40, height: 40), display: false)
    panel.contentView?.layoutSubtreeIfNeeded()

    #expect(panel.overlayView.frame.origin == .zero)
    #expect(panel.overlayView.frame.size == NSSize(width: 40, height: 40))
    #expect(panel.level == .floating)
}

@Test func fullScreenPanelsAppearAboveTheTransientSystemTitleBar() {
    #expect(WindowOverlay.panelLevel(forFullScreen: false).rawValue == NSWindow.Level.floating.rawValue + 1)
    #expect(WindowOverlay.panelLevel(forFullScreen: true) == .popUpMenu)
    #expect(
        WindowOverlay.panelLevel(forFullScreen: true).rawValue
            > NSWindow.Level.statusBar.rawValue
    )
    #expect(
        WindowOverlay.panelLevel(forFullScreen: false).rawValue
            > NSWindow.Level.floating.rawValue
    )
}

@MainActor
@Test func minimizedOverlayStaysSuppressedUntilRestored() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let key = AXWindowKey(pid: pid, element: AXUIElementCreateApplication(pid))
    let overlay = WindowOverlay(key: key)

    overlay.suppressUntilRestored()
    #expect(overlay.isSuppressed)
    #expect(overlay.presentationState == .suppressed)

    overlay.restoreFromSuppression()
    #expect(!overlay.isSuppressed)
    #expect(overlay.presentationState == .hidden)
}

@MainActor
@Test func trackedWindowDoesNotEagerlyCreateOverlayPanels() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let key = AXWindowKey(pid: pid, element: AXUIElementCreateApplication(pid))
    let overlay = WindowOverlay(key: key)

    #expect(overlay.livePanelCount == 0)
    overlay.hide()
    #expect(overlay.livePanelCount == 0)
}

@MainActor
@Test func overlayColorVisibilityFollowsActivationAndHover() {
    let panel = OverlayPanel(action: .close)

    #expect(!panel.overlayView.isColorVisible)
    panel.overlayView.isGroupHovered = true
    #expect(panel.overlayView.isColorVisible)
    panel.overlayView.isGroupHovered = false
    #expect(!panel.overlayView.isColorVisible)

    panel.overlayView.isWindowActive = true
    #expect(panel.overlayView.isColorVisible)
    #expect(!panel.overlayView.isPointerHighlightVisible)
}

@Test func symbolRectUsesAnimatedBoundsInsteadOfConfiguredControlSize() throws {
    let compactBounds = NSRect(x: 0, y: 0, width: 14, height: 14)
    let symbolRect = try #require(OverlayButtonView.symbolRect(in: compactBounds, style: .macOS))

    #expect(symbolRect.minX.isFinite)
    #expect(symbolRect.minY.isFinite)
    #expect(symbolRect.width > 0)
    #expect(symbolRect.height > 0)
}

@Test func zoomSymbolUsesTwoOutwardFacingTriangles() {
    let triangles = OverlayButtonView.zoomSymbolTriangles(
        in: NSRect(x: 0, y: 0, width: 10, height: 10)
    )

    #expect(triangles.count == 2)
    #expect(triangles.allSatisfy { $0.count == 3 })
    #expect(triangles[0] == [
        NSPoint(x: 0, y: 0),
        NSPoint(x: 9, y: 0),
        NSPoint(x: 0, y: 9),
    ])
    #expect(triangles[1] == [
        NSPoint(x: 10, y: 10),
        NSPoint(x: 1, y: 10),
        NSPoint(x: 10, y: 1),
    ])
}

@Test func onlyVisibleNativeButtonsArePreparedForDisplay() {
    let windowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    let buttonFrame = CGRect(x: 112, y: 112, width: 14, height: 14)

    #expect(WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: false,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: true
    ))
    #expect(!WindowOverlay.shouldDisplayNativeButton(
        enabled: false,
        hidden: false,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: true
    ))
    #expect(!WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: true,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: true
    ))
    #expect(!WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: nil,
        frame: nil,
        windowFrame: windowFrame,
        isWindowChild: true
    ))
    #expect(!WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: nil,
        frame: CGRect(x: 0, y: 0, width: 14, height: 14),
        windowFrame: windowFrame,
        isWindowChild: true
    ))
    // Nested title-bar close buttons (HUD / font panel) are still on-window.
    #expect(WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: nil,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: false
    ))
    #expect(!WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: nil,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: false,
        requireDirectWindowChild: true
    ))
    #expect(WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: nil,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: nil
    ))
}

@Test func closeOnlyPanelsUseMonochromeControls() {
    #expect(WindowOverlay.usesMonochromeControls(for: [.close]))
    #expect(!WindowOverlay.usesMonochromeControls(for: [.close, .minimize, .zoom]))
    #expect(!WindowOverlay.usesMonochromeControls(for: [.close, .zoom]))
}

@MainActor
@Test func monochromeCloseButtonStaysGrayWhenWindowIsActive() {
    let panel = OverlayPanel(action: .close)
    panel.overlayView.usesMonochromeControls = true
    panel.overlayView.isWindowActive = true
    panel.overlayView.isControlEnabled = true

    #expect(panel.overlayView.isColorVisible)
    #expect(!panel.overlayView.isPointerHighlightVisible)
}

@Test func monochromeCloseSymbolUsesBlackInsteadOfGrayTint() throws {
    let symbol = try #require(
        OverlayButtonView.monochromeSymbolColor(isEnabled: true).usingColorSpace(.sRGB)
    )
    #expect(symbol.redComponent == 0)
    #expect(symbol.greenComponent == 0)
    #expect(symbol.blueComponent == 0)
    #expect(symbol.alphaComponent == 0.92)
}

@Test func hudCloseButtonUsesExactLightGrayFill() throws {
    let color = try #require(OverlayButtonView.hudControlColor.usingColorSpace(.sRGB))
    #expect(abs(color.redComponent - 0xDF / 255) < 0.0001)
    #expect(abs(color.greenComponent - 0xDF / 255) < 0.0001)
    #expect(abs(color.blueComponent - 0xDF / 255) < 0.0001)
}

@Test func hudCloseSymbolIsSlightlyHeavierThanStandardTrafficLightGlyph() {
    let size: CGFloat = 28
    let standard = OverlayButtonView.symbolLineWidth(visualSize: size, usesMonochromeControls: false)
    let hud = OverlayButtonView.symbolLineWidth(visualSize: size, usesMonochromeControls: true)
    #expect(hud > standard)
    #expect(abs(hud - size * 0.078) < 0.0001)
    #expect(abs(standard - size * 0.062) < 0.0001)
}

@Test func trackedWindowServerLayersIncludeFloatingUtilityPanels() {
    #expect(WindowOverlay.isTrackedWindowServerLayer(0))
    #expect(WindowOverlay.isTrackedWindowServerLayer(3))
    #expect(WindowOverlay.isTrackedWindowServerLayer(8))
    #expect(WindowOverlay.isTrackedWindowServerLayer(19))
    #expect(!WindowOverlay.isTrackedWindowServerLayer(25))
    #expect(!WindowOverlay.isTrackedWindowServerLayer(101))
}

@Test func ownProcessKeepsOnlyTheRegisteredSettingsWindow() {
    let ownPID: pid_t = 1234
    let settingsID: CGWindowID = 42
    #expect(WindowOverlay.shouldIncludeWindowServerRecord(
        pid: ownPID,
        windowID: settingsID,
        ownPID: ownPID,
        settingsWindowID: settingsID
    ))
    #expect(!WindowOverlay.shouldIncludeWindowServerRecord(
        pid: ownPID,
        windowID: 99,
        ownPID: ownPID,
        settingsWindowID: settingsID
    ))
    #expect(!WindowOverlay.shouldIncludeWindowServerRecord(
        pid: ownPID,
        windowID: settingsID,
        ownPID: ownPID,
        settingsWindowID: nil
    ))
    #expect(WindowOverlay.shouldIncludeWindowServerRecord(
        pid: 5678,
        windowID: 99,
        ownPID: ownPID,
        settingsWindowID: settingsID
    ))
}

@Test func fullScreenTransientButtonsRemainAvailableWhenEnabled() {
    // Full-screen AX geometry observed on macOS: the content window begins below
    // the menu/title-bar reveal area, while the traffic lights stay at screen top.
    let windowFrame = CGRect(x: 0, y: 33, width: 1512, height: 949)
    let buttonFrame = CGRect(x: 8, y: 9, width: 16, height: 16)

    #expect(WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: true,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: false,
        allowFullScreenTransientState: true
    ))
    #expect(!WindowOverlay.shouldDisplayNativeButton(
        enabled: true,
        hidden: nil,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: false
    ))
    #expect(!WindowOverlay.shouldDisplayNativeButton(
        enabled: false,
        hidden: true,
        frame: buttonFrame,
        windowFrame: windowFrame,
        isWindowChild: false,
        allowFullScreenTransientState: true
    ))
}

@Test func trafficLightSymbolsUseDarkTintedColorsInsteadOfPureBlack() throws {
    let green = NSColor(srgbRed: 0.15686, green: 0.78431, blue: 0.25098, alpha: 1)
    let symbol = try #require(
        OverlayButtonView.symbolColor(for: green, isEnabled: true)
            .usingColorSpace(.sRGB)
    )

    #expect(symbol.greenComponent > symbol.redComponent)
    #expect(symbol.greenComponent > symbol.blueComponent)
    #expect(symbol.greenComponent < green.greenComponent)
    #expect(symbol.alphaComponent == 0.86)
}

@Test func editedIndicatorOnlyReplacesTheNativeCloseSymbol() {
    #expect(OverlayButtonView.shouldDrawEditedIndicator(
        action: .close,
        behavior: .closeWindow,
        isEdited: true
    ))
    #expect(!OverlayButtonView.shouldDrawEditedIndicator(
        action: .close,
        behavior: .closeWindow,
        isEdited: false
    ))
    #expect(!OverlayButtonView.shouldDrawEditedIndicator(
        action: .close,
        behavior: .quitApplication,
        isEdited: true
    ))
    #expect(!OverlayButtonView.shouldDrawEditedIndicator(
        action: .minimize,
        behavior: .closeWindow,
        isEdited: true
    ))
}

@Test func zoomButtonSymbolMatchesAccessibilitySubrole() {
    #expect(WindowOverlay.zoomButtonSymbol(forSubrole: kAXFullScreenButtonSubrole as String) == .fullScreen)
    #expect(WindowOverlay.zoomButtonSymbol(forSubrole: kAXZoomButtonSubrole as String) == .zoom)
    #expect(WindowOverlay.zoomButtonSymbol(forSubrole: nil) == .zoom)
}

@MainActor
@Test func maximumConfiguredSizeDrawsInsideNativeSizedAnimationFrame() throws {
    for action in WindowAction.allCases {
        let panel = OverlayPanel(action: action)
        panel.overlayView.controlSize = 48
        panel.overlayView.behavior = ButtonBehavior.defaultBehavior(for: action)
        panel.setFrame(NSRect(x: 0, y: 0, width: 14, height: 14), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()

        let representation = try #require(
            panel.overlayView.bitmapImageRepForCachingDisplay(in: panel.overlayView.bounds)
        )
        panel.overlayView.cacheDisplay(in: panel.overlayView.bounds, to: representation)
    }
}
