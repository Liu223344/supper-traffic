import Foundation
import Testing
@testable import TrafficLightsPlus

private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "TrafficLightsPlusTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

@Test func preferenceDefaultsAreUsable() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.enabled)
        #expect(preferences.size == 28)
        #expect(preferences.spacing == 0)
        #expect(preferences.style == .macOS)
        #expect(preferences.hiddenTrafficLightsEnabled)
        #expect(preferences.hiddenTrafficLightRevealMode == .nearest)
        #expect(!preferences.showInFullScreen)
        #expect(preferences.dockClickMinimizesActiveWindow)
        #expect(preferences.closeBehavior == .closeWindow)
        #expect(preferences.minimizeBehavior == .minimizeWindow)
        #expect(preferences.zoomBehavior == .zoomWindow)
        #expect(preferences.quitOnCloseApplications.isEmpty)
    }
}

@Test func recommendedHiddenTrafficLightCopyIsStable() {
    #expect(SettingsView.hiddenTrafficLightsTitle == "隐藏式红绿灯（推荐）")
    #expect(SettingsView.fullScreenOptionTitle == "在全屏窗口中显示（开发中）")
    #expect(SettingsView.dockClickMinimizeTitle == "再次点击 Dock 应用图标时最小化当前窗口")
    #expect(HiddenTrafficLightRevealMode.group.title == "整组")
    #expect(HiddenTrafficLightRevealMode.nearest.title == "单个（推荐）")
}

@Test func fullScreenPreferenceIsDisabledWhileTheFeatureIsInDevelopment() {
    withDefaults { defaults in
        defaults.set(true, forKey: "showInFullScreen")

        let preferences = Preferences(defaults: defaults)

        #expect(!preferences.showInFullScreen)
        #expect(!defaults.bool(forKey: "showInFullScreen"))
    }
}

@Test func preferencesPersist() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.enabled = false
        preferences.size = 42
        preferences.spacing = 12
        preferences.style = .edgeSquares
        preferences.hiddenTrafficLightsEnabled = false
        preferences.hiddenTrafficLightRevealMode = .group
        preferences.dockClickMinimizesActiveWindow = false
        preferences.closeBehavior = .quitApplication
        preferences.minimizeBehavior = .hideApplication
        preferences.zoomBehavior = .doNothing
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )

        let restored = Preferences(defaults: defaults)
        #expect(!restored.enabled)
        #expect(restored.size == 42)
        #expect(restored.spacing == 12)
        #expect(restored.style == .edgeSquares)
        #expect(!restored.hiddenTrafficLightsEnabled)
        #expect(restored.hiddenTrafficLightRevealMode == .group)
        #expect(!restored.showInFullScreen)
        #expect(!restored.dockClickMinimizesActiveWindow)
        #expect(restored.closeBehavior == .quitApplication)
        #expect(restored.minimizeBehavior == .hideApplication)
        #expect(restored.zoomBehavior == .doNothing)
        #expect(restored.quitOnCloseApplications == [
            QuitOnCloseApplication(bundleIdentifier: "com.example.editor", displayName: "Editor")
        ])
    }
}

@Test func quitOnCloseApplicationsCanBeAddedDeduplicatedAndRemoved() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        ))
        #expect(!preferences.addQuitOnCloseApplication(
            bundleIdentifier: "COM.EXAMPLE.EDITOR",
            displayName: "Duplicate"
        ))
        #expect(preferences.quitOnCloseApplications.count == 1)
        #expect(preferences.shouldQuitOnClose(bundleIdentifier: "COM.EXAMPLE.EDITOR"))

        preferences.removeQuitOnCloseApplication(bundleIdentifier: "com.example.editor")
        #expect(preferences.quitOnCloseApplications.isEmpty)
        #expect(!preferences.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
    }
}

@Test func corruptStoredQuitOnCloseApplicationsFallBackToEmpty() {
    withDefaults { defaults in
        defaults.set(Data("not-json".utf8), forKey: "quitOnCloseApplications")
        #expect(Preferences(defaults: defaults).quitOnCloseApplications.isEmpty)
    }
}

@Test func quitOnCloseOnlyOverridesConfiguredCloseBehaviors() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )

        #expect(preferences.effectiveBehavior(
            for: .close,
            bundleIdentifier: "com.example.editor"
        ) == .quitApplication)
        #expect(preferences.effectiveBehavior(
            for: .close,
            bundleIdentifier: "com.example.other"
        ) == .closeWindow)

        preferences.minimizeBehavior = .closeWindow
        #expect(preferences.effectiveBehavior(
            for: .minimize,
            bundleIdentifier: "com.example.editor"
        ) == .quitApplication)

        preferences.zoomBehavior = .zoomWindow
        #expect(preferences.effectiveBehavior(
            for: .zoom,
            bundleIdentifier: "com.example.editor"
        ) == .zoomWindow)
    }
}

@Test func quitOnCloseApplicationsSurviveBehaviorVisibilityAndResetChanges() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )

        preferences.closeBehavior = .doNothing
        preferences.minimizeBehavior = .minimizeWindow
        preferences.zoomBehavior = .zoomWindow
        #expect(!preferences.hasCloseWindowBehavior)
        #expect(preferences.quitOnCloseApplications.count == 1)

        preferences.resetButtonBehaviors()
        #expect(preferences.hasCloseWindowBehavior)
        #expect(preferences.quitOnCloseApplications.count == 1)
    }
}

@Test func corruptStoredRevealModeFallsBackToNearest() {
    withDefaults { defaults in
        defaults.set("unknown", forKey: "hiddenTrafficLightRevealMode")
        #expect(Preferences(defaults: defaults).hiddenTrafficLightRevealMode == .nearest)
    }
}

@Test func corruptStoredBehaviorsFallBackToNativeDefaults() {
    withDefaults { defaults in
        defaults.set("unknown", forKey: "closeButtonBehavior")
        defaults.set("unknown", forKey: "minimizeButtonBehavior")
        defaults.set("unknown", forKey: "zoomButtonBehavior")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.closeBehavior == .closeWindow)
        #expect(preferences.minimizeBehavior == .minimizeWindow)
        #expect(preferences.zoomBehavior == .zoomWindow)
    }
}

@Test func buttonBehaviorNativeActionMappingIsStable() {
    #expect(ButtonBehavior.closeWindow.nativeWindowAction == .close)
    #expect(ButtonBehavior.minimizeWindow.nativeWindowAction == .minimize)
    #expect(ButtonBehavior.zoomWindow.nativeWindowAction == .zoom)
    #expect(ButtonBehavior.quitApplication.nativeWindowAction == nil)
}

@Test func corruptStoredSizeIsClamped() {
    withDefaults { defaults in
        defaults.set(500, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 48)

        defaults.set(-20, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 18)
    }
}

@Test func corruptStoredSpacingIsClamped() {
    withDefaults { defaults in
        defaults.set(500, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == 32)

        defaults.set(-500, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == -8)
    }
}
