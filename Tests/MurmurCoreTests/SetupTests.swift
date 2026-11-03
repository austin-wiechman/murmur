import Testing
@testable import MurmurCore

struct SetupTests {
    private func take(_ setup: inout Setup) -> Bool { setup.takeConfirmation() }

    private func completed() -> Setup {
        var setup = Setup(confirmed: false)
        setup.accessibility = true
        setup.microphone = true
        setup.updatesAnswered = true
        setup.speechModelReady = true
        return setup
    }

    @Test func confirmationPlaysOnceAfterSetupCompletes() {
        var setup = completed()
        setup.speechModelReady = false
        #expect(!take(&setup))
        #expect(setup.showsSetupMenu)

        setup.speechModelReady = true
        #expect(take(&setup))
        #expect(!take(&setup))
        #expect(!setup.showsSetupMenu)
    }

    @Test func dictatingBeforeOpeningTheMenuSkipsTheConfirmation() {
        var setup = completed()
        setup.dictated()
        #expect(!take(&setup))
        #expect(!setup.showsSetupMenu)
    }

    @Test func laterLaunchesDontShowSetupWhileTheCachedModelLoads() {
        var setup = completed()
        _ = setup.takeConfirmation()
        setup.speechModelReady = false
        #expect(!setup.needsAttention)
        #expect(!setup.showsSetupMenu)
    }

    @Test func losingAPermissionReturnsToSetupWithoutAnotherConfirmation() {
        var setup = completed()
        _ = setup.takeConfirmation()
        setup.accessibility = false
        #expect(setup.showsSetupMenu)
        #expect(setup.nextStep == .accessibility)

        setup.accessibility = true
        #expect(!take(&setup))
        #expect(!setup.showsSetupMenu)
    }
}
