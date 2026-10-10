import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Copies a user recording into Samples and renders it at the device rate.
/// Pitch is a resample, so a later device-rate change reads the original file again.
nonisolated enum SampleImporter {
    static let maxDuration = 10.0
    static let maxBytes = 50 * 1024 * 1024
    static let rightsLine = "Импортируйте только звуки, на которые у вас есть права"

    struct Failure: Error {
        var reason: String
    }

    static var readableTypes: [UTType] {
        var types: [UTType] = [.wav, .aiff]
        if let caf = UTType(filenameExtension: "caf") {
            types.append(caf)
        }
        return types
    }

    @MainActor
    static func place(_ url: URL, onTrack track: Int, sequencer: SequencerEngine) {
        guard sequencer.tracks.indices.contains(track) else { return }
        let voice = sequencer.tracks[track].soundPreset.resolvedVoice
        do {
            let preset = try importFile(url, voice: voice, into: PatternManager.shared.directory)
            UserPresetStore.shared.save(preset)
            UserPresetStore.shared.flush()
            sequencer.tracks[track].soundPreset = preset
            sequencer.notePadSoundEdited()
            AudioEngineManager.shared.loadSound(preset: preset, forTrack: track)
        } catch {
            return
        }
    }

    @MainActor
    static func storeInLibrary(_ url: URL, voice: SoundPreset.VoiceKind) {
        do {
            let preset = try importFile(url, voice: voice, into: PatternManager.shared.directory)
            UserPresetStore.shared.save(preset)
            UserPresetStore.shared.flush()
        } catch {
            return
        }
    }

    /// Copies the file, then returns a user preset. The caller saves it.
    @MainActor
    static func importFile(
        _ url: URL,
        voice: SoundPreset.VoiceKind,
        into directory: URL
    ) throws -> SoundPreset {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["wav", "aiff", "aif", "caf"].contains(ext) else {
            throw reject("нужен WAV, AIFF или CAF", file: url.lastPathComponent, url: url)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > maxBytes {
            throw reject("файл больше 50 МБ", file: url.lastPathComponent, url: url)
        }
        let probed = try AVAudioFile(forReading: url)
        let fileRate = probed.processingFormat.sampleRate
        if fileRate > 0, Double(probed.length) / fileRate > maxDuration {
            throw reject("файл длиннее 10 с", file: url.lastPathComponent, url: url)
        }
        let samples = directory.appendingPathComponent("Samples", isDirectory: true)
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        let storedName = "\(UUID().uuidString).\(ext)"
        let destination = samples.appendingPathComponent(storedName)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw reject(error.localizedDescription, file: url.lastPathComponent, url: url)
        }
        return preset(storedName: storedName, original: url.lastPathComponent, voice: voice)
    }

    @MainActor
    static func isMissing(_ preset: SoundPreset) -> Bool {
        guard case .sample(let fileName, _) = preset.source else { return false }
        let url = PatternManager.shared.directory
            .appendingPathComponent("Samples", isDirectory: true)
            .appendingPathComponent(fileName)
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// Mono float buffer at `sampleRate`, before ADSR and normalize. A missing file is silence.
    static func render(
        fileName: String,
        sampleRoot: URL,
        sampleRate: Double,
        pitch: Float
    ) -> [Float] {
        let url = sampleRoot.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            reportMissing(fileName, url: url)
            return [0]
        }
        do {
            return try renderFile(url, sampleRate: sampleRate, pitch: pitch)
        } catch {
            report(fileName, url: url, reason: error.localizedDescription)
            return [0]
        }
    }

    private static func preset(
        storedName: String,
        original: String,
        voice: SoundPreset.VoiceKind
    ) -> SoundPreset {
        let display = (original as NSString).deletingPathExtension
        var preset = SoundPreset(
            id: UUID(),
            name: display.isEmpty ? original : display,
            filename: storedName,
            category: category(for: voice),
            origin: .user
        )
        preset.voice = voice
        preset.source = .sample(fileName: storedName, originalName: original)
        preset.attack = 0
        preset.decay = 0
        preset.sustain = 1
        preset.release = 0
        return preset
    }

    private static func category(for voice: SoundPreset.VoiceKind) -> SoundPreset.SoundCategory {
        switch voice {
        case .kick: return .kick
        case .snare: return .snare
        case .closedHat, .openHat: return .hihat
        case .clap, .tom, .perc: return .percussion
        case .ride, .crash: return .cymbals
        case .fx: return .fx
        }
    }

    @MainActor
    private static func reject(_ reason: String, file: String, url: URL) -> Failure {
        PersistenceAlerts.shared.report(
            .failed(operation: .read, file: file, reason: reason),
            url: url
        )
        return Failure(reason: reason)
    }

    private static func reportMissing(_ fileName: String, url: URL) {
        report(fileName, url: url, reason: "файл не найден")
    }

    private static func report(_ fileName: String, url: URL, reason: String) {
        Task { @MainActor in
            PersistenceAlerts.shared.report(
                .failed(operation: .read, file: fileName, reason: reason),
                url: url
            )
        }
    }

    /// AVAudioConverter calls the input block on the thread that is inside `convert`.
    /// The buffer stays on that call, so the unchecked mark is the synchronous contract.
    private nonisolated final class ConverterPull: @unchecked Sendable {
        private let buffer: AVAudioPCMBuffer
        private var delivered = false

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
            if delivered {
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
    }

    /// `converterRate` is the device rate divided by the pitch ratio, so the buffer played
    /// at the device rate is shorter when the pitch goes up.
    private static func renderFile(_ url: URL, sampleRate: Double, pitch: Float) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard source.sampleRate > 0, file.length > 0 else { return [0] }
        let ratio = pow(2.0, Double(pitch) / 12.0)
        let converterRate = sampleRate / max(ratio, 0.0001)
        guard let destination = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: converterRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: source, to: destination) else {
            return [0]
        }
        let capacity = AVAudioFrameCount(file.length)
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: capacity) else { return [0] }
        try file.read(into: input)
        // convert(to:from:) refuses a sample-rate change. The block API does it,
        // and it fills each chunk up to that chunk's capacity.
        let estimated = Int(Double(input.frameLength) * converterRate / source.sampleRate)
        let limit = min(estimated + 512, Int(sampleRate * maxDuration) + 512)
        guard let output = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: 4096) else {
            return [0]
        }
        let pull = ConverterPull(input)
        var produced: [Float] = []
        produced.reserveCapacity(max(estimated, 1))
        var error: NSError?
        while produced.count < limit {
            output.frameLength = output.frameCapacity
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                pull.next(outStatus)
            }
            if status == .error {
                throw error ?? Failure(reason: "конвертер")
            }
            let wrote = Int(output.frameLength)
            if wrote > 0, let channel = output.floatChannelData?[0] {
                let take = min(wrote, limit - produced.count)
                produced.append(contentsOf: UnsafeBufferPointer(start: channel, count: take))
            }
            if status == .endOfStream || status == .inputRanDry || wrote == 0 {
                break
            }
        }
        return produced.isEmpty ? [0] : produced
    }
}
