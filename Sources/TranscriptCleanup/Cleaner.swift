public protocol Cleaner: Sendable {
    func prepare(instructions: String) -> CleanupSession
}
