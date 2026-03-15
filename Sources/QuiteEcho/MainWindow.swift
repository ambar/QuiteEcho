import AppKit
import AVFoundation
import SwiftUI

// MARK: - Tabs

enum Tab: String, CaseIterable {
    case home = "Home"
    case models = "Models"
    case settings = "Settings"
}

// MARK: - Hotkey Presets

struct HotkeyPreset: Identifiable {
    let id: String
    let label: String
    let icon: String
    let keyCode: Int
    let modifiers: Int
    let isMediaKey: Bool

    static let presets: [HotkeyPreset] = [
        HotkeyPreset(id: "fn",      label: "Fn (Globe)",   icon: "globe",              keyCode: 0x3F, modifiers: 0, isMediaKey: false),
        HotkeyPreset(id: "l_ctrl",  label: "Left Control", icon: "control",            keyCode: 0x3B, modifiers: 0, isMediaKey: false),
        HotkeyPreset(id: "r_ctrl",  label: "Right Control",icon: "control",            keyCode: 0x3E, modifiers: 0, isMediaKey: false),
        HotkeyPreset(id: "l_opt",   label: "Left Option",  icon: "option",             keyCode: 0x3A, modifiers: 0, isMediaKey: false),
        HotkeyPreset(id: "r_opt",   label: "Right Option", icon: "option",             keyCode: 0x3D, modifiers: 0, isMediaKey: false),
        HotkeyPreset(id: "l_cmd",   label: "Left Command", icon: "command",            keyCode: 0x37, modifiers: 0, isMediaKey: false),
        HotkeyPreset(id: "r_cmd",   label: "Right Command",icon: "command",            keyCode: 0x36, modifiers: 0, isMediaKey: false),
        HotkeyPreset(id: "f5_mic",  label: "F5 (Mic)",     icon: "mic.fill",           keyCode: 30,   modifiers: 0, isMediaKey: true),
    ]

    /// Match a preset from current config, or nil if custom.
    static func matching(config: AppConfig) -> HotkeyPreset? {
        presets.first { p in
            p.keyCode == config.hotkeyKeyCode
            && p.modifiers == config.hotkeyModifiers
            && p.isMediaKey == config.hotkeyIsMediaKey
        }
    }
}

// MARK: - View Model

final class MainViewModel: ObservableObject {
    @Published var config: AppConfig
    @Published var asrState: ASRBridge.State = .idle
    @Published var stats: Stats
    @Published var isRecording = false
    @Published var selectedTab: Tab = .home
    @Published var playgroundText: String = ""
    @Published var permAccessibility: Bool = false
    @Published var permMicrophone: Bool = false

    var onModelChange: ((String) -> Void)?
    var onHFMirrorChange: ((Bool) -> Void)?
    var onChangeHotkey: (() -> Void)?                        // custom recorder
    var onSelectHotkeyPreset: ((HotkeyPreset) -> Void)?      // preset selection
    var onTogglePlayground: (() -> Void)?
    var onHotkeyModeChange: ((String) -> Void)?
    var onCheckUpdate: (() -> Void)?
    var onAutoCheckChange: ((Bool) -> Void)?

    enum UpdateCheckStatus: Equatable { case idle, checking, upToDate }
    @Published var availableUpdate: UpdateChecker.Release?
    @Published var updateCheckStatus: UpdateCheckStatus = .idle

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var allPermissionsGranted: Bool {
        permAccessibility && permMicrophone
    }

    init(config: AppConfig, stats: Stats) {
        self.config = config
        self.stats = stats
        refreshPermissions()
    }

    func refreshPermissions() {
        permAccessibility = AXIsProcessTrusted()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: permMicrophone = true
        default:          permMicrophone = false
        }
    }
}

// MARK: - Window Controller

final class MainWindowController {
    private var window: NSWindow?

    func show(viewModel: MainViewModel) {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: MainWindowView(vm: viewModel))

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.contentMinSize = NSSize(width: 640, height: 420)
        w.center()
        w.setFrameAutosaveName("QuiteEchoMain")

        self.window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root

struct MainWindowView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().ignoresSafeArea()

            Group {
                switch vm.selectedTab {
                case .home:     HomeView(vm: vm)
                case .models:   ModelsView(vm: vm)
                case .settings: SettingsView(vm: vm)
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 52)

            ForEach(Tab.allCases, id: \.self) { tab in
                Button(action: { vm.selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: vm.selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(vm.selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(
                            vm.selectedTab == tab
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let update = vm.availableUpdate {
                Button(action: {
                    if let url = URL(string: update.htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                        Text("v\(update.version)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            } else {
                Text("v0.1.1")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 12)
            }

            Spacer().frame(height: 12)
        }
        .padding(.horizontal, 8)
        .frame(width: 140)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Home

private struct HomeView: View {
    @ObservedObject var vm: MainViewModel

    @State private var permTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 52)

            if vm.allPermissionsGranted {
                mainContent
            } else {
                permissionsContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            vm.refreshPermissions()
            startPermPollingIfNeeded()
        }
        .onDisappear { stopPermPolling() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshPermissions()
        }
        .onChange(of: vm.allPermissionsGranted) {
            if vm.allPermissionsGranted { stopPermPolling() }
        }
    }

    private func startPermPollingIfNeeded() {
        guard !vm.allPermissionsGranted else { return }
        stopPermPolling()
        permTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak vm] _ in
            guard let vm else { return }
            DispatchQueue.main.async { vm.refreshPermissions() }
        }
    }

    private func stopPermPolling() {
        permTimer?.invalidate()
        permTimer = nil
    }

    // MARK: Main content (permissions granted)

    private var mainContent: some View {
        VStack(spacing: 0) {
            usageStats
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Spacer()

            statusLine
                .padding(.bottom, 16)
        }
    }

    // MARK: Permissions (not granted)

    private var permissionsContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Permissions Required")
                        .font(.system(size: 20, weight: .bold))
                    Text("QuiteEcho needs the following permissions to work.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 1) {
                    permissionRow(
                        name: "Microphone",
                        description: "Record audio for speech recognition",
                        granted: vm.permMicrophone,
                        action: requestMicrophone
                    )
                    permissionRow(
                        name: "Accessibility",
                        description: "Global hotkey and paste into apps",
                        granted: vm.permAccessibility,
                        action: requestAccessibility
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

                Button(action: { vm.refreshPermissions() }) {
                    Text("Refresh Status")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func permissionRow(
        name: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(granted ? .green : Color(nsColor: .tertiaryLabelColor))
                        .font(.system(size: 15))
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 21)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Text("Grant")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { vm.refreshPermissions() }
        }
    }

    private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        // Poll for a few seconds since macOS doesn't callback
        for delay in [1.0, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                vm.refreshPermissions()
            }
        }
    }

    // MARK: Usage

    private var usageStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Usage")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                stat(vm.stats.formattedTime, "Dictation time")
                stat("\(vm.stats.wordsDictated)", "Words")
                stat("\(vm.stats.sessionsCount)", "Sessions")
                stat(vm.stats.timeSaved, "Time saved")
                stat("\(vm.stats.avgWPM)", "Avg WPM")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Status (bottom center)

    private var statusLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.quaternary)
            Text(vm.config.modelLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        if vm.isRecording { return .red }
        switch vm.asrState {
        case .ready:        return .green
        case .downloading:  return .blue
        case .loading:      return .orange
        case .error:        return .red
        case .idle:         return .gray
        }
    }

    private var statusText: String {
        if vm.isRecording { return "Recording" }
        switch vm.asrState {
        case .ready:              return "Ready"
        case .downloading(let p): return "Downloading \(Int(p))%"
        case .loading:            return "Loading"
        case .error(let m):       return m
        case .idle:               return "Idle"
        }
    }
}

// MARK: - Models

private struct ModelsView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Models")
                    .font(.system(size: 22, weight: .bold))

                Text("Select the ASR model for transcription.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    ForEach(AppConfig.availableModels, id: \.id) { model in
                        modelCard(model)
                    }
                }

                // Mirror source
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download Source")
                        .font(.system(size: 14, weight: .semibold))

                    Picker("", selection: Binding(
                        get: { vm.config.useHFMirror },
                        set: { vm.onHFMirrorChange?($0) }
                    )) {
                        Text("Hugging Face (Official)").tag(false)
                        Text("HF Mirror (hf-mirror.com)").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }
            .padding(32)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func modelCard(_ model: (label: String, id: String)) -> some View {
        ModelCardView(vm: vm, model: model)
    }

}

private struct ModelCardView: View {
    @ObservedObject var vm: MainViewModel
    let model: (label: String, id: String)
    @State private var dirSize: Int64 = 0
    @State private var sizeTimer: Timer?

    private var selected: Bool { vm.config.model == model.id }
    private var isLoading: Bool {
        guard selected else { return false }
        switch vm.asrState {
        case .loading, .downloading: return true
        default: return false
        }
    }

    var body: some View {
        let cachePath = modelCachePath(model.id)
        let subtitle = model.id == "Qwen/Qwen3-ASR-0.6B"
            ? "Faster inference, lower memory usage"
            : "Higher accuracy, requires more memory"

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.label)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selected {
                    modelStateBadge
                }
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture { vm.onModelChange?(model.id) }

            Divider().padding(.horizontal, 12)

            if selected, case .downloading(let pct) = vm.asrState {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("Downloading… \(Int(pct))%")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if dirSize > 0 {
                            Text(formatBytes(dirSize))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    ProgressView(value: pct, total: 100)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if let path = cachePath {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(abbreviatePath(path))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if dirSize > 0 {
                        Text(formatBytes(dirSize))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("Downloaded on first use")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    selected ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        )
        .onAppear { refreshSize(); updateTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: vm.asrState) { updateTimer() }
    }

    // MARK: - State badge

    @ViewBuilder
    private var modelStateBadge: some View {
        switch vm.asrState {
        case .loading, .downloading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Loading")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: .separatorColor).opacity(0.3))
            .clipShape(Capsule())
        case .ready:
            Text("Ready")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
        case .error:
            Text("Error")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
        default:
            Text("Active")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    // MARK: - Size polling

    private func updateTimer() {
        if isLoading {
            guard sizeTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                refreshSize()
            }
            sizeTimer = timer
        } else {
            stopTimer()
            refreshSize()
        }
    }

    private func stopTimer() {
        sizeTimer?.invalidate()
        sizeTimer = nil
    }

    private func refreshSize() {
        let id = model.id
        DispatchQueue.global(qos: .utility).async {
            let size = Self.directorySize(for: id)
            DispatchQueue.main.async { dirSize = size }
        }
    }

    // MARK: - Helpers

    private static func directorySize(for modelId: String) -> Int64 {
        let path = AppConfig.modelCacheDir(modelId)
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let full = (path as NSString).appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: full),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    private func modelCachePath(_ modelId: String) -> String? {
        let path = AppConfig.modelCacheDir(modelId)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                    }
                }

                // Mode
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mode")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 0) {
                            modeButton("Toggle", value: "toggle",
                                       desc: "Press to start, press again to stop")
                            Divider().padding(.horizontal, 12)
                            modeButton("Hold", value: "hold",
                                       desc: "Hold to record, release to stop")
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
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
                                if let update = vm.availableUpdate {
                                    Text("v\(update.version) available")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                } else if vm.updateCheckStatus == .checking {
                                    Text("Checking...")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                } else if vm.updateCheckStatus == .upToDate {
                                    Text("Already the latest version")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Up to date")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let update = vm.availableUpdate {
                                Button(action: {
                                    if let url = URL(string: update.htmlURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Text("Download")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { vm.onCheckUpdate?() }) {
                                    if vm.updateCheckStatus == .checking {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Check Now")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 5)
                                            .background(Color.accentColor.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.updateCheckStatus == .checking)
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

                            Toggle(isOn: Binding(
                                get: { vm.config.autoCheckUpdates },
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
                }

                // Privacy
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your data stays private.")
                            .font(.system(size: 13, weight: .medium))
                        Text("All processing happens on your device.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
            .padding(32)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { vm.refreshPermissions() }
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
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
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
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
