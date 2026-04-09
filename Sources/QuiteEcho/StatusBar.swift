import AppKit
import Sparkle

/// Manages the NSStatusItem (menu bar icon + dropdown menu).
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var delegate: AppDelegate?
    private var statusMenuItem: NSMenuItem!

    init(delegate: AppDelegate) {
        self.delegate = delegate

        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "QuiteEcho")
            img?.isTemplate = true
            button.image = img
        }

        rebuildMenu()
    }

    // MARK: - Public

    func setStatus(_ text: String) {
        statusMenuItem?.title = text
    }

    func setRecording(_ recording: Bool) {
        updateIcon(recording ? "waveform.circle.fill" : "waveform")
    }

    func setLoading(_ loading: Bool) {
        updateIcon(loading ? "ellipsis.circle" : "waveform")
    }

    private func updateIcon(_ name: String) {
        guard let button = statusItem.button else { return }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "QuiteEcho")
        img?.isTemplate = true
        button.image = img
    }

    func rebuildMenu() {
        guard let delegate else { return }
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open QuiteEcho", action: #selector(onOpenWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        statusMenuItem = NSMenuItem(title: "Initializing...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let recItem = NSMenuItem(title: "Toggle Recording", action: #selector(onToggleRecording), keyEquivalent: "")
        recItem.target = self
        menu.addItem(recItem)
        menu.addItem(.separator())

        let modelMenu = NSMenu()
        for family in AppConfig.modelFamilies {
            for variant in family.variants {
                let id = family.modelId(variant)
                let label = "\(family.name) (\(variant))"
                let item = NSMenuItem(title: label, action: #selector(onSelectModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                item.state = (delegate.currentConfig.model == id) ? .on : .off
                modelMenu.addItem(item)
            }
            if family.name != AppConfig.modelFamilies.last?.name {
                modelMenu.addItem(.separator())
            }
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let hkTitle = "Hotkey: \(delegate.currentConfig.hotkeyDisplayString)"
        let hkItem = NSMenuItem(title: hkTitle, action: #selector(onChangeHotkey), keyEquivalent: "")
        hkItem.target = self
        menu.addItem(hkItem)

        menu.addItem(.separator())
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(AppDelegate.checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        updateItem.target = delegate
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(onQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func onOpenWindow() { delegate?.showMainWindow() }
    @objc private func onToggleRecording() { delegate?.toggleRecording() }
    @objc private func onSelectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        delegate?.selectModel(id)
    }
    @objc private func onChangeHotkey() { delegate?.changeHotkey() }
    @objc private func onQuit() { NSApp.terminate(nil) }
}
