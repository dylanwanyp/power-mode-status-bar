import Foundation

/// Thermal bands the app acts on. Mapped from `ProcessInfo.ThermalState` by the app target.
public enum ThermalPressureLevel: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public var requiresCooldown: Bool {
        switch self {
        case .serious, .critical:
            return true
        case .nominal, .fair:
            return false
        }
    }
}

#if os(macOS)
public extension ThermalPressureLevel {
    init(processThermalState: ProcessInfo.ThermalState) {
        switch processThermalState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .nominal
        }
    }
}
#endif

public struct ThermalCooldownSession: Equatable, Sendable {
    public let preferredMode: PowerMode
    public let restoreAt: Date

    public init(preferredMode: PowerMode, startedAt: Date) {
        self.preferredMode = preferredMode
        self.restoreAt = startedAt.addingTimeInterval(ThermalCooldownPolicy.restoreDelay)
    }

    public func isDue(at now: Date) -> Bool {
        now >= restoreAt
    }
}

public enum ThermalCooldownPolicy {
    public static let checkInterval: TimeInterval = 30 * 60
    public static let restoreDelay: TimeInterval = 15 * 60

    /// Assertions to hold during cool-down. Standby with the lid open on AC still prevents
    /// sleep, so cool-down must release prevention directly instead of switching modes.
    public static let releasedAssertions = RuntimePowerPolicy(
        preventSystemSleep: false,
        preventDisplaySleep: false,
        lockOnCurrentLidClosure: false,
        sleepOnCurrentLidClosure: false
    )

    public static func participatesInCooldown(_ mode: PowerMode) -> Bool {
        switch mode {
        case .extreme, .office:
            return true
        case .standby:
            return false
        }
    }

    public static func shouldBeginCooldown(
        enabled: Bool,
        pressure: ThermalPressureLevel,
        mode: PowerMode,
        cooldownActive: Bool
    ) -> Bool {
        enabled
            && pressure.requiresCooldown
            && participatesInCooldown(mode)
            && !cooldownActive
    }

    /// Scheduled restore runs only when cool-down is still the active plan.
    /// A manual mode change sets `userDidOverride` and cancels this restore.
    public static func shouldRestorePreferredMode(
        enabled: Bool,
        cooldownActive: Bool,
        userDidOverride: Bool
    ) -> Bool {
        enabled && cooldownActive && !userDidOverride
    }

    public static func statusLine(modeTitle: String, restoreTime: String) -> String {
        "Thermal cool-down active: restores \(modeTitle) at \(restoreTime)"
    }
}
