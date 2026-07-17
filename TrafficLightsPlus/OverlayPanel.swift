import AppKit

enum WindowAction: Int, CaseIterable {
    case close
    case minimize
    case zoom
}

enum ZoomButtonSymbol: Equatable {
    case zoom
    case fullScreen
}

final class OverlayButtonView: NSView {
    let action: WindowAction
    var behavior: ButtonBehavior {
        didSet {
            toolTip = behavior.title
            setAccessibilityLabel(behavior.accessibilityLabel)
            needsDisplay = true
        }
    }
    var zoomButtonSymbol: ZoomButtonSymbol = .fullScreen { didSet { needsDisplay = true } }
    var style: ControlStyle = .macOS { didSet { needsDisplay = true } }
    var controlSize: CGFloat = 28 { didSet { needsDisplay = true } }
    var isControlEnabled = true { didSet { needsDisplay = true } }
    var isWindowActive = false { didSet { needsDisplay = true } }
    var usesMonochromeControls = false { didSet { needsDisplay = true } }
    var isNativeCloseButtonEdited = false { didSet { needsDisplay = true } }
    var isGroupHovered = false { didSet { needsDisplay = true } }
    var actionHandler: ((WindowAction) -> Void)?
    var hoverHandler: ((Bool) -> Void)?

    var isColorVisible: Bool {
        usesMonochromeControls || isWindowActive || isGroupHovered || isHovered || isPressed
    }
    var isPointerHighlightVisible: Bool { isGroupHovered || isHovered || isPressed }

    func setPointerInside(_ inside: Bool) {
        guard inside != isHovered else { return }
        isHovered = inside
        if !inside { isPressed = false }
        needsDisplay = true
    }

    func resetInteractionState() {
        isHovered = false
        isPressed = false
        isGroupHovered = false
        needsDisplay = true
    }

    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?

    init(action: WindowAction) {
        self.action = action
        behavior = ButtonBehavior.defaultBehavior(for: action)
        super.init(frame: .zero)
        toolTip = behavior.title
        setAccessibilityRole(.button)
        setAccessibilityLabel(behavior.accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        setPointerInside(true)
        hoverHandler?(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
        hoverHandler?(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard isControlEnabled else { NSSound.beep(); return }
        isPressed = true
        needsDisplay = true
        // Act on press so zoom/minimize can hide enlarged controls before the
        // window geometry animation starts. Waiting for mouseUp leaves the
        // expanded button visible for the whole click.
        actionHandler?(action)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds
        let actionColor = color(for: action)
        let idleColor = inactiveControlColor()
        let fillColor: NSColor

        if !isControlEnabled {
            fillColor = idleColor
        } else if usesMonochromeControls {
            // Native HUD close buttons use a fixed light gray fill (#DFDFDF).
            let hudGray = Self.hudControlColor
            if isPressed {
                fillColor = hudGray.blended(withFraction: 0.24, of: .black) ?? hudGray
            } else if isHovered {
                fillColor = hudGray.blended(withFraction: 0.10, of: .black) ?? hudGray
            } else {
                fillColor = hudGray
            }
        } else if isPressed {
            fillColor = actionColor.blended(withFraction: 0.24, of: .black) ?? actionColor
        } else if isHovered {
            fillColor = actionColor.blended(withFraction: 0.10, of: .black) ?? actionColor
        } else if isWindowActive || isGroupHovered {
            fillColor = actionColor
        } else {
            fillColor = idleColor
        }

        let path = style == .macOS
            ? NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            : edgeSquarePath(in: rect)
        fillColor.setFill()
        path.fill()

        if style == .macOS {
            NSColor.black.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if style != .macOS || isPointerHighlightVisible {
            drawSymbol(in: rect)
        }
    }

    private func edgeSquarePath(in rect: NSRect) -> NSBezierPath {
        let radius = min(8, rect.height * 0.22)
        let path = NSBezierPath()

        switch action {
        case .close:
            path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
            path.curve(
                to: NSPoint(x: rect.minX + radius, y: rect.minY),
                controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
                controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
            )
        case .minimize, .zoom:
            path.appendRect(rect)
        }
        path.close()
        return path
    }

    private func color(for action: WindowAction) -> NSColor {
        switch action {
        case .close:
            return NSColor(srgbRed: 1.0, green: 0.37255, blue: 0.34118, alpha: 1.0)
        case .minimize:
            return NSColor(srgbRed: 0.99608, green: 0.73725, blue: 0.18039, alpha: 1.0)
        case .zoom:
            return NSColor(srgbRed: 0.15686, green: 0.78431, blue: 0.25098, alpha: 1.0)
        }
    }

    private func inactiveControlColor() -> NSColor {
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            // Sampled from the center of a native inactive traffic-light button.
            return NSColor(srgbRed: 0.37647, green: 0.37647, blue: 0.37255, alpha: 1.0)
        default:
            return NSColor(srgbRed: 0.74510, green: 0.74510, blue: 0.73725, alpha: 1.0)
        }
    }

    static let hudControlColor = NSColor(srgbRed: 0xDF / 255, green: 0xDF / 255, blue: 0xDF / 255, alpha: 1)

    private func drawSymbol(in rect: NSRect) {
        guard let symbolRect = Self.symbolRect(in: rect, style: style) else { return }
        let visualSize = min(rect.width, rect.height)
        let path = NSBezierPath()
        path.lineWidth = Self.symbolLineWidth(
            visualSize: visualSize,
            usesMonochromeControls: usesMonochromeControls
        )
        path.lineCapStyle = .round

        let symbolColor = usesMonochromeControls
            ? Self.monochromeSymbolColor(isEnabled: isControlEnabled)
            : Self.symbolColor(for: color(for: action), isEnabled: isControlEnabled)
        symbolColor.setStroke()

        if Self.shouldDrawEditedIndicator(
            action: action,
            behavior: behavior,
            isEdited: isNativeCloseButtonEdited
        ) {
            let diameter = min(symbolRect.width, symbolRect.height) * 0.56
            let dotRect = NSRect(
                x: symbolRect.midX - diameter / 2,
                y: symbolRect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            symbolColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return
        }

        switch behavior {
        case .closeWindow, .quitApplication:
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.minY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.maxY))
            path.move(to: NSPoint(x: symbolRect.maxX, y: symbolRect.minY))
            path.line(to: NSPoint(x: symbolRect.minX, y: symbolRect.maxY))
        case .minimizeWindow, .hideApplication:
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.midY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.midY))
        case .zoomWindow:
            switch zoomButtonSymbol {
            case .zoom:
                path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.midY))
                path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.midY))
                path.move(to: NSPoint(x: symbolRect.midX, y: symbolRect.minY))
                path.line(to: NSPoint(x: symbolRect.midX, y: symbolRect.maxY))
            case .fullScreen:
                for triangle in Self.zoomSymbolTriangles(in: symbolRect) {
                    path.move(to: triangle[0])
                    path.line(to: triangle[1])
                    path.line(to: triangle[2])
                    path.close()
                }
                symbolColor.setFill()
                path.fill()
                return
            }
        case .doNothing:
            return
        }
        path.stroke()
    }

    static func shouldDrawEditedIndicator(
        action: WindowAction,
        behavior: ButtonBehavior,
        isEdited: Bool
    ) -> Bool {
        action == .close && behavior == .closeWindow && isEdited
    }

    static func symbolColor(for actionColor: NSColor, isEnabled: Bool) -> NSColor {
        let tintedColor = actionColor.blended(withFraction: 0.55, of: .black) ?? actionColor
        return tintedColor.withAlphaComponent(isEnabled ? 0.86 : 0.36)
    }

    static func monochromeSymbolColor(isEnabled: Bool) -> NSColor {
        // Native HUD close glyphs are black on the gray button fill.
        NSColor.black.withAlphaComponent(isEnabled ? 0.92 : 0.36)
    }

    static func symbolLineWidth(visualSize: CGFloat, usesMonochromeControls: Bool) -> CGFloat {
        // HUD close X is a touch heavier than the standard traffic-light glyph.
        let ratio: CGFloat = usesMonochromeControls ? 0.078 : 0.062
        return max(1.15, visualSize * ratio)
    }

    static func zoomSymbolTriangles(in rect: NSRect) -> [[NSPoint]] {
        let separation = min(rect.width, rect.height) * 0.10
        return [
            [
                NSPoint(x: rect.minX, y: rect.minY),
                NSPoint(x: rect.maxX - separation, y: rect.minY),
                NSPoint(x: rect.minX, y: rect.maxY - separation),
            ],
            [
                NSPoint(x: rect.maxX, y: rect.maxY),
                NSPoint(x: rect.minX + separation, y: rect.maxY),
                NSPoint(x: rect.maxX, y: rect.minY + separation),
            ],
        ]
    }

    static func symbolRect(in rect: NSRect, style: ControlStyle) -> NSRect? {
        let visualSize = min(rect.width, rect.height)
        guard visualSize.isFinite, visualSize > 2,
              rect.minX.isFinite, rect.minY.isFinite else { return nil }
        let inset = visualSize * (style == .macOS ? 0.31 : 0.32)
        let symbolRect = rect.insetBy(dx: inset, dy: inset)
        guard !symbolRect.isNull,
              symbolRect.minX.isFinite, symbolRect.minY.isFinite,
              symbolRect.width.isFinite, symbolRect.height.isFinite,
              symbolRect.width > 0, symbolRect.height > 0 else { return nil }
        return symbolRect
    }
}

final class OverlayPanel: NSPanel {
    let overlayView: OverlayButtonView

    init(action: WindowAction) {
        overlayView = OverlayButtonView(action: action)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = overlayView
        overlayView.frame = contentView?.bounds ?? .zero
        overlayView.autoresizingMask = [.width, .height]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}
