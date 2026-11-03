import Observation

@MainActor @Observable
final class PillStore {
    var state: PillState = .hidden
}
