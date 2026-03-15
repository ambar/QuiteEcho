import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig.load()
    private var stats = Stats.load()
    private let recorder = AudioRecorder()
    private let overlay = OverlayPanel()
    private let asr = ASRBridge()
    private let hotkey = HotkeyManager()
    private let bootstrap = BootstrapManager()
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
        statusBar = StatusBarController(delegate: self)

        viewModel.onModelChange = { [weak self] id in self?.selectModel(id) }
        viewModel.onChangeHotkey = { [weak self] in self?.changeHotkey() }
        viewModel.onSelectHotkeyPreset = { [weak self] preset in self?.applyHotkeyPreset(preset) }
        viewModel.onTogglePlayground = { [weak self] in self?.togglePlaygroundRecording() }
        viewModel.onHotkeyModeChange = { [weak self] mode in self?.setHotkeyMode(mode) }

        asr.onStateChange = { [weak self] state in
            guard let self else { return }
            self.viewModel.asrState = state
            switch state {
            case .idle:
                self.statusBar.setStatus("Idle")
                self.statusBar.setLoading(false)
            case .downloading(let pct):
                self.statusBar.setStatus("Downloading model... \(Int(pct))%")
                self.statusBar.setLoading(true)
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

        bootstrap.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .creatingVenv:
                self.statusBar.setStatus("Creating Python environment...")
                self.statusBar.setLoading(true)
            case .installingDeps:
                self.statusBar.setStatus("Installing dependencies...")
                self.statusBar.setLoading(true)
            case .error(let msg):
                self.statusBar.setStatus("Setup error: \(msg)")
                self.statusBar.setLoading(false)
            default: break
            }
        }

        PasteService.ensureAccessibility()
        bindHotkey()
        showMainWindow()

        // Bootstrap venv, then start ASR worker
        bootstrap.ensureReady { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.asr.start(model: self.config.model, pythonPath: self.bootstrap.pythonPath)
            case .failure(let error):
                NSLog("[Bootstrap] %@", error.localizedDescription)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recorder.isRecording { _ = recorder.stop() }
        hotkey.unregister()
        asr.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
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

    func selectModel(_ modelID: String) {
        guard modelID != config.model else { return }
        config.model = modelID
        config.save()
        viewModel.config = config
        asr.reload(model: modelID)
        statusBar.rebuildMenu()
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
}
