import Foundation

public struct RuntimePowerPolicy: Equatable, Sendable {
    public let preventSystemSleep: Bool
    public let preventDisplaySleep: Bool
    public let lockOnCurrentLidClosure: Bool
    public let sleepOnCurrentLidClosure: Bool

    public init(
        preventSystemSleep: Bool,
        preventDisplaySleep: Bool,
        lockOnCurrentLidClosure: Bool,
        sleepOnCurrentLidClosure: Bool
    ) {
        self.preventSystemSleep = preventSystemSleep
        self.preventDisplaySleep = preventDisplaySleep
        self.lockOnCurrentLidClosure = lockOnCurrentLidClosure
        self.sleepOnCurrentLidClosure = sleepOnCurrentLidClosure
    }
}

public enum PowerPolicy {
    public static func runtimePolicy(
        for mode: PowerMode,
        snapshot: SystemPowerSnapshot
    ) -> RuntimePowerPolicy {
        let pluggedIn = snapshot.powerSource.isPluggedIn
        let lidClosed = snapshot.lidState.isClosed

        switch mode {
        case .extreme:
            return RuntimePowerPolicy(
                preventSystemSleep: true,
                preventDisplaySleep: true,
                lockOnCurrentLidClosure: false,
                sleepOnCurrentLidClosure: false
            )
        case .office:
            // Stay awake as a system, but let the panel sleep on idle with the lid open.
            // Lid-closed Office still locks, still prevents system sleep, and still allows display sleep.
            return RuntimePowerPolicy(
                preventSystemSleep: true,
                preventDisplaySleep: false,
                lockOnCurrentLidClosure: lidClosed,
                sleepOnCurrentLidClosure: false
            )
        case .standby:
            if lidClosed {
                return RuntimePowerPolicy(
                    preventSystemSleep: false,
                    preventDisplaySleep: false,
                    lockOnCurrentLidClosure: true,
                    sleepOnCurrentLidClosure: true
                )
            }

            if pluggedIn {
                return RuntimePowerPolicy(
                    preventSystemSleep: true,
                    preventDisplaySleep: true,
                    lockOnCurrentLidClosure: false,
                    sleepOnCurrentLidClosure: false
                )
            }

            return RuntimePowerPolicy(
                preventSystemSleep: false,
                preventDisplaySleep: false,
                lockOnCurrentLidClosure: false,
                sleepOnCurrentLidClosure: false
            )
        }
    }
}
