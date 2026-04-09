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
    var onLanguageChange: ((String) -> Void)?
    var checkForUpdates: (() -> Void)?
    var onAutoCheckChange: ((Bool) -> Void)?
    var onBetaUpdatesChange: ((Bool) -> Void)?
    var onCopyToClipboardChange: ((Bool) -> Void)?
    @Published var automaticallyChecksForUpdates = true
    @Published var optionKeyDown = false
    @Published var updateState: UpdateState = .idle
    @Published var showUpdatePopover = false
    var onUpdateInstall: (() -> Void)?
    var onUpdateDismiss: (() -> Void)?
    var onUpdateSkip: (() -> Void)?
    var onUpdateInstallAndRelaunch: (() -> Void)?

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
        w.titlebarSeparatorStyle = .none
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
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 0.5)
                .ignoresSafeArea()

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
            Spacer().frame(height: 38)

            ForEach(Tab.allCases, id: \.self) { tab in
                Button(action: { vm.selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: vm.selectedTab == tab ? .semibold : .regular))
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
                .focusEffectDisabled()
            }

            Spacer()

            updateBadge
                .padding(.horizontal, 12)

            Spacer().frame(height: 12)
        }
        .padding(.horizontal, 8)
        .frame(width: 140)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var updateBadge: some View {
        Group {
            switch vm.updateState {
            case .idle, .notFound:
                Text("v\(vm.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            case .checking:
                updateChip(color: .secondary) {
                    Text("Checking…")
                }
            case .available(let version, _):
                updateChip(color: .orange) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("v\(version)").fontWeight(.medium)
                }
            case .downloading(_, let progress):
                updateChip(color: .orange) {
                    ProgressView().controlSize(.mini)
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                }
            case .extracting:
                updateChip(color: .orange) {
                    ProgressView().controlSize(.mini)
                    Text("Preparing…")
                }
            case .readyToInstall(let version):
                Button(action: { vm.onUpdateInstallAndRelaunch?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("Install v\(version)").fontWeight(.medium)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
            case .installing:
                updateChip(color: .orange, interactive: false) {
                    ProgressView().controlSize(.mini)
                    Text("Installing…")
                }
            case .error:
                updateChip(color: .red) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("Error")
                }
            }
        }
        .popover(isPresented: $vm.showUpdatePopover, arrowEdge: .top) {
            UpdatePopoverView(vm: vm)
        }
    }

    private func updateChip<C: View>(color: Color, interactive: Bool = true, @ViewBuilder content: () -> C) -> some View {
        let label = HStack(spacing: 4) { content() }
            .font(.system(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())

        return Group {
            if interactive {
                Button(action: { vm.showUpdatePopover = true }) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }
}
