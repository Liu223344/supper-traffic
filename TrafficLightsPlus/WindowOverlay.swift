import AppKit
import ApplicationServices
import OSLog

struct AXWindowKey: Hashable {
    let pid: pid_t
    let element: AXUIElement

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(CFHash(element))
    }

    static func == (lhs: AXWindowKey, rhs: AXWindowKey) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }
}

enum OverlayPresentationState {
    case hidden
    case expanding
    case visible
    case collapsing
    case suppressed
}

final class WindowOverlay {
    private static let minimizeDispatchDelay = 1.0 / 120.0
    static let minimizeDismissDuration = 0.060
    private static let geometryTransitionTimeout = 0.45
    private static let revealDuration = 0.10

    let key: AXWindowKey
    private var panels: [WindowAction: OverlayPanel] = [:]
    private(set) var windowFrame = CGRect.zero
    private(set) var title = ""
    private(set) var cgWindowID: CGWindowID?

    private let window: AXUIElement
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "window-overlay")
    private var targetButtons: [WindowAction: AXUIElement] = [:]
    private var fullScreenSessionActive = false
    private var cachedFullScreenButtons: [WindowAction: AXUIElement] = [:]
    private var cachedFullScreenCenterOffsets: [WindowAction: CGPoint] = [:]
    private var nativeCenterOffsets: [WindowAction: CGPoint] = [:]
    private var nativeFrameOffsets: [WindowAction: CGRect] = [:]
    private var preparedCGFrames: [WindowAction: CGRect] = [:]
    private var preparedActions = Set<WindowAction>()
    private var availableActions = Set<WindowAction>()
    private var visibleActions = Set<WindowAction>()
    private var configuredBehaviors: [WindowAction: ButtonBehavior] = [:]
    private var controlEnabledByAction: [WindowAction: Bool] = [:]
    private var configuredStyle = ControlStyle.macOS
    private var configuredControlSize = CGFloat(28)
    private var configuredZoomButtonSymbol = ZoomButtonSymbol.fullScreen
    private var configuredPanelLevel = NSWindow.Level.floating
    private var configuredWindowIsActive = false
    private var configuredUsesMonochromeControls = false
    private var configuredCloseButtonIsEdited = false
    private(set) var isSuppressed = false
    private var isEligibleForDisplay = true
    private var lastDiagnostic = ""
    private var hoverResetWorkItem: DispatchWorkItem?
    private var dismissRequestGeneration = 0
    private var isActionDismissalInProgress = false
    /// While set, overlays stay torn down and pointer hover cannot re-reveal them.
    private var geometryTransitionBaseline: CGRect?
    private var nativeCommitPending = false
    private var nativeMouseUpMonitor: Any?
    private var hiddenModeEnabled = true
    private var revealMode = HiddenTrafficLightRevealMode.nearest
    private var presentationProgressByAction = Dictionary(
        uniqueKeysWithValues: WindowAction.allCases.map { ($0, CGFloat.zero) }
    )
    private var selectedNearestAction: WindowAction?
    private var interactiveActions = Set<WindowAction>()
    private var lastDesiredActions = Set<WindowAction>()
    private var lastPresentationUpdate = 0.0
    private(set) var presentationState = OverlayPresentationState.hidden

    init(key: AXWindowKey) {
        self.key = key
        window = key.element
    }

    var livePanelCount: Int { panels.count }

    @discardableResult
    func update(preferences: Preferences, recalibrateNativeCenters: Bool = true) -> Bool {
        guard let frame = axFrame(of: window), frame.width > 50, frame.height > 40 else {
            isEligibleForDisplay = false
            hide()
            return false
        }

        let minimized: Bool = copyAttribute(kAXMinimizedAttribute as CFString, from: window) ?? false
        if minimized {
            suppressUntilRestored()
            return false
        }
        let fullScreen: Bool = copyAttribute("AXFullScreen" as CFString, from: window) ?? false
        guard preferences.showInFullScreen || !fullScreen else {
            isEligibleForDisplay = false
            hide()
            return false
        }

        isEligibleForDisplay = true

        windowFrame = frame
        title = copyAttribute(kAXTitleAttribute as CFString, from: window) ?? ""
        let application = NSRunningApplication(processIdentifier: key.pid)
        let appIsActive = application?.isActive ?? false
        let windowIsFocused: Bool = copyAttribute(kAXFocusedAttribute as CFString, from: window) ?? false
        let windowIsMain: Bool = copyAttribute(kAXMainAttribute as CFString, from: window) ?? false
        let isActiveWindow = appIsActive && (windowIsFocused || windowIsMain)
        configuredBehaviors = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map {
            ($0, preferences.effectiveBehavior(
                for: $0,
                bundleIdentifier: application?.bundleIdentifier
            ))
        })
        let controlSize = ControlLayout.effectiveSize(preferred: preferences.size)
        if fullScreen { fullScreenSessionActive = true }
        var treatingAsFullScreen = preferences.showInFullScreen
            && (fullScreen || fullScreenSessionActive)
        var buttons: [WindowAction: AXUIElement] = [:]
        var frames: [WindowAction: CGRect] = [:]
        var currentlyCapturedActions = Set<WindowAction>()
        var directlyAttachedActions = Set<WindowAction>()
        let windowChildren: [AXUIElement]? = copyAttribute(kAXChildrenAttribute as CFString, from: window)

        for action in WindowAction.allCases {
            guard let button: AXUIElement = copyAttribute(attribute(for: action), from: window) else { continue }
            let enabled: Bool? = copyAttribute(kAXEnabledAttribute as CFString, from: button)
            let hidden: Bool? = copyAttribute(kAXHiddenAttribute as CFString, from: button)
            let nativeFrame = axFrame(of: button)
            let isWindowChild = windowChildren?.contains(where: { CFEqual($0, button) })
            guard Self.shouldDisplayNativeButton(
                enabled: enabled,
                hidden: hidden,
                frame: nativeFrame,
                windowFrame: frame,
                isWindowChild: isWindowChild,
                allowFullScreenTransientState: treatingAsFullScreen,
                // HUD / utility title bars nest the close button; minimize/zoom
                // on those panels are usually absent, and nested false-positives
                // should not become fake traffic lights.
                requireDirectWindowChild: action != .close
            ) else { continue }
            buttons[action] = button
            currentlyCapturedActions.insert(action)
            if isWindowChild == true,
               let nativeFrame,
               frame.contains(CGPoint(x: nativeFrame.midX, y: nativeFrame.midY)) {
                directlyAttachedActions.insert(action)
            }
            if let nativeFrame,
               recalibrateNativeCenters || nativeFrameOffsets[action] == nil {
                nativeFrameOffsets[action] = CGRect(
                    x: nativeFrame.minX - frame.minX,
                    y: nativeFrame.minY - frame.minY,
                    width: nativeFrame.width,
                    height: nativeFrame.height
                )
                nativeCenterOffsets[action] = CGPoint(
                    x: nativeFrame.midX - frame.minX,
                    y: nativeFrame.midY - frame.minY
                )
            }
        }

        // AXFullScreen can briefly flip while macOS animates the transient title bar.
        // Only a normal, directly attached traffic light proves that the window has
        // actually returned to windowed mode.
        if !fullScreen, !directlyAttachedActions.isEmpty {
            fullScreenSessionActive = false
            cachedFullScreenButtons.removeAll(keepingCapacity: true)
            cachedFullScreenCenterOffsets.removeAll(keepingCapacity: true)
            treatingAsFullScreen = false
        } else if treatingAsFullScreen, !currentlyCapturedActions.isEmpty {
            for action in currentlyCapturedActions {
                cachedFullScreenButtons[action] = buttons[action]
                cachedFullScreenCenterOffsets[action] = nativeCenterOffsets[action]
            }
        }

        if treatingAsFullScreen {
            for action in WindowAction.allCases where buttons[action] == nil {
                guard let cachedButton = cachedFullScreenButtons[action],
                      let cachedOffset = cachedFullScreenCenterOffsets[action] else { continue }
                // The button was enabled when captured. Once macOS removes the
                // transient title bar from the AX tree, querying AXEnabled on the
                // cached element can incorrectly return false or fail.
                buttons[action] = cachedButton
                nativeCenterOffsets[action] = cachedOffset
            }
        }

        if preferences.style == .macOS {
            for action in buttons.keys {
                guard let offset = nativeCenterOffsets[action] else { continue }
                let nativeCenter = CGPoint(x: frame.minX + offset.x, y: frame.minY + offset.y)
                let center = ControlLayout.centerByAdjustingSystemSpacing(
                    nativeCenter,
                    action: action,
                    adjustment: ControlLayout.effectiveSpacingAdjustment(preferred: preferences.spacing)
                )
                frames[action] = CGRect(
                    x: center.x - controlSize / 2,
                    y: center.y - controlSize / 2,
                    width: controlSize,
                    height: controlSize
                )
            }
        }

        if preferences.style == .edgeSquares {
            let edgeFrames = ControlLayout.frames(
                style: .edgeSquares,
                controlSize: controlSize,
                windowOrigin: frame.origin,
                windowSize: frame.size
            )
            for action in buttons.keys { frames[action] = edgeFrames[action] }
        }

        report(
            "pid=\(key.pid) fullScreen=\(fullScreen) session=\(fullScreenSessionActive) "
                + "current=\(currentlyCapturedActions.count) cached=\(cachedFullScreenButtons.count) "
                + "controls=\(buttons.count)"
        )

        targetButtons = buttons
        let zoomButtonSymbol: ZoomButtonSymbol
        if let zoomButton = buttons[.zoom] {
            let subrole: String? = copyAttribute(kAXSubroleAttribute as CFString, from: zoomButton)
            zoomButtonSymbol = Self.zoomButtonSymbol(forSubrole: subrole)
        } else {
            zoomButtonSymbol = .zoom
        }
        configuredStyle = preferences.style
        configuredControlSize = controlSize
        configuredZoomButtonSymbol = zoomButtonSymbol
        configuredPanelLevel = Self.panelLevel(forFullScreen: treatingAsFullScreen)
        configuredWindowIsActive = isActiveWindow
        configuredUsesMonochromeControls = Self.usesMonochromeControls(for: Set(buttons.keys))
        configuredCloseButtonIsEdited = buttons[.close].flatMap {
            copyAttribute(kAXEditedAttribute as CFString, from: $0) as Bool?
        } ?? false
        controlEnabledByAction = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { action in
            let behavior = configuredBehaviors[action] ?? ButtonBehavior.defaultBehavior(for: action)
            if let nativeAction = behavior.nativeWindowAction,
               treatingAsFullScreen,
               !currentlyCapturedActions.contains(nativeAction),
               cachedFullScreenButtons[nativeAction] != nil {
                return (action, true)
            }
            return (action, isBehaviorEnabled(behavior, buttons: buttons))
        })
        for (action, panel) in panels {
            configure(panel, for: action)
        }

        preparedCGFrames.removeAll(keepingCapacity: true)
        preparedActions.removeAll(keepingCapacity: true)
        for action in WindowAction.allCases {
            guard let cgFrame = frames[action], buttons[action] != nil else {
                releasePanel(for: action)
                continue
            }
            guard appKitFrame(for: cgFrame) != nil else {
                releasePanel(for: action)
                continue
            }

            preparedCGFrames[action] = cgFrame
            preparedActions.insert(action)
        }

        availableActions.formIntersection(preparedActions)
        for action in WindowAction.allCases where !preparedActions.contains(action) {
            releasePanel(for: action)
            visibleActions.remove(action)
        }
        return !preparedActions.isEmpty
    }

    static func shouldDisplayNativeButton(
        enabled: Bool?,
        hidden: Bool?,
        frame: CGRect?,
        windowFrame: CGRect,
        isWindowChild: Bool?,
        allowFullScreenTransientState: Bool = false,
        requireDirectWindowChild: Bool = false
    ) -> Bool {
        guard enabled ?? true,
              allowFullScreenTransientState || !(hidden ?? false),
              let frame,
              frame.width > 0,
              frame.height > 0 else { return false }
        // In macOS full screen, AX reports the content window below the revealed
        // title-bar area while its traffic lights remain at the physical screen top.
        // Their centers can therefore legitimately sit just outside windowFrame.
        if allowFullScreenTransientState { return true }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard windowFrame.contains(center) else { return false }
        if requireDirectWindowChild, isWindowChild == false { return false }
        // Utility / HUD / font panels often nest the close button under a title-bar
        // group instead of attaching it as a direct AX window child.
        return true
    }

    static func usesMonochromeControls(for availableActions: Set<WindowAction>) -> Bool {
        // Native HUD panels expose only a gray close button.
        availableActions == [.close]
    }

    static func zoomButtonSymbol(forSubrole subrole: String?) -> ZoomButtonSymbol {
        subrole == (kAXFullScreenButtonSubrole as String) ? .fullScreen : .zoom
    }

    static func panelLevel(forFullScreen fullScreen: Bool) -> NSWindow.Level {
        // Stay above normal windows and floating utility/HUD/font panels. Full-screen
        // transient title bars sit even higher, so those use pop-up-menu level.
        if fullScreen { return .popUpMenu }
        return NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }

    static func isTrackedWindowServerLayer(_ layer: Int) -> Bool {
        // Normal windows plus floating / modal / utility panels (font panel, HUD).
        // Keep menus, status items, and screen savers out.
        switch layer {
        case 0, 3, 8, 19: return true
        default: return false
        }
    }

    static func shouldIncludeWindowServerRecord(
        pid: pid_t,
        windowID: CGWindowID,
        ownPID: pid_t,
        settingsWindowID: CGWindowID?
    ) -> Bool {
        // Other apps: keep. Our process: only the settings window is an occluder;
        // overlay panels must not appear in the compositor list.
        if pid != ownPID { return true }
        guard let settingsWindowID else { return false }
        return windowID == settingsWindowID
    }

    func bind(to windowID: CGWindowID) {
        cgWindowID = windowID
    }

    func clearCGWindowBinding() {
        cgWindowID = nil
    }

    var hasPreparedControls: Bool { !preparedCGFrames.isEmpty }

    var controlFrames: [WindowAction: CGRect] {
        preparedCGFrames
    }

    func syncPosition(to currentWindowFrame: CGRect) {
        guard !isSuppressed else { return }
        // Keep overlays torn down for the whole zoom animation. Releasing early
        // (e.g. on a briefly stable intermediate frame) lets the still-hovered
        // pointer re-expand the green button mid-flight.
        guard geometryTransitionBaseline == nil else { return }
        let delta = CGPoint(
            x: currentWindowFrame.minX - windowFrame.minX,
            y: currentWindowFrame.minY - windowFrame.minY
        )
        guard abs(delta.x) > 0.01 || abs(delta.y) > 0.01 else { return }

        windowFrame.origin = currentWindowFrame.origin

        for action in preparedActions {
            guard var cgFrame = preparedCGFrames[action] else { continue }
            cgFrame.origin.x += delta.x
            cgFrame.origin.y += delta.y
            preparedCGFrames[action] = cgFrame
        }
    }

    func updatePresentation(
        availableActions actions: Set<WindowAction>,
        mouseLocation: NSPoint,
        hiddenModeEnabled: Bool,
        revealMode: HiddenTrafficLightRevealMode,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.hiddenModeEnabled = hiddenModeEnabled
        self.revealMode = revealMode
        guard !isSuppressed, isEligibleForDisplay else {
            presentationState = .suppressed
            resetPresentationProgress()
            hidePanels()
            return
        }
        guard geometryTransitionBaseline == nil else {
            presentationState = .hidden
            selectedNearestAction = nil
            resetPresentationProgress()
            // Veil only — closing panels here races AppKit mouse tracking and
            // can leave the enlarged control on-screen until mouseUp.
            veilPanels()
            return
        }

        availableActions = actions.intersection(preparedActions)
        guard !availableActions.isEmpty else {
            presentationState = .hidden
            selectedNearestAction = nil
            resetPresentationProgress()
            hidePanels()
            return
        }

        let desiredActions = isActionDismissalInProgress
            ? Set<WindowAction>()
            : desiredExpandedActions(mouseLocation: mouseLocation)
        let elapsed = lastPresentationUpdate > 0 ? min(max(now - lastPresentationUpdate, 0), 0.05) : 0
        lastPresentationUpdate = now

        for action in WindowAction.allCases {
            guard availableActions.contains(action) else {
                presentationProgressByAction[action] = 0
                continue
            }
            if isActionDismissalInProgress {
                presentationProgressByAction[action] = ControlLayout.nextPresentationProgress(
                    current: presentationProgressByAction[action] ?? 0,
                    elapsed: elapsed,
                    expanding: false,
                    duration: Self.minimizeDismissDuration
                )
            } else if !hiddenModeEnabled {
                presentationProgressByAction[action] = 1
            } else {
                presentationProgressByAction[action] = ControlLayout.nextPresentationProgress(
                    current: presentationProgressByAction[action] ?? 0,
                    elapsed: elapsed,
                    expanding: desiredActions.contains(action),
                    duration: Self.revealDuration
                )
            }
        }

        updatePresentationState(desiredActions: desiredActions)
        renderPresentation(desiredActions: desiredActions, mouseLocation: mouseLocation)
    }

    private func renderPresentation(
        desiredActions: Set<WindowAction>,
        mouseLocation: NSPoint
    ) {
        var nextVisibleActions = Set<WindowAction>()
        var pointerInsideButton = false

        for action in WindowAction.allCases {
            let linearProgress = presentationProgressByAction[action] ?? 0
            let progress = linearProgress * linearProgress * (3 - 2 * linearProgress)
            guard progress > 0,
                  availableActions.contains(action),
                  let nativeFrame = nativeCGFrame(for: action),
                  let targetFrame = preparedCGFrames[action] else {
                releasePanel(for: action)
                continue
            }

            let cgFrame = ControlLayout.interpolatedFrame(
                from: nativeFrame,
                to: targetFrame,
                progress: progress
            )
            guard let frame = appKitFrame(for: cgFrame) else {
                releasePanel(for: action)
                continue
            }

            let panel = ensurePanel(for: action)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            panel.alphaValue = 1
            panel.ignoresMouseEvents = !desiredActions.contains(action)
            if !panel.isVisible { panel.orderFrontRegardless() }
            nextVisibleActions.insert(action)

            let pointerInside = desiredActions.contains(action) && frame.contains(mouseLocation)
            panel.overlayView.setPointerInside(pointerInside)
            pointerInsideButton = pointerInsideButton || pointerInside
        }

        visibleActions = nextVisibleActions
        interactiveActions = desiredActions.intersection(nextVisibleActions)
        if desiredActions != lastDesiredActions {
            for action in ControlLayout.displayOrder(for: .macOS) where interactiveActions.contains(action) {
                panels[action]?.orderFrontRegardless()
            }
            lastDesiredActions = desiredActions
        }
        if visibleActions.isEmpty {
            hoverResetWorkItem?.cancel()
            hoverResetWorkItem = nil
        } else {
            setGroupHovered(pointerInsideButton)
        }
    }

    private func desiredExpandedActions(mouseLocation: NSPoint) -> Set<WindowAction> {
        guard hiddenModeEnabled else {
            selectedNearestAction = nil
            return availableActions
        }
        guard pointerInsideActivationRegion(mouseLocation) else {
            selectedNearestAction = nil
            return []
        }

        switch revealMode {
        case .group:
            selectedNearestAction = nil
            return ControlLayout.revealActions(
                mode: .group,
                pointer: mouseLocation,
                controlFrames: appKitControlFrames(actions: availableActions),
                actions: availableActions,
                currentAction: nil
            )
        case .nearest:
            let frames = appKitControlFrames(actions: availableActions)
            let actions = ControlLayout.revealActions(
                mode: .nearest,
                pointer: mouseLocation,
                controlFrames: frames,
                actions: availableActions,
                currentAction: selectedNearestAction
            )
            selectedNearestAction = actions.first
            return actions
        }
    }

    private func updatePresentationState(desiredActions: Set<WindowAction>) {
        let visibleProgress = presentationProgressByAction.filter { $0.value > 0 }
        guard !visibleProgress.isEmpty else {
            presentationState = .hidden
            return
        }
        if desiredActions.contains(where: { (presentationProgressByAction[$0] ?? 0) < 1 }) {
            presentationState = .expanding
        } else if visibleProgress.contains(where: { !desiredActions.contains($0.key) }) {
            presentationState = .collapsing
        } else {
            presentationState = .visible
        }
    }

    private func resetPresentationProgress() {
        for action in WindowAction.allCases { presentationProgressByAction[action] = 0 }
        interactiveActions.removeAll(keepingCapacity: true)
        lastDesiredActions.removeAll(keepingCapacity: true)
    }

    private func pointerInsideActivationRegion(_ mouseLocation: NSPoint) -> Bool {
        let frames = appKitControlFrames(actions: availableActions)
        guard let region = ControlLayout.activationRegion(
            controlFrames: frames,
            actions: availableActions
        ) else { return false }
        return region.contains(mouseLocation)
    }

    private func appKitControlFrames(actions: Set<WindowAction>) -> [WindowAction: CGRect] {
        Dictionary(uniqueKeysWithValues: actions.compactMap { action in
            guard let cgFrame = preparedCGFrames[action], let frame = appKitFrame(for: cgFrame) else { return nil }
            return (action, frame)
        })
    }

    private func nativeCGFrame(for action: WindowAction) -> CGRect? {
        if let offset = nativeFrameOffsets[action] {
            return CGRect(
                x: windowFrame.minX + offset.minX,
                y: windowFrame.minY + offset.minY,
                width: offset.width,
                height: offset.height
            )
        }
        guard let targetFrame = preparedCGFrames[action] else { return nil }
        return ControlLayout.frameCentered(on: targetFrame, controlSize: min(14, targetFrame.width))
    }

    private func appKitFrame(for cgFrame: CGRect) -> NSRect? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let cgBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard cgBounds.intersects(cgFrame) else { continue }
            return NSRect(
                x: screen.frame.minX + cgFrame.minX - cgBounds.minX,
                y: screen.frame.maxY - (cgFrame.minY - cgBounds.minY) - cgFrame.height,
                width: cgFrame.width,
                height: cgFrame.height
            )
        }
        return nil
    }

    func hide() {
        isActionDismissalInProgress = false
        resetPresentationProgress()
        selectedNearestAction = nil
        lastPresentationUpdate = 0
        presentationState = isSuppressed ? .suppressed : .hidden
        visibleActions.removeAll(keepingCapacity: true)
        hidePanels()
    }

    func suppressUntilRestored() {
        dismissRequestGeneration += 1
        cancelPendingNativeCommit()
        geometryTransitionBaseline = nil
        isSuppressed = true
        isEligibleForDisplay = false
        hide()
    }

    func restoreFromSuppression() {
        dismissRequestGeneration += 1
        cancelPendingNativeCommit()
        geometryTransitionBaseline = nil
        isSuppressed = false
        isEligibleForDisplay = true
        isActionDismissalInProgress = false
        resetPresentationProgress()
        selectedNearestAction = nil
        lastPresentationUpdate = 0
        presentationState = .hidden
    }

    private func hidePanels() {
        hoverResetWorkItem?.cancel()
        hoverResetWorkItem = nil
        visibleActions.removeAll(keepingCapacity: true)
        interactiveActions.removeAll(keepingCapacity: true)
        lastDesiredActions.removeAll(keepingCapacity: true)
        releaseAllPanels()
    }

    /// Instantly hides overlay windows without `close()`, which AppKit may defer
    /// until mouse tracking ends if called from inside `mouseDown`.
    private func veilPanels() {
        hoverResetWorkItem?.cancel()
        hoverResetWorkItem = nil
        for panel in panels.values {
            panel.overlayView.actionHandler = nil
            panel.overlayView.hoverHandler = nil
            panel.overlayView.resetInteractionState()
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        }
        visibleActions.removeAll(keepingCapacity: true)
        interactiveActions.removeAll(keepingCapacity: true)
        lastDesiredActions.removeAll(keepingCapacity: true)
    }

    private func cancelPendingNativeCommit() {
        nativeCommitPending = false
        if let nativeMouseUpMonitor {
            NSEvent.removeMonitor(nativeMouseUpMonitor)
            self.nativeMouseUpMonitor = nil
        }
    }

    private func ensurePanel(for action: WindowAction) -> OverlayPanel {
        if let panel = panels[action] {
            return panel
        }

        let panel = OverlayPanel(action: action)
        panel.overlayView.actionHandler = { [weak self] action in self?.perform(action) }
        panel.overlayView.hoverHandler = { [weak self] hovered in self?.setGroupHovered(hovered) }
        configure(panel, for: action)
        panels[action] = panel
        return panel
    }

    private func configure(_ panel: OverlayPanel, for action: WindowAction) {
        panel.level = configuredPanelLevel
        panel.overlayView.style = configuredStyle
        panel.overlayView.controlSize = configuredControlSize
        panel.overlayView.behavior = configuredBehaviors[action] ?? ButtonBehavior.defaultBehavior(for: action)
        panel.overlayView.zoomButtonSymbol = configuredZoomButtonSymbol
        panel.overlayView.isControlEnabled = controlEnabledByAction[action] ?? false
        panel.overlayView.isWindowActive = configuredWindowIsActive
        panel.overlayView.usesMonochromeControls = configuredUsesMonochromeControls
        panel.overlayView.isNativeCloseButtonEdited = action == .close && configuredCloseButtonIsEdited
    }

    private func releasePanel(for action: WindowAction) {
        guard let panel = panels.removeValue(forKey: action) else { return }
        panel.overlayView.actionHandler = nil
        panel.overlayView.hoverHandler = nil
        panel.overlayView.resetInteractionState()
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        panel.close()
    }

    private func releaseAllPanels() {
        for action in Array(panels.keys) {
            releasePanel(for: action)
        }
    }

    private func setGroupHovered(_ hovered: Bool) {
        if hovered {
            hoverResetWorkItem?.cancel()
            hoverResetWorkItem = nil
            for (action, panel) in panels {
                panel.overlayView.isGroupHovered = interactiveActions.contains(action)
            }
            return
        }

        guard hoverResetWorkItem == nil,
              panels.values.contains(where: { $0.overlayView.isGroupHovered }) else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panels.values.forEach { $0.overlayView.isGroupHovered = false }
            self.hoverResetWorkItem = nil
        }
        hoverResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func perform(_ action: WindowAction) {
        let behavior = configuredBehaviors[action] ?? ButtonBehavior.defaultBehavior(for: action)

        if let nativeAction = behavior.nativeWindowAction {
            guard let button = targetButtons[nativeAction] else { NSSound.beep(); return }
            switch behavior {
            case .closeWindow:
                performClose(using: button)
            case .minimizeWindow:
                performMinimize(using: button)
            case .zoomWindow:
                performZoom(using: button)
            default:
                if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success {
                    NSSound.beep()
                }
            }
            return
        }

        guard let application = NSRunningApplication(processIdentifier: key.pid) else {
            NSSound.beep()
            return
        }
        switch behavior {
        case .quitApplication:
            if !application.terminate() { NSSound.beep() }
        case .hideApplication:
            if !application.hide() { NSSound.beep() }
        case .doNothing:
            break
        case .closeWindow, .minimizeWindow, .zoomWindow:
            break
        }
    }

    /// Shared path for close / minimize / zoom: veil on mouseDown, commit on mouseUp.
    /// Closing an NSPanel inside mouseDown is deferred by AppKit until tracking ends,
    /// which otherwise leaves the enlarged control visible through the window animation.
    private func beginVeiledNativeCommit(commit: @escaping (_ generation: Int) -> Void) {
        dismissRequestGeneration += 1
        let generation = dismissRequestGeneration
        cancelPendingNativeCommit()
        isActionDismissalInProgress = false
        selectedNearestAction = nil
        interactiveActions.removeAll(keepingCapacity: true)
        hoverResetWorkItem?.cancel()
        hoverResetWorkItem = nil

        geometryTransitionBaseline = windowFrame
        veilPanels()
        resetPresentationProgress()
        lastPresentationUpdate = 0
        presentationState = .hidden
        nativeCommitPending = true

        let runCommit = { [weak self] in
            guard let self,
                  generation == self.dismissRequestGeneration,
                  self.nativeCommitPending else { return }
            self.nativeCommitPending = false
            if let monitor = self.nativeMouseUpMonitor {
                NSEvent.removeMonitor(monitor)
                self.nativeMouseUpMonitor = nil
            }
            commit(generation)
        }

        if NSEvent.pressedMouseButtons & (1 << 0) == 0 {
            DispatchQueue.main.async(execute: runCommit)
            return
        }

        nativeMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            DispatchQueue.main.async(execute: runCommit)
            return event
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: runCommit)
    }

    private func performClose(using button: AXUIElement) {
        let actionsToRestore = interactiveActions
        beginVeiledNativeCommit { [weak self] generation in
            guard let self else { return }
            self.hidePanels()
            if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success {
                self.geometryTransitionBaseline = nil
                self.availableActions = actionsToRestore.intersection(self.preparedActions)
                for action in actionsToRestore { self.presentationProgressByAction[action] = 1 }
                self.interactiveActions = actionsToRestore
                self.presentationState = .visible
                self.renderPresentation(
                    desiredActions: actionsToRestore,
                    mouseLocation: NSEvent.mouseLocation
                )
                NSSound.beep()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.geometryTransitionTimeout) { [weak self] in
                guard let self, generation == self.dismissRequestGeneration else { return }
                self.geometryTransitionBaseline = nil
            }
        }
    }

    private func performMinimize(using button: AXUIElement) {
        let actionsToRestore = interactiveActions
        beginVeiledNativeCommit { [weak self] _ in
            guard let self else { return }
            self.hidePanels()
            self.suppressUntilRestored()
            let suppressionGeneration = self.dismissRequestGeneration

            // Give WindowServer one display frame to commit the hidden overlay
            // before the target application begins its minimize animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.minimizeDispatchDelay) { [weak self] in
                guard let self, suppressionGeneration == self.dismissRequestGeneration else { return }
                self.pressMinimizeButton(button, restoring: actionsToRestore)
            }
        }
    }

    private func performZoom(using button: AXUIElement) {
        let actionsToRestore = interactiveActions
        beginVeiledNativeCommit { [weak self] generation in
            guard let self else { return }
            self.hidePanels()
            self.pressZoomButton(button, restoring: actionsToRestore, generation: generation)
        }
    }

    private func pressMinimizeButton(
        _ button: AXUIElement,
        restoring actionsToRestore: Set<WindowAction>
    ) {
        if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success {
            restoreFromSuppression()
            availableActions = actionsToRestore.intersection(preparedActions)
            for action in actionsToRestore { presentationProgressByAction[action] = 1 }
            interactiveActions = actionsToRestore
            presentationState = .visible
            renderPresentation(
                desiredActions: actionsToRestore,
                mouseLocation: NSEvent.mouseLocation
            )
            NSSound.beep()
        }
    }

    private func pressZoomButton(
        _ button: AXUIElement,
        restoring actionsToRestore: Set<WindowAction>,
        generation: Int
    ) {
        if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success {
            geometryTransitionBaseline = nil
            availableActions = actionsToRestore.intersection(preparedActions)
            for action in actionsToRestore { presentationProgressByAction[action] = 1 }
            interactiveActions = actionsToRestore
            presentationState = .visible
            renderPresentation(
                desiredActions: actionsToRestore,
                mouseLocation: NSEvent.mouseLocation
            )
            NSSound.beep()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.geometryTransitionTimeout) { [weak self] in
            guard let self, generation == self.dismissRequestGeneration else { return }
            self.geometryTransitionBaseline = nil
        }
    }

    private func isBehaviorEnabled(
        _ behavior: ButtonBehavior,
        buttons: [WindowAction: AXUIElement]
    ) -> Bool {
        if let nativeAction = behavior.nativeWindowAction {
            guard let button = buttons[nativeAction] else { return false }
            return copyAttribute(kAXEnabledAttribute as CFString, from: button) ?? true
        }
        switch behavior {
        case .quitApplication, .hideApplication:
            return NSRunningApplication(processIdentifier: key.pid) != nil
        case .doNothing:
            return false
        case .closeWindow, .minimizeWindow, .zoomWindow:
            return false
        }
    }

    private func attribute(for action: WindowAction) -> CFString {
        switch action {
        case .close: return kAXCloseButtonAttribute as CFString
        case .minimize: return kAXMinimizeButtonAttribute as CFString
        case .zoom: return kAXZoomButtonAttribute as CFString
        }
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = copyAttribute(kAXPositionAttribute as CFString, from: element),
              let size: AXValue = copyAttribute(kAXSizeAttribute as CFString, from: element) else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }

    private func report(_ diagnostic: String) {
        guard diagnostic != lastDiagnostic else { return }
        lastDiagnostic = diagnostic
        logger.notice("\(diagnostic, privacy: .public)")
    }

}
