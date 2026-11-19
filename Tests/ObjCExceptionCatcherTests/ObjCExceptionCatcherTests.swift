import AVFAudio
import Foundation
import ObjCExceptionCatcher
import Testing

@Test func raisedExceptionBecomesThrownError() {
    let error = #expect(throws: NSError.self) {
        try ObjCExceptionCatcher.catchException {
            NSException(name: NSExceptionName("com.apple.coreaudio.avfaudio"),
                        reason: "Failed to create tap due to format mismatch", userInfo: nil).raise()
        }
    }
    #expect(error?.domain == "com.apple.coreaudio.avfaudio")
    #expect(error?.localizedDescription == "Failed to create tap due to format mismatch")
}

@Test func blockThatReturnsDoesNotThrow() throws {
    var ran = false
    try ObjCExceptionCatcher.catchException { ran = true }
    #expect(ran)
}

@Test func tapOnADetachedNodeThrowsInsteadOfAborting() {
    #expect(throws: NSError.self) {
        try ObjCExceptionCatcher.installTap(on: AVAudioPlayerNode(), bus: 0, bufferSize: 1024, format: nil) { _, _ in }
    }
}
