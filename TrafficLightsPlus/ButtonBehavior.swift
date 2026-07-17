import Foundation

enum ButtonBehavior: String, CaseIterable, Identifiable {
    case closeWindow
    case quitApplication
    case minimizeWindow
    case zoomWindow
    case hideApplication
    case doNothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closeWindow: return I18n.string("behavior.closeWindow")
        case .quitApplication: return I18n.string("behavior.quitApplication")
        case .minimizeWindow: return I18n.string("behavior.minimizeWindow")
        case .zoomWindow: return I18n.string("behavior.zoomWindow")
        case .hideApplication: return I18n.string("behavior.hideApplication")
        case .doNothing: return I18n.string("behavior.doNothing")
        }
    }

    var accessibilityLabel: String { title }

    var nativeWindowAction: WindowAction? {
        switch self {
        case .closeWindow: return .close
        case .minimizeWindow: return .minimize
        case .zoomWindow: return .zoom
        case .quitApplication, .hideApplication, .doNothing: return nil
        }
    }

    static func defaultBehavior(for action: WindowAction) -> ButtonBehavior {
        switch action {
        case .close: return .closeWindow
        case .minimize: return .minimizeWindow
        case .zoom: return .zoomWindow
        }
    }
}
