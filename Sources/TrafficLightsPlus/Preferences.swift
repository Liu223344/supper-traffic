import Foundation

enum ControlStyle: String, CaseIterable {
    case macOS
    case edgeSquares

    var title: String {
        switch self {
        case .macOS: return "macOS 圆形"
        case .edgeSquares: return "左侧贴边方块"
        }
    }
}

enum HiddenTrafficLightRevealMode: String, CaseIterable {
    case group
    case nearest

    var title: String {
        switch self {
        case .group: return "整组"
        case .nearest: return "单个（推荐）"
        }
    }
}

struct QuitOnCloseApplication: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }
}

final class Preferences: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let size = "controlSize"
        static let spacing = "controlSpacingAdjustment"
        static let style = "controlStyle"
        static let hiddenTrafficLightsEnabled = "hiddenTrafficLightsEnabled"
        static let hiddenTrafficLightRevealMode = "hiddenTrafficLightRevealMode"
        static let showInFullScreen = "showInFullScreen"
        static let closeBehavior = "closeButtonBehavior"
        static let minimizeBehavior = "minimizeButtonBehavior"
        static let zoomBehavior = "zoomButtonBehavior"
        static let quitOnCloseApplications = "quitOnCloseApplications"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published var size: Double {
        didSet { defaults.set(size, forKey: Key.size) }
    }

    @Published var spacing: Double {
        didSet { defaults.set(spacing, forKey: Key.spacing) }
    }

    @Published var style: ControlStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }

    @Published var hiddenTrafficLightsEnabled: Bool {
        didSet { defaults.set(hiddenTrafficLightsEnabled, forKey: Key.hiddenTrafficLightsEnabled) }
    }

    @Published var hiddenTrafficLightRevealMode: HiddenTrafficLightRevealMode {
        didSet { defaults.set(hiddenTrafficLightRevealMode.rawValue, forKey: Key.hiddenTrafficLightRevealMode) }
    }

    @Published private(set) var showInFullScreen: Bool

    @Published var closeBehavior: ButtonBehavior {
        didSet { defaults.set(closeBehavior.rawValue, forKey: Key.closeBehavior) }
    }

    @Published var minimizeBehavior: ButtonBehavior {
        didSet { defaults.set(minimizeBehavior.rawValue, forKey: Key.minimizeBehavior) }
    }

    @Published var zoomBehavior: ButtonBehavior {
        didSet { defaults.set(zoomBehavior.rawValue, forKey: Key.zoomBehavior) }
    }

    @Published private(set) var quitOnCloseApplications: [QuitOnCloseApplication] {
        didSet {
            guard let data = try? JSONEncoder().encode(quitOnCloseApplications) else { return }
            defaults.set(data, forKey: Key.quitOnCloseApplications)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.size: 28.0,
            Key.spacing: 0.0,
            Key.style: ControlStyle.macOS.rawValue,
            Key.hiddenTrafficLightsEnabled: true,
            Key.hiddenTrafficLightRevealMode: HiddenTrafficLightRevealMode.nearest.rawValue,
            Key.showInFullScreen: false,
            Key.closeBehavior: ButtonBehavior.closeWindow.rawValue,
            Key.minimizeBehavior: ButtonBehavior.minimizeWindow.rawValue,
            Key.zoomBehavior: ButtonBehavior.zoomWindow.rawValue
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        size = min(max(defaults.double(forKey: Key.size), ControlLayout.sizeRange.lowerBound), ControlLayout.sizeRange.upperBound)
        spacing = min(
            max(defaults.double(forKey: Key.spacing), ControlLayout.spacingAdjustmentRange.lowerBound),
            ControlLayout.spacingAdjustmentRange.upperBound
        )
        style = ControlStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .macOS
        hiddenTrafficLightsEnabled = defaults.bool(forKey: Key.hiddenTrafficLightsEnabled)
        hiddenTrafficLightRevealMode = HiddenTrafficLightRevealMode(
            rawValue: defaults.string(forKey: Key.hiddenTrafficLightRevealMode) ?? ""
        ) ?? .nearest
        showInFullScreen = false
        defaults.set(false, forKey: Key.showInFullScreen)
        closeBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.closeBehavior) ?? "") ?? .closeWindow
        minimizeBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.minimizeBehavior) ?? "") ?? .minimizeWindow
        zoomBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.zoomBehavior) ?? "") ?? .zoomWindow
        quitOnCloseApplications = Self.loadQuitOnCloseApplications(from: defaults)
    }

    func behavior(for action: WindowAction) -> ButtonBehavior {
        switch action {
        case .close: return closeBehavior
        case .minimize: return minimizeBehavior
        case .zoom: return zoomBehavior
        }
    }

    func resetButtonBehaviors() {
        closeBehavior = .closeWindow
        minimizeBehavior = .minimizeWindow
        zoomBehavior = .zoomWindow
    }

    var hasCloseWindowBehavior: Bool {
        [closeBehavior, minimizeBehavior, zoomBehavior].contains(.closeWindow)
    }

    @discardableResult
    func addQuitOnCloseApplication(bundleIdentifier: String, displayName: String) -> Bool {
        guard !bundleIdentifier.isEmpty,
              !quitOnCloseApplications.contains(where: {
                  $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
              }) else { return false }
        quitOnCloseApplications.append(
            QuitOnCloseApplication(bundleIdentifier: bundleIdentifier, displayName: displayName)
        )
        return true
    }

    func removeQuitOnCloseApplication(bundleIdentifier: String) {
        quitOnCloseApplications.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }

    func shouldQuitOnClose(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return quitOnCloseApplications.contains {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }

    func effectiveBehavior(for action: WindowAction, bundleIdentifier: String?) -> ButtonBehavior {
        let configuredBehavior = behavior(for: action)
        guard configuredBehavior == .closeWindow,
              shouldQuitOnClose(bundleIdentifier: bundleIdentifier) else {
            return configuredBehavior
        }
        return .quitApplication
    }

    private static func loadQuitOnCloseApplications(from defaults: UserDefaults) -> [QuitOnCloseApplication] {
        guard let data = defaults.data(forKey: Key.quitOnCloseApplications),
              let applications = try? JSONDecoder().decode([QuitOnCloseApplication].self, from: data) else {
            return []
        }

        var seenBundleIdentifiers = Set<String>()
        return applications.filter { application in
            let normalizedIdentifier = application.bundleIdentifier.lowercased()
            guard !normalizedIdentifier.isEmpty,
                  seenBundleIdentifiers.insert(normalizedIdentifier).inserted else { return false }
            return true
        }
    }
}
