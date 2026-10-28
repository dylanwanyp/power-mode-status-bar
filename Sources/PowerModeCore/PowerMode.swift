import Foundation

public enum PowerMode: String, CaseIterable, Codable, Equatable, Sendable {
    case extreme
    case office
    case standby

    public var title: String {
        switch self {
        case .extreme:
            return "Extreme Mode"
        case .office:
            return "Office Mode"
        case .standby:
            return "Standby Mode"
        }
    }

    public var symbolName: String {
        switch self {
        case .extreme:
            return "bolt.circle.fill"
        case .office:
            return "laptopcomputer"
        case .standby:
            return "battery.100"
        }
    }

    public var coreFeatureSummary: String {
        switch self {
        case .extreme:
            return "Never sleeps or auto-locks"
        case .office:
            return "Display sleeps on idle; locks on lid close"
        case .standby:
            return "Lid close locks and sleeps"
        }
    }
}

public struct RuleSummary: Equatable, Sendable {
    public let lidTriggersSleep: Bool
    public let lidTriggersAutoLock: Bool
    public let unpluggedTriggersSleep: Bool
    public let unpluggedTriggersAutoLock: Bool

    public init(
        lidTriggersSleep: Bool,
        lidTriggersAutoLock: Bool,
        unpluggedTriggersSleep: Bool,
        unpluggedTriggersAutoLock: Bool
    ) {
        self.lidTriggersSleep = lidTriggersSleep
        self.lidTriggersAutoLock = lidTriggersAutoLock
        self.unpluggedTriggersSleep = unpluggedTriggersSleep
        self.unpluggedTriggersAutoLock = unpluggedTriggersAutoLock
    }

    public var lidLine: String {
        "Lid close: sleep \(lidTriggersSleep.displayText), auto-lock \(lidTriggersAutoLock.displayText)"
    }

    public var unpluggedLine: String {
        "On battery: sleep \(unpluggedTriggersSleep.displayText), auto-lock \(unpluggedTriggersAutoLock.displayText)"
    }
}

public extension PowerMode {
    var ruleSummary: RuleSummary {
        switch self {
        case .extreme:
            return RuleSummary(
                lidTriggersSleep: false,
                lidTriggersAutoLock: false,
                unpluggedTriggersSleep: false,
                unpluggedTriggersAutoLock: false
            )
        case .office:
            return RuleSummary(
                lidTriggersSleep: false,
                lidTriggersAutoLock: true,
                unpluggedTriggersSleep: false,
                unpluggedTriggersAutoLock: false
            )
        case .standby:
            return RuleSummary(
                lidTriggersSleep: true,
                lidTriggersAutoLock: true,
                unpluggedTriggersSleep: true,
                unpluggedTriggersAutoLock: false
            )
        }
    }
}

private extension Bool {
    var displayText: String {
        self ? "on" : "off"
    }
}
