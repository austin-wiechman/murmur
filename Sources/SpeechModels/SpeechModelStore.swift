import FluidAudio
import Foundation

/// Where downloaded speech models live. The default is FluidAudio's own folder in the user's
/// Application Support, so every unsandboxed app using it shares one download.
public struct SpeechModelStore: Sendable {
    public var directory: URL

    public init(directory: URL = MLModelConfigurationUtils.defaultModelsDirectory()) {
        self.directory = directory
    }

    public func folder(for model: SpeechModel) -> URL {
        directory.appendingPathComponent(model.repo.folderName, isDirectory: true)
    }

    /// Applies the checks FluidAudio makes before it skips a download, so a `true` here means
    /// loading the model won't download it again.
    public func isPresent(_ model: SpeechModel) -> Bool {
        let folder = folder(for: model)
        return Self.hasRevision(model.repo.revision, in: folder)
            && model.requiredFiles.allSatisfy { Self.isComplete(folder.appendingPathComponent($0)) }
    }

    /// Files from before FluidAudio wrote revision markers count as `main`.
    private static func hasRevision(_ revision: String, in folder: URL) -> Bool {
        let marker = folder.appendingPathComponent(".fluidaudio-revision")
        guard let data = try? Data(contentsOf: marker) else { return revision == "main" }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == revision
    }

    /// A compiled model is a folder with `coremldata.bin` and no `.partial` file left by an
    /// interrupted download.
    private static func isComplete(_ file: URL) -> Bool {
        guard file.pathExtension == "mlmodelc" else { return FileManager.default.fileExists(atPath: file.path) }
        guard FileManager.default.fileExists(atPath: file.appendingPathComponent("coremldata.bin").path) else {
            return false
        }
        let contents = FileManager.default.enumerator(at: file, includingPropertiesForKeys: nil)
        return !(contents?.contains { ($0 as? URL)?.pathExtension == "partial" } ?? false)
    }

    /// Downloads whatever is missing. `progress` gets the completed fraction, 0 through 1.
    public func download(_ model: SpeechModel, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        var handler: ProgressHandler?
        if let progress {
            handler = { update in progress(Self.downloadFraction(update.fractionCompleted)) }
        }
        try await ModelHub.download(model.repo, to: directory, variant: model.variant,
                                    additionalModelNames: model.requiredFiles, progressHandler: handler)
    }

    /// FluidAudio's repo download reports its download phase as 0...0.5 and reserves the rest for a
    /// compile step that loading the model does later.
    static func downloadFraction(_ reported: Double) -> Double {
        min(max(reported / 0.5, 0), 1)
    }
}
