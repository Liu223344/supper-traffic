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
        case .closeWindow: return "关闭窗口"
        case .quitApplication: return "退出当前应用"
        case .minimizeWindow: return "最小化窗口"
        case .zoomWindow: return "缩放窗口"
        case .hideApplication: return "隐藏当前应用"
        case .doNothing: return "无操作"
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
