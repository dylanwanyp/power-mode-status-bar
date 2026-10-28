import AppKit
import Foundation
import PowerModeCore

@MainActor
final class AppCoordinator: NSObject {
    private let preferences = AppPreferences()
    private let stateProvider = SystemStateProvider()
    private let assertionManager = PowerAssertionManager()
    private let commandRunner = PrivilegedCommandRunner()
    private let loginItemManager = LoginItemManager()
    private let isDryRun = ProcessInfo.processInfo.environment["POWER_MODE_DRY_RUN"] == "1"
    private lazy var menuController = StatusMenuController(delegate: self)

    private var monitorTimer: Timer?
    private var thermalCheckTimer: Timer?
    private var cooldownRestoreTimer: Timer?
    private var thermalStateObserver: NSObjectProtocol?
    private var handledLidClosureMode: PowerMode?
    private var cooldownSession: ThermalCooldownSession?
    /// Wall-clock deadline for the next periodic thermal check. `Timer` does not advance during
    /// system sleep, so the one-second monitor also honors this date after the Mac wakes.
    private var nextThermalCheckAt = Date.distantFuture
    private(set) var selectedMode: PowerMode {
        didSet {
            preferences.selectedMode = selectedMode
        }
    }

    private(set) var openAtLoginEnabled: Bool {
        didSet {
            preferences.openAtLoginEnabled = openAtLoginEnabled
        }
    }

    private(set) var thermalAutoCooldownEnabled: Bool {
        didSet {
            preferences.thermalAutoCooldownEnabled = thermalAutoCooldownEnabled
        }
    }

    private(set) var lastError: String? {
        didSet {
            menuController.update()
        }
    }

    override init() {
        selectedMode = preferences.selectedMode
        openAtLoginEnabled = preferences.openAtLoginEnabled
        thermalAutoCooldownEnabled = preferences.thermalAutoCooldownEnabled
        super.init()
    }

    func start() {
        configureDefaultLoginItem()
        menuController.install()
        applySelectedMode(reason: "launch", applySystemSettings: false)
        startMonitoring()
        startThermalMonitoring()
    }

    private func configureDefaultLoginItem() {
        guard openAtLoginEnabled else {
            return
        }

        guard !isDryRun else {
            return
        }

        do {
            try loginItemManager.setEnabled(true)
        } catch {
            lastError = "Open at Login was not enabled: \(error.localizedDescription)"
        }
    }

    private func startMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(monitorTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(monitorTimer!, forMode: .common)
    }

    private func startThermalMonitoring() {
        if thermalStateObserver == nil {
            thermalStateObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.evaluateThermalPressure()
                }
            }
        }

        scheduleNextThermalCheck()
        evaluateThermalPressure()
    }

    private func scheduleNextThermalCheck() {
        thermalCheckTimer?.invalidate()
        let fireAt = Date().addingTimeInterval(ThermalCooldownPolicy.checkInterval)
        nextThermalCheckAt = fireAt
        let timer = Timer(
            fireAt: fireAt,
            interval: 0,
            target: self,
            selector: #selector(thermalCheckTimerFired(_:)),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        thermalCheckTimer = timer
    }

    @objc private func monitorTimerFired(_ timer: Timer) {
        if Date() >= nextThermalCheckAt {
            performScheduledThermalCheck()
        }
        applyRuntimePolicy()
    }

    @objc private func thermalCheckTimerFired(_ timer: Timer) {
        performScheduledThermalCheck()
    }

    private func performScheduledThermalCheck() {
        scheduleNextThermalCheck()
        evaluateThermalPressure()
    }

    @objc private func cooldownRestoreTimerFired(_ timer: Timer) {
        guard let session = cooldownSession else {
            return
        }
        finishThermalCooldown(session: session)
    }

    private func evaluateThermalPressure() {
        let pressure = ThermalPressureLevel(processThermalState: ProcessInfo.processInfo.thermalState)
        guard ThermalCooldownPolicy.shouldBeginCooldown(
            enabled: thermalAutoCooldownEnabled,
            pressure: pressure,
            mode: selectedMode,
            cooldownActive: cooldownSession != nil
        ) else {
            return
        }

        beginThermalCooldown(preferredMode: selectedMode)
    }

    private func beginThermalCooldown(preferredMode: PowerMode) {
        guard !isDryRun else {
            print("[PowerModeStatusBar] dry-run skipped thermal cool-down for \(preferredMode.title)")
            return
        }

        let session = ThermalCooldownSession(preferredMode: preferredMode, startedAt: Date())
        cooldownSession = session
        scheduleCooldownRestore(at: session.restoreAt)
        assertionManager.apply(ThermalCooldownPolicy.releasedAssertions)
        menuController.update()
        print("[PowerModeStatusBar] thermal cool-down started; restoring \(preferredMode.title) at \(session.restoreAt)")

        // Give IOPM a moment to drop the assertions before requesting sleep.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.cooldownSession != nil else {
                return
            }
            SystemSleeper.sleepNow()
        }
    }

    private func scheduleCooldownRestore(at date: Date) {
        cooldownRestoreTimer?.invalidate()
        let timer = Timer(
            fireAt: date,
            interval: 0,
            target: self,
            selector: #selector(cooldownRestoreTimerFired(_:)),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        cooldownRestoreTimer = timer
    }

    private func finishThermalCooldown(session: ThermalCooldownSession) {
        guard cooldownSession == session else {
            return
        }

        let shouldRestore = ThermalCooldownPolicy.shouldRestorePreferredMode(
            enabled: thermalAutoCooldownEnabled,
            cooldownActive: true,
            userDidOverride: false
        )
        clearThermalCooldownSchedule()

        if shouldRestore && selectedMode != session.preferredMode {
            selectedMode = session.preferredMode
        }
        // Disabled cool-down still reapplies the selected mode so assertions are not left released.
        // User override never reaches this method: choosing a mode clears the session first.
        applySelectedMode(
            reason: shouldRestore ? "thermal-restore" : "thermal-cooldown-ended",
            applySystemSettings: false
        )
        // An overdue periodic check must not start another cool-down in the same wake.
        // The next 30-minute check, or a later thermal-state change, can start one.
        if Date() >= nextThermalCheckAt {
            scheduleNextThermalCheck()
        }
    }

    /// Manual mode selection wins. Clears the pending restore without applying the remembered mode.
    private func cancelThermalCooldownForUserSelection() -> Bool {
        guard cooldownSession != nil else {
            return false
        }
        clearThermalCooldownSchedule()
        return true
    }

    private func clearThermalCooldownSchedule() {
        cooldownRestoreTimer?.invalidate()
        cooldownRestoreTimer = nil
        cooldownSession = nil
    }

    private func applySelectedMode(reason: String, applySystemSettings: Bool) {
        menuController.update()
        applyRuntimePolicy()

        guard applySystemSettings else {
            return
        }

        let mode = selectedMode
        let plan = SystemCommandPlanner.plan(for: mode)

        let result = commandRunner.runPrivileged(plan.privilegedCommands)
        switch result {
        case .success:
            lastError = nil
        case .failure(let error):
            lastError = "Failed to apply system settings: \(error.localizedDescription)"
        }
        applyRuntimePolicy()
    }

    private func applyRuntimePolicy() {
        if let session = cooldownSession {
            // `Date` keeps moving while the Mac sleeps, so this restores the preferred mode
            // on wake once 15 minutes have passed even if the restore timer was suspended.
            if session.isDue(at: Date()) {
                finishThermalCooldown(session: session)
                return
            }
            assertionManager.apply(ThermalCooldownPolicy.releasedAssertions)
            return
        }

        let snapshot = stateProvider.snapshot()
        let runtimePolicy = PowerPolicy.runtimePolicy(for: selectedMode, snapshot: snapshot)
        assertionManager.apply(runtimePolicy)

        if snapshot.lidState == .open {
            handledLidClosureMode = nil
        }

        let shouldHandleLidClosure = runtimePolicy.lockOnCurrentLidClosure || runtimePolicy.sleepOnCurrentLidClosure
        if shouldHandleLidClosure && handledLidClosureMode != selectedMode {
            handledLidClosureMode = selectedMode
            performLidClosureAction(runtimePolicy)
        }
    }

    private func performLidClosureAction(_ runtimePolicy: RuntimePowerPolicy) {
        guard !isDryRun else {
            return
        }

        if runtimePolicy.lockOnCurrentLidClosure {
            ScreenLocker.lock()
        }

        guard runtimePolicy.sleepOnCurrentLidClosure else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else {
                return
            }

            let snapshot = self.stateProvider.snapshot()
            guard self.selectedMode == .standby, snapshot.lidState == .closed else {
                return
            }

            SystemSleeper.sleepNow()
        }
    }

    private var thermalCooldownStatusText: String? {
        guard let cooldownSession else {
            return nil
        }
        let restoreTime = cooldownSession.restoreAt.formatted(date: .omitted, time: .shortened)
        return ThermalCooldownPolicy.statusLine(
            modeTitle: cooldownSession.preferredMode.title,
            restoreTime: restoreTime
        )
    }
}

extension AppCoordinator: StatusMenuControllerDelegate {
    var currentMode: PowerMode {
        selectedMode
    }

    var currentRuleSummary: RuleSummary {
        selectedMode.ruleSummary
    }

    var isOpenAtLoginEnabled: Bool {
        openAtLoginEnabled
    }

    var isThermalAutoCooldownEnabled: Bool {
        thermalAutoCooldownEnabled
    }

    var thermalCooldownStatusLine: String? {
        thermalCooldownStatusText
    }

    var statusError: String? {
        lastError
    }

    func selectMode(_ mode: PowerMode) {
        let cancelledCooldown = cancelThermalCooldownForUserSelection()
        guard selectedMode != mode || cancelledCooldown else {
            return
        }
        if selectedMode != mode {
            selectedMode = mode
        }
        applySelectedMode(reason: "menu", applySystemSettings: false)
    }

    func toggleOpenAtLogin() {
        let nextValue = !openAtLoginEnabled
        guard !isDryRun else {
            openAtLoginEnabled = nextValue
            lastError = nil
            menuController.update()
            return
        }

        do {
            try loginItemManager.setEnabled(nextValue)
            openAtLoginEnabled = nextValue
            lastError = nil
        } catch {
            lastError = "Failed to toggle Open at Login: \(error.localizedDescription)"
        }
        menuController.update()
    }

    func toggleThermalAutoCooldown() {
        thermalAutoCooldownEnabled.toggle()
        if thermalAutoCooldownEnabled {
            evaluateThermalPressure()
        } else if let session = cooldownSession {
            clearThermalCooldownSchedule()
            if selectedMode != session.preferredMode {
                selectedMode = session.preferredMode
            }
            applySelectedMode(reason: "thermal-disabled", applySystemSettings: false)
        }
        menuController.update()
    }

    func reapplyPolicy() {
        applySelectedMode(reason: "manual", applySystemSettings: true)
    }

    func quit() {
        monitorTimer?.invalidate()
        thermalCheckTimer?.invalidate()
        cooldownRestoreTimer?.invalidate()
        if let thermalStateObserver {
            NotificationCenter.default.removeObserver(thermalStateObserver)
            self.thermalStateObserver = nil
        }
        assertionManager.releaseAll()
        NSApp.terminate(nil)
    }
}
