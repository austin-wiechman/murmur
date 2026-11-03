/// First-run setup: four steps, then a one-time "ready" confirmation in the menu.
public struct Setup: Equatable, Sendable {
    public enum Step: CaseIterable, Sendable { case accessibility, microphone, updates, speechModel }

    public var accessibility = false
    public var microphone = false
    public var updatesAnswered = false
    public var speechModelReady = false
    /// Set once the confirmation has played or been skipped, and never cleared.
    public private(set) var confirmed: Bool

    public init(confirmed: Bool) {
        self.confirmed = confirmed
    }

    public func isDone(_ step: Step) -> Bool {
        switch step {
        case .accessibility: accessibility
        case .microphone: microphone
        case .updates: updatesAnswered
        case .speechModel: speechModelReady
        }
    }

    public var completedSteps: Int { Step.allCases.filter(isDone).count }
    public var isComplete: Bool { completedSteps == Step.allCases.count }

    /// The first step still waiting on the user. The speech model downloads by itself, so it never is.
    public var nextStep: Step? {
        Step.allCases.first { $0 != .speechModel && !isDone($0) }
    }

    /// A step is waiting on the user, or the first-run download hasn't finished. A later launch
    /// loading the cached model doesn't count, so the icon doesn't flash on every start.
    public var needsAttention: Bool { nextStep != nil || (!isComplete && !confirmed) }

    public var showsSetupMenu: Bool { needsAttention || !confirmed }

    /// Call when the menu is open and setup is complete. Returns whether to play the confirmation now.
    public mutating func takeConfirmation() -> Bool {
        guard isComplete, !confirmed else { return false }
        confirmed = true
        return true
    }

    /// Someone who has already dictated knows Murmur works, so the confirmation is skipped.
    public mutating func dictated() {
        if isComplete { confirmed = true }
    }
}
