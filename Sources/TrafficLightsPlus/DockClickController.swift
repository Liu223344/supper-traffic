import AppKit
import ApplicationServices
import OSLog

private func dockClickEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<DockClickController>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.reenableEventTap()
    } else {
        controller.handleEvent(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

struct DockClickCandidate {
    let pid: pid_t
    let bundleIdentifier: String
    let location: CGPoint
    let timestamp: TimeInterval

    func matches(bundleIdentifier: String?, location: CGPoint, timestamp: TimeInterval) -> Bool {
        guard let bundleIdentifier,
              self.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame,
              timestamp >= self.timestamp,
              timestamp - self.timestamp <= DockClickController.maximumClickDuration else { return false }
        return hypot(location.x - self.location.x, location.y - self.location.y)
            <= DockClickController.maximumClickTravel
    }
}

final class DockClickController {
    static let maximumClickDuration = 1.0
    static let maximumClickTravel: CGFloat = 8
    private static let dockBundleIdentifier = "com.apple.dock"

    private let preferences: Preferences
    private let minimizeHandler: (pid_t) -> Bool
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "dock-click")
    private let systemWideElement = AXUIElementCreateSystemWide()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var candidate: DockClickCandidate?

    init(preferences: Preferences, minimizeHandler: @escaping (pid_t) -> Bool) {
        self.preferences = preferences
        self.minimizeHandler = minimizeHandler
        installEventTapIfPossible()
        if eventTap == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.installEventTapIfPossible()
            }
        }
    }

    deinit {
        retryTimer?.invalidate()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
    }

    static func shouldTrackClick(
        featureEnabled: Bool,
        clickedBundleIdentifier: String?,
        frontmostBundleIdentifier: String?,
        hasUnminimizedWindow: Bool
    ) -> Bool {
        guard featureEnabled, hasUnminimizedWindow,
              let clickedBundleIdentifier,
              let frontmostBundleIdentifier else { return false }
        return clickedBundleIdentifier.caseInsensitiveCompare(frontmostBundleIdentifier) == .orderedSame
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        let featureEnabled = preferences.enabled && preferences.dockClickMinimizesActiveWindow
        guard featureEnabled else {
            candidate = nil
            return
        }

        let location = event.location
        let timestamp = ProcessInfo.processInfo.systemUptime
        switch type {
        case .leftMouseDown:
            let clickedBundleIdentifier = dockApplicationBundleIdentifier(at: location)
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            let hasUnminimizedWindow = frontmostApplication.map {
                hasUnminimizedFocusedWindow(pid: $0.processIdentifier)
            } ?? false
            guard Self.shouldTrackClick(
                featureEnabled: featureEnabled,
                clickedBundleIdentifier: clickedBundleIdentifier,
                frontmostBundleIdentifier: frontmostApplication?.bundleIdentifier,
                hasUnminimizedWindow: hasUnminimizedWindow
            ), let clickedBundleIdentifier, let frontmostApplication else {
                candidate = nil
                return
            }
            candidate = DockClickCandidate(
                pid: frontmostApplication.processIdentifier,
                bundleIdentifier: clickedBundleIdentifier,
                location: location,
                timestamp: timestamp
            )
        case .leftMouseUp:
            guard let candidate else { return }
            self.candidate = nil
            let clickedBundleIdentifier = dockApplicationBundleIdentifier(at: location)
            guard candidate.matches(
                bundleIdentifier: clickedBundleIdentifier,
                location: location,
                timestamp: timestamp
            ) else { return }
            DispatchQueue.main.async { [weak self] in
                _ = self?.minimizeHandler(candidate.pid)
            }
        default:
            break
        }
    }

    fileprivate func reenableEventTap() {
        candidate = nil
        guard let eventTap else {
            installEventTapIfPossible()
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func installEventTapIfPossible() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dockClickEventTapCallback,
            userInfo: context
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Unable to install Dock click event tap")
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        retryTimer?.invalidate()
        retryTimer = nil
        logger.notice("Dock click event tap installed")
    }

    private func dockApplicationBundleIdentifier(at location: CGPoint) -> String? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(location.x),
            Float(location.y),
            &element
        ) == .success, let element else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == Self.dockBundleIdentifier,
              let subrole: String = copyAttribute(kAXSubroleAttribute as CFString, from: element),
              subrole == "AXApplicationDockItem",
              let url: URL = copyAttribute("AXURL" as CFString, from: element) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private func hasUnminimizedFocusedWindow(pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        let focusedWindow: AXUIElement? = copyAttribute(kAXFocusedWindowAttribute as CFString, from: application)
        let mainWindow: AXUIElement? = copyAttribute(kAXMainWindowAttribute as CFString, from: application)
        guard let window = focusedWindow ?? mainWindow else { return false }
        let minimized: Bool = copyAttribute(kAXMinimizedAttribute as CFString, from: window) ?? false
        return !minimized
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }
}
