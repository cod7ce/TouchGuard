import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var flashTimer: Timer?

    private let guardObject = InputGuard.shared
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // A windowless agent app is otherwise eligible for automatic termination,
        // and LaunchServices reaps it moments after launch.
        ProcessInfo.processInfo.disableAutomaticTermination("Keeps the event tap installed")
        ProcessInfo.processInfo.disableSuddenTermination()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        guardObject.onBlock = { [weak self] in self?.flash() }

        if !guardObject.start() {
            requestAccessibility()
        }
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guardObject.stop()
    }

    // MARK: - Permission

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { return }
            if self.guardObject.start() {
                timer.invalidate()
                self.permissionTimer = nil
                self.updateIcon()
            }
        }
    }

    // MARK: - Status item

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let name: String
        if !guardObject.isRunning {
            name = "exclamationmark.triangle"
        } else if settings.enabled {
            name = "hand.raised"
        } else {
            name = "hand.raised.slash"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "TouchGuard")
        image?.isTemplate = true
        button.image = image
    }

    /// Brief visual confirmation that something was actually swallowed.
    private func flash() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "TouchGuard")
        image?.isTemplate = true
        button.image = image
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.updateIcon()
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !guardObject.isRunning {
            menu.addItem(disabledItem("未获得辅助功能权限"))
            menu.addItem(withTitle: "打开系统设置授权…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
                .target = self
            menu.addItem(.separator())
        } else {
            let state = settings.enabled ? "运行中" : "已暂停"
            menu.addItem(disabledItem("TouchGuard · \(state)"))
            menu.addItem(disabledItem("已拦截 \(guardObject.blockedClicks) 次点击 / \(guardObject.blockedOther) 次滑动"))
            menu.addItem(.separator())
        }

        addToggle(menu, title: "启用拦截", isOn: settings.enabled, action: #selector(toggleEnabled), key: "e")

        let delayMenu = NSMenu()
        for value in [200, 300, 500, 750, 1000] {
            let item = NSMenuItem(title: "\(value) 毫秒", action: #selector(setDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = settings.delayMS == value ? .on : .off
            delayMenu.addItem(item)
        }
        let delayItem = NSMenuItem(title: "停用时长", action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        let blockMenu = NSMenu()
        addToggle(blockMenu, title: "点击 / 轻点", isOn: settings.blockClicks, action: #selector(toggleClicks))
        addToggle(blockMenu, title: "指针移动", isOn: settings.blockMovement, action: #selector(toggleMovement))
        addToggle(blockMenu, title: "两指滚动", isOn: settings.blockScroll, action: #selector(toggleScroll))
        let blockItem = NSMenuItem(title: "拦截内容", action: nil, keyEquivalent: "")
        blockItem.submenu = blockMenu
        menu.addItem(blockItem)

        menu.addItem(.separator())
        addToggle(menu, title: "按住修饰键时放行", isOn: settings.allowModifierChords, action: #selector(toggleModifierChords))
        addToggle(menu, title: "只拦截触控板（严格）", isOn: settings.strictTrackpadOnly, action: #selector(toggleStrict))
        addToggle(menu, title: "开机自动启动", isOn: launchAtLoginEnabled, action: #selector(toggleLaunchAtLogin))

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 TouchGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @discardableResult
    private func addToggle(_ menu: NSMenu, title: String, isOn: Bool, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = isOn ? .on : .off
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        updateIcon()
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Int { settings.delayMS = value }
    }

    @objc private func toggleClicks() { settings.blockClicks.toggle() }
    @objc private func toggleMovement() { settings.blockMovement.toggle() }
    @objc private func toggleScroll() { settings.blockScroll.toggle() }
    @objc private func toggleModifierChords() { settings.allowModifierChords.toggle() }
    @objc private func toggleStrict() { settings.strictTrackpadOnly.toggle() }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机启动项"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
