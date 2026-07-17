import SwiftUI
import ApplicationServices
import AppKit
import UniformTypeIdentifiers
import Combine

struct SettingsView: View {
    static var hiddenTrafficLightsTitle: String { I18n.string("settings.hiddenTrafficLights") }

    @ObservedObject var preferences: Preferences
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var appSelectionError = ""
    @State private var isShowingAppSelectionError = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                preview
                controls
                Divider()
                permissionStatus
            }
            .padding(24)
        }
        .frame(width: 480, height: 740)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
        .alert(I18n.string("settings.unableToAddApplication"), isPresented: $isShowingAppSelectionError) {
            Button(I18n.string("common.ok"), role: .cancel) {}
        } message: {
            Text(appSelectionError)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Traffic Lights Plus")
                    .font(.title2.bold())
                Text(I18n.string("settings.tagline"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)
            Spacer()
            Toggle(I18n.string("settings.enabled"), isOn: $preferences.enabled)
                .toggleStyle(.switch)
                .fixedSize()
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(I18n.string("settings.livePreview"))
                .font(.headline)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 1)
                    }
                previewButtons
                    .padding(.leading, preferences.style == .macOS ? 12 : 0)
                    .padding(.top, preferences.style == .macOS ? 8 : 0)
            }
            .frame(height: max(64, CGFloat(preferences.size) + 16))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var previewButtons: some View {
        let size = CGFloat(preferences.size)
        let spacing: CGFloat = preferences.style == .macOS
            ? max(-size + 4, 8 + CGFloat(preferences.spacing))
            : 0
        return HStack(spacing: spacing) {
            PreviewControl(
                action: .close,
                behavior: preferences.closeBehavior,
                style: preferences.style,
                size: size
            )
                .frame(width: size, height: size)
            PreviewControl(
                action: .minimize,
                behavior: preferences.minimizeBehavior,
                style: preferences.style,
                size: size
            )
                .frame(width: size, height: size)
            PreviewControl(
                action: .zoom,
                behavior: preferences.zoomBehavior,
                style: preferences.style,
                size: size
            )
                .frame(width: size, height: size)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(I18n.string("settings.appearance"))
                    .font(.headline)
                Picker(I18n.string("settings.appearance"), selection: $preferences.style) {
                    ForEach(ControlStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(I18n.string("settings.buttonSize"))
                        .font(.headline)
                    Spacer()
                    Text("\(Int(preferences.size)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button(I18n.string("settings.resetDefault")) { preferences.size = 28 }
                        .buttonStyle(.link)
                }
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Slider(value: $preferences.size, in: ControlLayout.sizeRange, step: 1)
                        .accessibilityLabel(I18n.string("settings.buttonSize"))
                        .accessibilityValue("\(Int(preferences.size)) pt")
                    Image(systemName: "circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            if preferences.style == .macOS {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(I18n.string("settings.buttonSpacing"))
                            .font(.headline)
                        Spacer()
                        Text(spacingDescription)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button(I18n.string("settings.restoreSystemSpacing")) { preferences.spacing = 0 }
                            .buttonStyle(.link)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.and.right")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: $preferences.spacing,
                            in: ControlLayout.spacingAdjustmentRange,
                            step: 1
                        )
                        .accessibilityLabel(I18n.string("settings.buttonSpacing"))
                        .accessibilityValue(spacingDescription)
                        Image(systemName: "arrow.left.and.right")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(Self.hiddenTrafficLightsTitle, isOn: $preferences.hiddenTrafficLightsEnabled)

            if preferences.hiddenTrafficLightsEnabled {
                Picker(I18n.string("settings.revealMethod"), selection: $preferences.hiddenTrafficLightRevealMode) {
                    ForEach(HiddenTrafficLightRevealMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle(I18n.string("settings.showInFullScreen"), isOn: $preferences.showInFullScreen)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(I18n.string("settings.buttonActions"))
                        .font(.headline)
                    Spacer()
                    Button(I18n.string("settings.resetDefault")) { preferences.resetButtonBehaviors() }
                        .buttonStyle(.link)
                }
                behaviorRow(
                    title: I18n.string("settings.redButton"),
                    color: Color(red: 1.0, green: 0.37255, blue: 0.34118),
                    selection: $preferences.closeBehavior
                )
                behaviorRow(
                    title: I18n.string("settings.yellowButton"),
                    color: Color(red: 0.99608, green: 0.73725, blue: 0.18039),
                    selection: $preferences.minimizeBehavior
                )
                behaviorRow(
                    title: I18n.string("settings.greenButton"),
                    color: Color(red: 0.15686, green: 0.78431, blue: 0.25098),
                    selection: $preferences.zoomBehavior
                )
            }

            if preferences.hasCloseWindowBehavior {
                quitOnCloseApplications
            }
        }
    }

    private var quitOnCloseApplications: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(I18n.string("settings.quitOnCloseApplications"))
                    .font(.headline)
                Spacer()
                Button(action: chooseQuitOnCloseApplication) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(I18n.string("settings.addApplication"))
                .accessibilityLabel(I18n.string("settings.addQuitOnCloseApplication"))
            }

            if preferences.quitOnCloseApplications.isEmpty {
                Text(I18n.string("settings.noApplications"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preferences.quitOnCloseApplications) { application in
                    HStack(spacing: 10) {
                        Image(nsImage: icon(for: application))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(application.displayName)
                                .lineLimit(1)
                            Text(application.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            preferences.removeQuitOnCloseApplication(
                                bundleIdentifier: application.bundleIdentifier
                            )
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(I18n.string("settings.removeFromList"))
                        .accessibilityLabel(I18n.string("settings.removeApplication", application.displayName))
                    }
                }
            }
        }
    }

    private var spacingDescription: String {
        let spacing = Int(preferences.spacing)
        if spacing == 0 { return I18n.string("settings.systemSpacing") }
        return spacing > 0 ? "+\(spacing) pt" : "\(spacing) pt"
    }

    private func behaviorRow(
        title: String,
        color: Color,
        selection: Binding<ButtonBehavior>
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(ButtonBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private var permissionStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accessibilityGranted ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(accessibilityGranted
                    ? I18n.string("settings.accessibilityGranted")
                    : I18n.string("settings.accessibilityRequired"))
                    .foregroundStyle(.secondary)
                Spacer()
                if !accessibilityGranted {
                    Button(I18n.string("settings.openAccessibilitySettings")) { requestAccessibility() }
                }
            }
            if !accessibilityGranted {
                Text(I18n.string("settings.accessibilityInstructions"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func chooseQuitOnCloseApplication() {
        let panel = NSOpenPanel()
        panel.title = I18n.string("settings.chooseQuitOnCloseApplication")
        panel.prompt = I18n.string("settings.add")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            appSelectionError = I18n.string("settings.missingBundleIdentifier")
            isShowingAppSelectionError = true
            return
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        _ = preferences.addQuitOnCloseApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }

    private func icon(for application: QuitOnCloseApplication) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: application.bundleIdentifier
        ) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: application.displayName)
            ?? NSImage(size: NSSize(width: 28, height: 28))
    }
}

private struct PreviewControl: NSViewRepresentable {
    let action: WindowAction
    let behavior: ButtonBehavior
    let style: ControlStyle
    let size: CGFloat

    func makeNSView(context: Context) -> OverlayButtonView {
        OverlayButtonView(action: action)
    }

    func updateNSView(_ view: OverlayButtonView, context: Context) {
        view.style = style
        view.controlSize = size
        view.behavior = behavior
        view.isWindowActive = true
        view.needsDisplay = true
    }
}
