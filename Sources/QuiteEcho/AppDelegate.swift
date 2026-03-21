import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig.load()
    private var stats = Stats.load()
    private let recorder = AudioRecorder()
    private let overlay = OverlayPanel()
    private let asr = ASRBridge()
    private let hotkey = HotkeyManager()
    private let updateChecker = UpdateChecker()
    private var statusBar: StatusBarController!
    private var hotkeyRecorderWindow: HotkeyRecorderWindow?

    private let mainWindowController = MainWindowController()
    let viewModel: MainViewModel

    private var recordingStartDate: Date?
    private var isPlaygroundRecording = false
    private var levelTimer: Timer?

    override init() {
        viewModel = MainViewModel(config: config, stats: stats)
        super.init()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        statusBar = StatusBarController(delegate: self)

        viewModel.onModelChange = { [weak self] id in self?.selectModel(id) }
        viewModel.onHFMirrorChange = { [weak self] enabled in self?.setHFMirror(enabled) }
        viewModel.onChangeHotkey = { [weak self] in self?.changeHotkey() }
        viewModel.onSelectHotkeyPreset = { [weak self] preset in self?.applyHotkeyPreset(preset) }
        viewModel.onTogglePlayground = { [weak self] in self?.togglePlaygroundRecording() }
        viewModel.onHotkeyModeChange = { [weak self] mode in self?.setHotkeyMode(mode) }
        viewModel.onLanguageChange = { [weak self] lang in
            guard let self else { return }
            self.config.language = lang
            self.config.save()
            self.viewModel.config = self.config
        }
        viewModel.onCheckUpdate = { [weak self] in
            guard let self else { return }
            self.viewModel.updateCheckStatus = .checking
            self.updateChecker.check(manual: true)
        }
        viewModel.onAutoCheckChange = { [weak self] enabled in self?.setAutoCheckUpdates(enabled) }

        asr.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .downloading where self.isModelCached(self.config.model):
                // Model already cached — suppress downloading status
                break
            default:
                self.viewModel.asrState = state
            }
            switch state {
            case .idle:
                self.statusBar.setStatus("Idle")
                self.statusBar.setLoading(false)
            case .downloading(let pct) where !self.isModelCached(self.config.model):
                self.statusBar.setStatus("Downloading model... \(Int(pct))%")
                self.statusBar.setLoading(true)
            case .downloading:
                break
            case .loading:
                self.statusBar.setStatus("Loading model...")
                self.statusBar.setLoading(true)
            case .ready:
                self.statusBar.setStatus("Ready — \(self.config.modelLabel)")
                self.statusBar.setLoading(false)
            case .error(let msg):
                self.statusBar.setStatus("Error: \(msg)")
                self.statusBar.setLoading(false)
            }
        }

        updateChecker.onUpdateAvailable = { [weak self] release in
            guard let self else { return }
            self.viewModel.availableUpdate = release
            self.viewModel.updateCheckStatus = .idle
            self.statusBar.rebuildMenu()
        }
        updateChecker.onCheckComplete = { [weak self] hasUpdate in
            guard let self, !hasUpdate else { return }
            self.viewModel.updateCheckStatus = .upToDate
            // Reset after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if self.viewModel.updateCheckStatus == .upToDate {
                    self.viewModel.updateCheckStatus = .idle
                }
            }
        }
        if config.autoCheckUpdates {
            updateChecker.startPeriodicChecks()
        }

        PasteService.ensureAccessibility()
        bindHotkey()
        showMainWindow()

        asr.start(model: config.model, useHFMirror: config.useHFMirror)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recorder.isRecording { _ = recorder.stop() }
        hotkey.unregister()
        asr.stop()
        updateChecker.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About QuiteEcho", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit QuiteEcho", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Window

    func showMainWindow() {
        mainWindowController.show(viewModel: viewModel)
    }

    // MARK: - Recording

    /// Hotkey-triggered: paste result to active app.
    func toggleRecording() {
        isPlaygroundRecording = false
        toggleRecordingImpl()
    }

    /// Playground-triggered: append result to playground text.
    func togglePlaygroundRecording() {
        if !recorder.isRecording {
            isPlaygroundRecording = true
        }
        toggleRecordingImpl()
    }

    private func toggleRecordingImpl() {
        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard asr.state == .ready else {
            overlay.showError("Model not ready")
            return
        }
        do {
            try recorder.start()
            recordingStartDate = Date()
            overlay.showRecording()
            statusBar.setRecording(true)
            viewModel.isRecording = true
            startLevelFeed()
        } catch {
            overlay.showError("Mic error")
            NSLog("[Rec] %@", error.localizedDescription)
        }
    }

    private func stopAndTranscribe() {
        let duration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartDate = nil
        let wasPlayground = isPlaygroundRecording

        stopLevelFeed()

        guard let url = recorder.stop() else {
            overlay.hide()
            statusBar.setRecording(false)
            viewModel.isRecording = false
            return
        }
        statusBar.setRecording(false)
        viewModel.isRecording = false
        overlay.showProcessing()

        let lang = config.language.isEmpty ? nil : config.language

        asr.transcribe(audioPath: url.path, language: lang) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.overlay.hide()
                } else {
                    self.overlay.showDone(trimmed)
                    self.stats.recordSession(text: trimmed, durationSeconds: duration)
                    self.viewModel.stats = self.stats

                    if wasPlayground {
                        if !self.viewModel.playgroundText.isEmpty {
                            self.viewModel.playgroundText += "\n"
                        }
                        self.viewModel.playgroundText += trimmed
                    } else {
                        PasteService.paste(trimmed)
                    }
                }
            case .failure(let error):
                self.overlay.showError("Error")
                NSLog("[ASR] %@", error.localizedDescription)
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Audio level → overlay

    private func startLevelFeed() {
        stopLevelFeed()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.overlay.audioLevel = self.recorder.level
        }
    }

    private func stopLevelFeed() {
        levelTimer?.invalidate()
        levelTimer = nil
        overlay.audioLevel = 0
    }

    // MARK: - Model

    private func isModelCached(_ modelId: String) -> Bool {
        let path = AppConfig.modelCacheDir(modelId) + "/snapshots"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return false }
        return contents.contains(where: { !$0.hasPrefix(".") })
    }

    func selectModel(_ modelID: String) {
        guard modelID != config.model else { return }
        config.model = modelID
        // Remember the variant choice for this family
        if let family = AppConfig.modelFamilies.first(where: { $0.hasVariant(modelID) }),
           let variant = family.variant(of: modelID) {
            config.modelVariants[family.name] = variant
        }
        config.save()
        viewModel.config = config
        asr.reload(model: modelID, useHFMirror: config.useHFMirror)
        statusBar.rebuildMenu()
    }

    func setHFMirror(_ use: Bool) {
        config.useHFMirror = use
        config.save()
        viewModel.config = config
    }

    private func setAutoCheckUpdates(_ enabled: Bool) {
        config.autoCheckUpdates = enabled
        config.save()
        viewModel.config = config
        if enabled {
            updateChecker.startPeriodicChecks()
        } else {
            updateChecker.stop()
        }
    }

    // MARK: - Hotkey

    func applyHotkeyPreset(_ preset: HotkeyPreset) {
        config.hotkeyKeyCode = preset.keyCode
        config.hotkeyModifiers = preset.modifiers
        config.hotkeyIsMediaKey = preset.isMediaKey
        config.save()
        viewModel.config = config
        bindHotkey()
        statusBar.rebuildMenu()
    }

    func changeHotkey() {
        // Unregister hotkey so it doesn't fire while recording a new one
        hotkey.unregister()

        let win = HotkeyRecorderWindow { [weak self] keyCode, modifiers, isMediaKey in
            guard let self else { return }
            self.config.hotkeyKeyCode = Int(keyCode)
            self.config.hotkeyModifiers = isMediaKey ? 0 : carbonModifiers(from: modifiers)
            self.config.hotkeyIsMediaKey = isMediaKey
            self.config.save()
            self.viewModel.config = self.config
            self.bindHotkey()
            self.statusBar.rebuildMenu()
            self.hotkeyRecorderWindow = nil
        }
        // Re-register hotkey if the user closes the window without recording
        win.onCancel = { [weak self] in
            self?.bindHotkey()
            self?.hotkeyRecorderWindow = nil
        }
        hotkeyRecorderWindow = win
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setHotkeyMode(_ mode: String) {
        guard mode != config.hotkeyMode else { return }
        config.hotkeyMode = mode
        config.save()
        viewModel.config = config
        bindHotkey()
    }

    private func bindHotkey() {
        let isHold = config.hotkeyMode == "hold"

        let onPressed: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if isHold {
                    if !self.recorder.isRecording { self.toggleRecording() }
                } else {
                    self.toggleRecording()
                }
            }
        }

        let onReleased: (() -> Void)? = isHold ? { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.recorder.isRecording { self.toggleRecording() }
            }
        } : nil

        if config.hotkeyIsMediaKey {
            hotkey.registerMediaKey(
                nxKeyType: config.hotkeyKeyCode,
                onPressed: onPressed,
                onReleased: onReleased
            )
        } else {
            hotkey.register(
                keyCode: UInt32(config.hotkeyKeyCode),
                modifiers: UInt32(config.hotkeyModifiers),
                onPressed: onPressed,
                onReleased: onReleased
            )
        }
    }

    // MARK: - Accessors

    var currentConfig: AppConfig { config }
}

// MARK: - Hotkey Recorder Window

/// Parameters: (keyCode, modifierFlags, isMediaKey)
final class HotkeyRecorderWindow: NSWindow {
    private let onRecord: (UInt16, NSEvent.ModifierFlags, Bool) -> Void
    var onCancel: (() -> Void)?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var mediaMonitor: Any?
    private var pendingModifier: UInt16?
    private var didRecord = false

    init(onRecord: @escaping (UInt16, NSEvent.ModifierFlags, Bool) -> Void) {
        self.onRecord = onRecord
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Record Hotkey"

        let label = NSTextField(labelWithString: "Press any key or combination...")
        label.frame = NSRect(x: 20, y: 55, width: 320, height: 30)
        label.alignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        contentView?.addSubview(label)

        let hint = NSTextField(labelWithString: "Keys, combos, Fn, L/R modifiers, and special function keys.")
        hint.frame = NSRect(x: 20, y: 25, width: 320, height: 30)
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        contentView?.addSubview(hint)
    }

    override func becomeKey() {
        super.becomeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.pendingModifier = nil
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            self?.didRecord = true
            self?.onRecord(event.keyCode, mods, false)
            self?.close()
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode
            guard kModifierKeyCodes.contains(keyCode) else { return event }

            if let flag = modifierFlag(for: keyCode) {
                if event.modifierFlags.contains(flag) {
                    self.pendingModifier = keyCode
                } else if self.pendingModifier == keyCode {
                    self.pendingModifier = nil
                    self.didRecord = true
                    self.onRecord(keyCode, NSEvent.ModifierFlags(), false)
                    self.close()
                }
            }
            return event
        }

        mediaMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let nxKey = Int((event.data1 & 0x7FFF_0000) >> 16)
            let keyState = (event.data1 & 0x0000_FF00) >> 8
            if keyState == 0x0A {
                self?.pendingModifier = nil
                self?.didRecord = true
                self?.onRecord(UInt16(nxKey), NSEvent.ModifierFlags(), true)
                self?.close()
            }
        }
    }

    override func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = mediaMonitor { NSEvent.removeMonitor(m); mediaMonitor = nil }
        pendingModifier = nil
        if !didRecord { onCancel?() }
        super.close()
    }

    deinit { close() }
}
