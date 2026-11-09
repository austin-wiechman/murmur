import FluidAudio
import Foundation
import SpeechModels
import Testing

struct SpeechModelStoreTests {
    private let store = SpeechModelStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString))
    private let model = DictationModel.speechModel

    @Test func aModelIsPresentOnceEveryRequiredFileIsDownloaded() throws {
        #expect(!store.isPresent(model))
        try install(model)
        #expect(store.isPresent(model))
    }

    @Test func aMissingFileMeansTheModelIsNotPresent() throws {
        try install(model)
        try FileManager.default.removeItem(at: store.folder(for: model).appendingPathComponent("vocab.json"))
        #expect(!store.isPresent(model))
    }

    @Test func anInterruptedDownloadIsNotPresent() throws {
        try install(model)
        let bundle = try #require(model.requiredFiles.first { $0.hasSuffix(".mlmodelc") })
        let weights = store.folder(for: model).appendingPathComponent(bundle).appendingPathComponent("weights")
        try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
        try Data().write(to: weights.appendingPathComponent("weight.bin.partial"))
        #expect(!store.isPresent(model))
    }

    @Test func aCompiledModelWithoutItsDataIsNotPresent() throws {
        try install(model)
        let bundle = try #require(model.requiredFiles.first { $0.hasSuffix(".mlmodelc") })
        try FileManager.default.removeItem(
            at: store.folder(for: model).appendingPathComponent(bundle).appendingPathComponent("coremldata.bin"))
        #expect(!store.isPresent(model))
    }

    /// FluidAudio re-downloads a pinned repo whose files came from another revision.
    @Test func filesFromAnotherRevisionAreNotPresent() throws {
        let pinned = SpeechModel(repo: .diarizer, requiredFiles: ["vocab.json"])
        try install(pinned)
        #expect(!store.isPresent(pinned))
        try Data(pinned.repo.revision.utf8).write(to: store.folder(for: pinned).appendingPathComponent(".fluidaudio-revision"))
        #expect(store.isPresent(pinned))
    }

    private func install(_ model: SpeechModel) throws {
        let folder = store.folder(for: model)
        for file in model.requiredFiles {
            let path = folder.appendingPathComponent(file)
            if file.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                try Data([1]).write(to: path.appendingPathComponent("coremldata.bin"))
            } else {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data([1]).write(to: path)
            }
        }
    }
}
