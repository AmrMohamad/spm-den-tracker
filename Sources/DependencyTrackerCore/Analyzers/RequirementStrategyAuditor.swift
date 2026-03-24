import Foundation

struct RequirementStrategyAuditor {
    func audit(_ pins: [ResolvedPin]) -> [StrategyFinding] {
        pins.map { pin in
            let risk: StrategyRisk
            let message: String

            switch pin.state {
            case .version:
                risk = .normal
                message = "\"\(pin.identity)\" is pinned to a version tag."
            case .branch(let branch, _):
                risk = .elevated
                message = "\"\(pin.identity)\" is pinned to branch \"\(branch)\"."
            case .revision:
                risk = .elevated
                message = "\"\(pin.identity)\" is pinned to a bare revision."
            case .local:
                risk = .environmentSensitive
                message = "\"\(pin.identity)\" is pinned to a local path."
            }

            return StrategyFinding(pin: pin, risk: risk, message: message)
        }
    }
}
