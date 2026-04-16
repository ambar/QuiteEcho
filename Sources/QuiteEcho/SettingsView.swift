import AppKit
import AVFoundation
import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold))

                    // Hotkey
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hotkey")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        hotkeyPicker

                        VStack(spacing: 0) {
                            modeButton("Toggle", value: "toggle",
                                       desc: "Press to start, press again to stop")
                            Divider().padding(.horizontal, 12)
                            modeButton("Hold", value: "hold",
                                       desc: "Hold to record, release to stop")
                        }
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Speech Language — picker for families that route a hint
                // into the decoder, read-only note for families that detect
                // the language from the audio themselves.
                if let family = vm.config.modelFamily,
                   family.supportsLanguage || family.autoDetectsLanguage {
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Speech Language")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            HStack {
                                Text("Language for speech recognition")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if family.supportsLanguage {
                                    Picker("", selection: Binding(
                                        get: { vm.config.language },
                                        set: { vm.onLanguageChange?($0) }
                                    )) {
                                        if family.supportsAutoLanguage {
                                            Text("Auto").tag("")
                                        }
                                        ForEach(family.supportedLanguages, id: \.self) { lang in
                                            Text(lang).tag(lang)
                                        }
                                    }
                                    .labelsHidden()
                                    .fixedSize()
                                } else {
                                    Text("Auto (detected from audio)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Output
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Output")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Copy to clipboard")
                                    .font(.system(size: 13))
                                Text("Keep transcribed text on clipboard for re-pasting")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { vm.config.copyToClipboard },
                                set: { vm.onCopyToClipboardChange?($0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }
                    }
                }

                // Permissions
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Permissions")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        settingsPermRow(
                            icon: "mic.fill",
                            name: "Microphone",
                            granted: vm.permMicrophone,
                            action: grantMicrophone
                        )
                        settingsPermRow(
                            icon: "hand.raised.fill",
                            name: "Accessibility",
                            granted: vm.permAccessibility,
                            action: grantAccessibility
                        )
                    }
                }

                // Updates
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updates")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current version: v\(vm.currentVersion)")
                                    .font(.system(size: 13))
                                if case .readyToInstall(let version) = vm.updateState {
                                    Text("v\(version) ready to install")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.green)
                                } else if let version = vm.updateState.version {
                                    Text("v\(version) available")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            if case .readyToInstall = vm.updateState {
                                Button(action: { vm.onUpdateInstallAndRelaunch?() }) {
                                    Text("Install & Relaunch")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.green)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            } else if vm.updateState.version != nil {
                                Button(action: { vm.onUpdateInstall?() }) {
                                    Text("Install Update")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { vm.checkForUpdates?(); vm.showUpdatePopover = true }) {
                                    Text("Check for Updates")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        HStack {
                            Button(action: {
                                if let url = URL(string: "https://github.com/ambar/QuiteEcho/releases") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 2) {
                                    Text("Release Notes")
                                    Image(systemName: "arrow.up.right")
                                        .imageScale(.small)
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            if vm.optionKeyDown {
                                Toggle(isOn: Binding(
                                    get: { vm.config.betaUpdates },
                                    set: { vm.onBetaUpdatesChange?($0) }
                                )) {
                                    Text("Opt-in beta")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .transition(.opacity)
                            }

                            Toggle(isOn: Binding(
                                get: { vm.automaticallyChecksForUpdates },
                                set: { vm.onAutoCheckChange?($0) }
                            )) {
                                Text("Auto check")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                    }
                    .animation(nil, value: vm.optionKeyDown)
                }

                // Privacy
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("All processing happens on your device.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .onAppear { vm.refreshPermissions() }
        .onModifierKeys(.option) { pressed in
            vm.optionKeyDown = pressed
        }
    }

    private func settingsPermRow(icon: String, name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 13))
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            } else {
                Button(action: action) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func grantMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { vm.refreshPermissions() }
        }
    }

    private func grantAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        for delay in [1.0, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                vm.refreshPermissions()
            }
        }
    }

    private var hotkeyPicker: some View {
        let current = HotkeyPreset.matching(config: vm.config)
        let isCustom = current == nil

        return Menu {
            ForEach(HotkeyPreset.presets) { preset in
                Button(action: { vm.onSelectHotkeyPreset?(preset) }) {
                    HStack {
                        Image(systemName: preset.icon)
                        Text(preset.label)
                    }
                }
            }
            Divider()
            Button(action: { vm.onChangeHotkey?() }) {
                HStack {
                    Image(systemName: "keyboard")
                    Text("Custom...")
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let p = current {
                    Image(systemName: p.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Text(isCustom ? vm.config.hotkeyDisplayString : current!.label)
                    .font(.system(size: 14, weight: .medium))

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
    }

    private func modeButton(_ label: String, value: String, desc: String) -> some View {
        let selected = vm.config.hotkeyMode == value
        return HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { vm.onHotkeyModeChange?(value) }
    }

    private func card<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

// MARK: - Modifier Key Monitor

private struct ModifierKeyModifier: ViewModifier {
    let flags: NSEvent.ModifierFlags
    let onChange: (Bool) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let existing = monitor { NSEvent.removeMonitor(existing) }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    onChange(event.modifierFlags.contains(flags))
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                onChange(false)
            }
    }
}

extension View {
    func onModifierKeys(_ flags: NSEvent.ModifierFlags, onChange: @escaping (Bool) -> Void) -> some View {
        modifier(ModifierKeyModifier(flags: flags, onChange: onChange))
    }
}
