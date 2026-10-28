import AppKit
import Foundation
import PowerModeCore

@MainActor
protocol StatusMenuControllerDelegate: AnyObject {
    var currentMode: PowerMode { get }
    var currentRuleSummary: RuleSummary { get }
    var isOpenAtLoginEnabled: Bool { get }
    var isThermalAutoCooldownEnabled: Bool { get }
    var thermalCooldownStatusLine: String? { get }
    var statusError: String? { get }

    func selectMode(_ mode: PowerMode)
    func toggleOpenAtLogin()
    func toggleThermalAutoCooldown()
    func reapplyPolicy()
    func quit()
}

@MainActor
final class StatusMenuController: NSObject {
    private weak var delegate: StatusMenuControllerDelegate?
    private var statusItem: NSStatusItem?

    init(delegate: StatusMenuControllerDelegate) {
        self.delegate = delegate
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        updateStatusButton()
        update()
    }

    func update() {
        updateStatusButton()
        statusItem?.menu = makeMenu()
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button, let delegate else {
            return
        }

        button.image = NSImage(
            systemSymbolName: delegate.currentMode.symbolName,
            accessibilityDescription: delegate.currentMode.title
        )
        button.image?.isTemplate = true
        button.toolTip = delegate.thermalCooldownStatusLine ?? delegate.currentMode.title
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        guard let delegate else {
            return menu
        }

        if let statusLine = delegate.thermalCooldownStatusLine {
            let cooldownItem = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
            cooldownItem.isEnabled = false
            menu.addItem(cooldownItem)
            menu.addItem(.separator())
        }

        for mode in PowerMode.allCases {
            let item = NSMenuItem(
                title: "\(mode.title)    \(mode.coreFeatureSummary)",
                action: #selector(modeItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == delegate.currentMode ? .on : .off
            item.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        addRuleSummaryItems(to: menu, summary: delegate.currentRuleSummary)

        if let statusError = delegate.statusError {
            menu.addItem(.separator())
            let errorItem = NSMenuItem(title: statusError, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())
        let loginItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(openAtLoginSelected(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = delegate.isOpenAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        let thermalItem = NSMenuItem(
            title: "Thermal Auto Cool-Down",
            action: #selector(thermalAutoCooldownSelected(_:)),
            keyEquivalent: ""
        )
        thermalItem.target = self
        thermalItem.state = delegate.isThermalAutoCooldownEnabled ? .on : .off
        menu.addItem(thermalItem)

        let reapplyItem = NSMenuItem(
            title: "Apply System Settings (Admin Required)",
            action: #selector(reapplySelected(_:)),
            keyEquivalent: ""
        )
        reapplyItem.target = self
        menu.addItem(reapplyItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitSelected(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func addRuleSummaryItems(to menu: NSMenu, summary: RuleSummary) {
        let lidItem = NSMenuItem(title: summary.lidLine, action: nil, keyEquivalent: "")
        lidItem.isEnabled = false
        menu.addItem(lidItem)

        let unpluggedItem = NSMenuItem(title: summary.unpluggedLine, action: nil, keyEquivalent: "")
        unpluggedItem.isEnabled = false
        menu.addItem(unpluggedItem)
    }

    @objc private func modeItemSelected(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = PowerMode(rawValue: rawValue)
        else {
            return
        }

        delegate?.selectMode(mode)
    }

    @objc private func openAtLoginSelected(_ sender: NSMenuItem) {
        delegate?.toggleOpenAtLogin()
    }

    @objc private func thermalAutoCooldownSelected(_ sender: NSMenuItem) {
        delegate?.toggleThermalAutoCooldown()
    }

    @objc private func reapplySelected(_ sender: NSMenuItem) {
        delegate?.reapplyPolicy()
    }

    @objc private func quitSelected(_ sender: NSMenuItem) {
        delegate?.quit()
    }
}
