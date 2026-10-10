import AVFoundation
import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct SampleImportTests {
    @Test func stereoSineBecomesMonoAtTheDeviceRateAndAgainAtTheFileRate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("sine.wav")
        try SampleTone.write(to: source)
        let preset = try SampleImporter.importFile(source, voice: .perc, into: directory)
        let root = directory.appendingPathComponent("Samples", isDirectory: true)
        let stored = root.appendingPathComponent(preset.filename)
        #expect(FileManager.default.fileExists(atPath: stored.path))
        if case .sample(let fileName, let original) = preset.source {
            #expect(fileName == preset.filename)
            #expect(original == "sine.wav")
        } else {
            Issue.record("imported preset is not a sample")
        }

        let atDevice = DrumSynthesizer.samples(for: preset, sampleRate: 48_000, sampleRoot: root)
        #expect(abs(atDevice.count - 24_000) < 400, "length \(atDevice.count)")
        let peak = atDevice.map { abs($0) }.max() ?? 0
        #expect(abs(peak - 0.5) < 0.02, "peak \(peak)")
        #expect(atDevice.last == 0)
        let finite = atDevice.allSatisfy { $0.isFinite }
        #expect(finite)

        let atFileRate = DrumSynthesizer.samples(for: preset, sampleRate: 44_100, sampleRoot: root)
        #expect(abs(atFileRate.count - 22_050) < 400, "file-rate length \(atFileRate.count)")
    }

    @Test func aMissingSamplePlaysSilence() {
        var preset = SoundPreset(
            id: UUID(),
            name: "Gone",
            filename: "gone.wav",
            category: .percussion,
            origin: .user
        )
        preset.voice = .perc
        preset.source = .sample(fileName: "gone.wav", originalName: "gone.wav")
        preset.sustain = 1
        preset.decay = 0
        preset.release = 0
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: true)
        let samples = DrumSynthesizer.samples(for: preset, sampleRate: 48_000, sampleRoot: root)
        #expect(samples == [0])
    }

    @Test func deletingASamplePresetRemovesTheFileUnlessAKitKeepsIt() throws {
        let alone = try SampleFixture()
        defer { alone.remove() }
        let alonePreset = try alone.importTone()
        let aloneStore = UserPresetStore(directory: alone.directory)
        aloneStore.save(alonePreset)
        aloneStore.flush()
        let aloneFile = alone.directory
            .appendingPathComponent("Samples", isDirectory: true)
            .appendingPathComponent(alonePreset.filename)
        aloneStore.delete(id: alonePreset.id)
        #expect(FileManager.default.fileExists(atPath: aloneFile.path) == false)

        let held = try SampleFixture()
        defer { held.remove() }
        let heldPreset = try held.importTone()
        let heldStore = UserPresetStore(directory: held.directory)
        heldStore.save(heldPreset)
        heldStore.flush()
        let kits = KitStore(directory: held.directory)
        kits.save(DrumKit(id: UUID(), name: "Hold", sounds: [heldPreset]))
        kits.flush()
        let heldFile = held.directory
            .appendingPathComponent("Samples", isDirectory: true)
            .appendingPathComponent(heldPreset.filename)
        heldStore.delete(id: heldPreset.id)
        #expect(FileManager.default.fileExists(atPath: heldFile.path))
    }
}

enum SampleTone {
    static func write(to url: URL) throws {
        let rate = 44_100.0
        let frames = Int(rate * 0.5)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: 2,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            throw SampleImporter.Failure(reason: "format")
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for index in 0..<frames {
            let sample = Float(sin(2 * Double.pi * 440 * Double(index) / rate))
            left[index] = sample
            right[index] = sample * 0.5
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

@MainActor
private struct SampleFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func importTone() throws -> SoundPreset {
        let source = directory.appendingPathComponent("tone.wav")
        try SampleTone.write(to: source)
        return try SampleImporter.importFile(source, voice: .perc, into: directory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
