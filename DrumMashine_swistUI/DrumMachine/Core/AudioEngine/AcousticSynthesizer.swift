import Foundation

/// Acoustic drums and percussion. Used only when a preset has `dynamics`.
/// Legacy `generateKick` and the other 808-style generators are not called from here.
nonisolated enum AcousticSynthesizer {
    static func render(
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        layer: Int,
        roundRobin: Int,
        sampleRate: Double
    ) -> [Float] {
        let rate = max(8_000, sampleRate)
        let velocity = min(1, max(0, velocity))
        let recipe = spec.recipe ?? defaultRecipe(for: preset)
        // Body seed ignores layer and round-robin so neighbors stay in phase
        // and a noisy hit stays the same instrument. Round-robin is a short overlay.
        let seed = UInt64(0xA11C_E001)
        var dry = voice(
            recipe: recipe,
            preset: preset,
            spec: spec,
            velocity: velocity,
            sampleRate: rate,
            seed: seed
        )
        var overlay = UnitNoise(seed: seed ^ (UInt64(layer) &* 0x85EB) ^ 0x51)
        let overlayCount = min(dry.count, Int(0.02 * rate))
        if overlayCount > 0 {
            let amp = Float(0.02 * (0.4 + 0.6 * velocity))
            for index in 0..<overlayCount {
                let env = Float(overlayCount - index) / Float(overlayCount)
                dry[index] += Float(overlay.next()) * amp * env
            }
        }
        if let mic = preset.mic {
            dry = bakeMic(dry, mic: mic, velocity: velocity, sampleRate: rate, seed: seed)
        }
        addRoundRobin(
            &dry,
            roundRobin: roundRobin,
            sampleRate: rate,
            lowpassHz: snareRoundRobinLowpass(recipe)
        )
        if dry.isEmpty { return [0] }
        return dry
    }

    /// Snare wire energy lives in 3–8 kHz. Full-band round-robin noise fills that
    /// band on a ghost hit, so snare noise is lowpassed and the other voices stay broadband.
    private static func snareRoundRobinLowpass(_ recipe: AcousticRecipe) -> Double? {
        switch recipe {
        case .snareCenter, .snareRimshot, .snareCrossStick, .concertSnare:
            return 1_100
        default:
            return nil
        }
    }

    /// Same noise shape on every layer of one round-robin, a bit above the
    /// attack RMS, so the first 50 ms correlate as one instrument and still differ.
    private static func addRoundRobin(
        _ buffer: inout [Float],
        roundRobin: Int,
        sampleRate: Double,
        lowpassHz: Double?
    ) {
        let count = min(buffer.count, max(1, Int(0.050 * sampleRate)))
        guard count > 8 else { return }
        var energy = 0.0
        for index in 0..<count {
            let sample = Double(buffer[index])
            energy += sample * sample
        }
        let rms = sqrt(energy / Double(count))
        let amp = Float(max(rms * 1.15, 1e-4))
        var noise = UnitNoise(seed: 0xC0FFEE ^ (UInt64(roundRobin) &* 0x9E37) ^ 0x51)
        let cutoff = lowpassHz ?? 0
        let alpha = cutoff > 0 ? (1 - exp(-2 * Double.pi * cutoff / sampleRate)) : 1
        let makeup: Float = cutoff > 0 ? 1.8 : 1
        var low = 0.0
        var low2 = 0.0
        for index in 0..<count {
            let env = Float(count - index) / Float(count)
            var sample = Double(noise.next())
            if cutoff > 0 {
                low += alpha * (sample - low)
                low2 += alpha * (low - low2)
                sample = low2
            }
            buffer[index] += Float(sample) * amp * env * 0.75 * makeup
        }
    }

    private static func defaultRecipe(for preset: SoundPreset) -> AcousticRecipe {
        switch preset.resolvedVoice {
        case .kick: return .membraneKick
        case .snare: return .snareCenter
        case .closedHat: return .hatClosed
        case .openHat: return .hatOpen
        case .clap: return .clap
        case .tom: return .membraneTom
        case .ride: return .rideBow
        case .crash: return .crash
        case .perc: return .conga
        case .fx: return .clap
        }
    }

    private static func voice(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        switch recipe {
        case .membraneKick, .membraneTom, .orchestralBass, .timpani:
            return membrane(
                recipe: recipe, preset: preset, spec: spec,
                velocity: velocity, sampleRate: sampleRate, seed: seed
            )
        case .snareCenter, .snareRimshot, .snareCrossStick, .concertSnare:
            return snare(
                recipe: recipe, preset: preset, spec: spec,
                velocity: velocity, sampleRate: sampleRate, seed: seed
            )
        case .brushTap, .brushSwirl, .brushSlap:
            return brush(
                recipe: recipe, preset: preset, spec: spec,
                velocity: velocity, sampleRate: sampleRate, seed: seed
            )
        case .hatClosed, .hatOpen, .hatPedal, .hatHalfOpen,
             .rideBow, .rideBell, .rideEdge,
             .crash, .splash, .china, .suspendedCymbal:
            return metal(
                recipe: recipe, preset: preset, spec: spec,
                velocity: velocity, sampleRate: sampleRate, seed: seed
            )
        case .conga, .bongo, .cajon, .djembe, .timbale:
            return hand(
                recipe: recipe, preset: preset, spec: spec,
                velocity: velocity, sampleRate: sampleRate, seed: seed
            )
        case .shaker, .tambourine, .clap, .snap, .guiro:
            return shaken(
                recipe: recipe, preset: preset, spec: spec,
                velocity: velocity, sampleRate: sampleRate, seed: seed
            )
        case .cowbell, .agogo, .wood, .triangle:
            return idiophone(
                recipe: recipe, preset: preset, spec: spec,
                velocity: velocity, sampleRate: sampleRate, seed: seed
            )
        }
    }

    // MARK: Membrane

    private static func membrane(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        let model = preset.synth?.membrane
        let f0 = tuned(spec.f0 ?? model?.f0 ?? defaultF0(recipe), pitch: preset.pitch)
        let damping = min(1, max(0, model?.damping ?? (recipe == .timpani ? 0.15 : 0.4)))
        let beater = min(1, max(0, model?.beater ?? (recipe == .orchestralBass ? 0.25 : 0.7)))
        let port = model?.port ?? false
        let seconds = min(recipe == .orchestralBass || recipe == .timpani ? 2.5 : 1.6, max(0.12, Double(preset.decay) * 5))
        var buffer = allocate(seconds: seconds * (port ? 0.65 : 1), sampleRate: sampleRate)
        let ratios = [1.0, 1.59, 2.14, 2.30, 2.65]
        let tilt = harmonicTilt(preset: preset, velocity: velocity)
        let amps = [1.0, 0.52 * tilt, 0.30 * tilt, 0.20 * tilt, 0.12 * tilt]
        let taus = [1.0, 0.55, 0.45, 0.38, 0.30]
        let baseTau = max(0.04, Double(preset.decay) * (1.5 - damping))
        let rise = (preset.dynamics?.pitch ?? 1.0) * velocity
        addSweptModes(
            &buffer, f0: f0, ratios: ratios, amps: amps, tauScales: taus,
            baseTau: baseTau, damping: damping, riseSemitones: rise, fallSeconds: 0.028,
            bodyAttack: 0.002 + 0.02 * velocity, sampleRate: sampleRate
        )
        let front = port ? 0.25 : 0.45
        addMode(&buffer, hz: f0 * 1.1, amp: front * (1 - damping * 0.5), tau: baseTau * 0.7, sampleRate: sampleRate)
        let clickTop = 2_400 + 2_800 * velocity
        addBeater(&buffer, velocity: velocity, beater: beater, sampleRate: sampleRate, seed: seed, lowHz: 1_800, highHz: clickTop, tau: 0.007)
        if recipe == .membraneTom || recipe == .timpani {
            let drop = (1.2 + velocity) * (recipe == .timpani ? 0.6 : 1)
            addPitchDrop(&buffer, f0: f0, depthSemitones: drop, seconds: 0.1, amp: 0.35, tau: baseTau, sampleRate: sampleRate)
        }
        return buffer
    }

    // MARK: Snare

    private static func snare(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        let model = preset.synth?.snareModel
        let f0 = tuned(spec.f0 ?? model?.f0 ?? (recipe == .snareRimshot ? 210 : 190), pitch: preset.pitch)
        let seconds = min(1.2, max(0.1, Double(preset.decay) * 4))
        var buffer = allocate(seconds: recipe == .snareCrossStick ? min(0.12, seconds) : seconds, sampleRate: sampleRate)
        let damping = preset.synth?.membrane?.damping ?? 0.35
        if recipe != .snareCrossStick {
            addSweptModes(
                &buffer, f0: f0, ratios: [1, 1.59, 2.14, 2.30],
                amps: [1, 0.45, 0.22, 0.12], tauScales: [1, 0.5, 0.4, 0.32],
                baseTau: max(0.04, Double(preset.decay) * (1.2 - 0.6 * damping)),
                damping: damping,
                riseSemitones: 0.4 * velocity,
                fallSeconds: 0.02,
                sampleRate: sampleRate
            )
            addMode(&buffer, hz: 520, amp: 0.18, tau: 0.03, sampleRate: sampleRate)
            addMode(&buffer, hz: 780, amp: 0.12, tau: 0.025, sampleRate: sampleRate)
        }
        if recipe == .snareRimshot {
            addMode(&buffer, hz: 980, amp: 0.22, tau: 0.04, sampleRate: sampleRate)
            addPartialCluster(&buffer, lowHz: 2_200, highHz: 6_500, count: 6, amp: 0.16, tau: 0.04, sampleRate: sampleRate, seed: seed ^ 0x51A0)
            addBeater(&buffer, velocity: 0.78 + 0.22 * velocity, beater: 1, sampleRate: sampleRate, seed: seed, lowHz: 1_200, highHz: 3_600, tau: 0.008)
        } else if recipe == .snareCrossStick {
            addMode(&buffer, hz: 1_400, amp: 0.7, tau: 0.012, sampleRate: sampleRate)
            addMode(&buffer, hz: 2_100, amp: 0.35, tau: 0.008, sampleRate: sampleRate)
            addBeater(&buffer, velocity: min(1, 0.3 + velocity), beater: 0.4, sampleRate: sampleRate, seed: seed, lowHz: 1_000, highHz: 2_400, tau: 0.006)
        } else {
            addBeater(&buffer, velocity: velocity, beater: 0.65, sampleRate: sampleRate, seed: seed, lowHz: 600, highHz: 1_600, tau: 0.006)
        }
        if recipe == .snareCenter || recipe == .snareRimshot || recipe == .concertSnare {
            let amount = min(1, max(0, spec.wires ?? model?.wires ?? (recipe == .concertSnare ? 1 : 0.75)))
            let open = min(1, max(0, (velocity - 0.02) / 0.98))
            let wires = (0.25 + 0.75 * pow(open, 0.7)) * amount * (recipe == .concertSnare ? 1.25 : 1)
            addBandNoise(&buffer, amp: wires * 0.55, lowHz: 3_000, highHz: 8_000, tau: 0.09, sampleRate: sampleRate, seed: seed ^ 0x51A4)
            let buzz = model?.buzz ?? 0.25
            if buzz > 0.01 {
                addBandNoise(&buffer, amp: wires * buzz * 0.2, lowHz: 2_500, highHz: 6_000, tau: 0.16, sampleRate: sampleRate, seed: seed ^ 0xB022)
            }
        }
        return buffer
    }

    // MARK: Brush

    private static func brush(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        let f0 = tuned(spec.f0 ?? 180, pitch: preset.pitch)
        let seconds: Double
        switch recipe {
        case .brushSwirl: seconds = min(1.5, max(0.6, Double(preset.decay) * 3))
        case .brushSlap: seconds = min(0.35, max(0.08, Double(preset.decay)))
        default: seconds = min(0.2, max(0.05, Double(preset.decay)))
        }
        var buffer = allocate(seconds: seconds, sampleRate: sampleRate)
        addMode(&buffer, hz: f0, amp: recipe == .brushSwirl ? 0.15 : 0.35, tau: seconds * 0.4, sampleRate: sampleRate)
        let noiseAmp = (recipe == .brushSlap ? 0.7 : 0.4) * (0.55 + 0.45 * velocity)
        let low: Double = recipe == .brushSlap ? 2_000 : 5_000
        addBandNoise(&buffer, amp: noiseAmp, lowHz: low, highHz: 8_000, tau: seconds * 0.5, sampleRate: sampleRate, seed: seed)
        if recipe == .brushSwirl {
            let lfoHz = 1.5 + velocity
            var phase = 0.0
            let step = lfoHz / sampleRate
            for index in buffer.indices {
                let swell = 0.55 + 0.45 * sin(phase * 2 * Double.pi)
                buffer[index] *= Float(swell * velocity)
                phase += step
                if phase >= 1 { phase -= 1 }
            }
        }
        return buffer
    }

    // MARK: Metal

    private static func metal(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        let scale = preset.synth?.metal?.scale ?? 1
        let seconds = metalSeconds(recipe, decay: Double(preset.decay))
        var buffer = allocate(seconds: seconds, sampleRate: sampleRate)
        let hatRatios = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0, 1_243.0]
        let bright = 0.45 + 1.15 * velocity
        switch recipe {
        case .hatClosed, .hatOpen, .hatPedal, .hatHalfOpen:
            for (index, ratio) in hatRatios.enumerated() {
                let hz = ratio * scale * (0.85 + 0.3 * velocity)
                let amp = (index < 4 ? 0.22 : 0.1) * (recipe == .hatPedal ? 0.45 : 1)
                addSquare(&buffer, hz: hz, amp: amp, tau: seconds * 0.55, sampleRate: sampleRate)
            }
            addPartialCluster(&buffer, lowHz: 3_000 * bright, highHz: min(14_000, 6_000 + 8_000 * velocity), count: 8, amp: 0.08, tau: seconds * 0.4, sampleRate: sampleRate, seed: seed)
            if recipe != .hatPedal {
                addBandNoise(&buffer, amp: 0.20 + 0.18 * velocity, lowHz: 6_000, highHz: 12_000, tau: seconds * 0.35, sampleRate: sampleRate, seed: seed ^ 0x11)
            }
        case .rideBow, .rideBell, .rideEdge:
            let ping = recipe == .rideBell ? 0.15 : 0.45 * velocity
            addBeater(&buffer, velocity: max(velocity, 0.2), beater: ping, sampleRate: sampleRate, seed: seed, lowHz: 1_500, highHz: 6_000, tau: 0.004)
            addPartialCluster(&buffer, lowHz: recipe == .rideBell ? 600 : 2_000, highHz: recipe == .rideBell ? 1_600 : 8_000, count: 10, amp: recipe == .rideBell ? 0.16 : 0.07, tau: seconds * 0.7, sampleRate: sampleRate, seed: seed)
            let wash = pow(velocity, 0.8) * (recipe == .rideEdge ? 0.45 : 0.22)
            let rivets = preset.synth?.metal?.rivets ?? 0
            addBandNoise(&buffer, amp: wash + rivets * 0.3, lowHz: 4_000, highHz: 10_000, tau: seconds * 0.8, sampleRate: sampleRate, seed: seed ^ 0x22)
            addBandNoise(&buffer, amp: 0.02 + 1.25 * pow(velocity, 1.35), lowHz: 6_500, highHz: 12_000, tau: 0.014, sampleRate: sampleRate, seed: seed ^ 0x2B)
            if recipe == .rideBell {
                addMode(&buffer, hz: tuned(820 * scale, pitch: preset.pitch), amp: 0.4, tau: 0.4, sampleRate: sampleRate)
            }
        default:
            let fm = recipe == .china ? 1.4 : (recipe == .splash ? 0.4 : 0.8)
            addFM(&buffer, carrier: tuned(280 * scale, pitch: preset.pitch), mod: 190 * fm, index: 1.5 + 1.1 * velocity, tau: seconds * 0.45, sampleRate: sampleRate)
            addPartialCluster(
                &buffer,
                lowHz: 1_400 + 800 * velocity,
                highHz: 6_000 + 2_200 * velocity,
                count: 10,
                amp: 0.06 + 0.04 * velocity,
                tau: seconds * 0.6,
                sampleRate: sampleRate,
                seed: seed
            )
            addBandNoise(&buffer, amp: 0.01 + 0.55 * pow(velocity, 1.6), lowHz: 7_000, highHz: 14_000, tau: 0.015, sampleRate: sampleRate, seed: seed ^ 0xC4)
            bloomHighs(&buffer, velocity: velocity, sampleRate: sampleRate, seed: seed ^ 0x33)
        }
        let hpCut: Double
        switch recipe {
        case .hatPedal: hpCut = 1_500
        case .hatClosed, .hatOpen, .hatHalfOpen: hpCut = 1_200 + 4_500 * velocity
        case .rideBell: hpCut = 400
        case .rideBow, .rideEdge: hpCut = 1_600 + 1_200 * velocity
        case .crash, .china, .splash, .suspendedCymbal: hpCut = 1_500 + 1_200 * velocity
        default: hpCut = 900 + 3_200 * velocity
        }
        highpass(&buffer, cutoff: hpCut, sampleRate: sampleRate)
        return buffer
    }

    private static func metalSeconds(_ recipe: AcousticRecipe, decay: Double) -> Double {
        switch recipe {
        case .hatClosed: return min(0.09, max(0.03, decay))
        case .hatPedal: return min(0.05, max(0.025, decay * 0.6))
        case .hatHalfOpen: return min(0.30, max(0.15, decay))
        case .hatOpen: return min(1.5, max(0.5, decay * 2))
        case .splash: return min(0.8, max(0.4, decay))
        case .rideBow, .rideBell, .rideEdge, .crash, .china, .suspendedCymbal:
            return min(2.5, max(0.5, decay * 3))
        default:
            return min(1.2, max(0.2, decay * 2))
        }
    }

    // MARK: Hand drums

    private static func hand(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        let model = preset.synth?.hand
        let tag = (spec.tag ?? "").lowercased()
        let f0 = tuned(spec.f0 ?? model?.f0 ?? handF0(recipe, tag: tag), pitch: preset.pitch)
        let slap = tag == "slap" || (model?.slap ?? 0) > 0.6
        let seconds = min(0.8, max(0.08, Double(preset.decay) * 3))
        var buffer = allocate(seconds: slap ? min(0.2, seconds) : seconds, sampleRate: sampleRate)
        if recipe == .cajon && (tag == "bass" || tag.isEmpty || spec.f0 == nil && tag != "slap" && tag != "tip") {
            addMode(&buffer, hz: f0, amp: 1, tau: 0.12, sampleRate: sampleRate)
            let wires = 0.35 + 0.65 * velocity
            addBandNoise(&buffer, amp: 0.45 * wires, lowHz: 3_000, highHz: 6_000, tau: 0.03, sampleRate: sampleRate, seed: seed)
        } else if slap || tag == "tip" {
            addBeater(&buffer, velocity: 0.84 + 0.16 * velocity, beater: 0.9, sampleRate: sampleRate, seed: seed, lowHz: 1_200, highHz: 6_000, tau: 0.01)
            addMode(&buffer, hz: f0 * 2.1, amp: 0.3, tau: 0.02, sampleRate: sampleRate)
        } else {
            addSweptModes(
                &buffer, f0: f0, ratios: [1, 1.59, 2.14, 2.65],
                amps: [1, 0.4, 0.2, 0.1], tauScales: [1, 0.5, 0.4, 0.3],
                baseTau: max(0.05, Double(preset.decay)), damping: tag == "mute" || tag == "heel" ? 0.85 : 0.25,
                riseSemitones: 0.5 * velocity, fallSeconds: 0.03, sampleRate: sampleRate
            )
        }
        if recipe == .timbale && (tag == "rim" || tag == "paila") {
            addMode(&buffer, hz: f0 * 3.2, amp: 0.5, tau: 0.08, sampleRate: sampleRate)
            addSquare(&buffer, hz: f0 * 2.4, amp: 0.2, tau: 0.05, sampleRate: sampleRate)
        }
        return buffer
    }

    private static func handF0(_ recipe: AcousticRecipe, tag: String) -> Double {
        switch recipe {
        case .conga:
            if tag == "quinto" { return 280 }
            if tag == "tumba" { return 180 }
            return 230
        case .bongo: return tag == "hembra" ? 340 : 460
        case .cajon: return tag == "slap" || tag == "tip" ? 180 : 80
        case .djembe:
            if tag == "bass" { return 70 }
            if tag == "slap" { return 400 }
            return 330
        case .timbale: return 420
        default: return 200
        }
    }

    // MARK: Shaken and clap

    private static func shaken(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        let seconds: Double
        switch recipe {
        case .guiro: seconds = min(0.8, max(0.12, Double(preset.decay) * (0.6 + velocity)))
        case .clap: seconds = min(0.45, max(0.12, Double(preset.decay)))
        case .snap: seconds = min(0.22, max(0.045, Double(preset.decay)))
        case .tambourine: seconds = min(0.7, max(0.1, Double(preset.decay) * 2))
        default: seconds = min(0.4, max(0.08, Double(preset.decay)))
        }
        var buffer = allocate(seconds: seconds, sampleRate: sampleRate)
        var rng = UnitNoise(seed: seed)
        switch recipe {
        case .shaker:
            let density = Int(8 + 40 * velocity)
            let gap = max(1, buffer.count / density)
            for grain in 0..<density {
                let at = min(buffer.count - 1, grain * gap)
                let length = min(buffer.count - at, Int(0.008 * sampleRate))
                for index in 0..<length {
                    let env = Float(length - index) / Float(length)
                    buffer[at + index] += Float(rng.next()) * env * 0.5
                }
            }
            bandpass(&buffer, lowHz: 5_000, highHz: 9_000, sampleRate: sampleRate)
        case .tambourine:
            let jingles = 8 + Int(8 * velocity)
            for index in 0..<jingles {
                let hz = 4_000 + Double(index) * 380 * (1 + 0.15 * velocity)
                addMode(&buffer, hz: hz, amp: 0.12, tau: seconds * 0.45, sampleRate: sampleRate, phase: Double(index) * 0.17)
            }
            addBeater(&buffer, velocity: velocity, beater: 0.5, sampleRate: sampleRate, seed: seed, lowHz: 3_000, highHz: 8_000, tau: 0.01)
        case .clap, .snap:
            let hands = recipe == .snap ? 1 : (spec.tag == "single" ? 1 : 3 + Int(velocity * 2))
            for hand in 0..<hands {
                let at = min(buffer.count - 1, Int(Double(hand) * (0.003 + 0.009 * velocity) * sampleRate))
                let length = min(buffer.count - at, Int(0.04 * sampleRate))
                for index in 0..<length {
                    let env = exp(-Double(index) / (0.008 * sampleRate))
                    buffer[at + index] += Float(rng.next() * env) * 0.6
                }
            }
            let shift = pow(2, Double(preset.pitch) / 12)
            let low = (recipe == .snap ? 2_000.0 : 800.0) * shift
            let high = (recipe == .snap ? 4_500.0 : 6_000.0) * shift
            bandpass(&buffer, lowHz: low, highHz: max(low + 400, high), sampleRate: sampleRate)
        case .guiro:
            let rateHz = 25 + 35 * velocity
            let period = max(1, Int(sampleRate / rateHz))
            var cursor = 0
            while cursor < buffer.count {
                let length = min(buffer.count - cursor, Int(0.004 * sampleRate))
                for index in 0..<length {
                    let env = Float(length - index) / Float(max(length, 1))
                    buffer[cursor + index] += Float(rng.next()) * env
                }
                cursor += period
            }
            bandpass(&buffer, lowHz: 1_200, highHz: 5_000, sampleRate: sampleRate)
        default:
            break
        }
        return buffer
    }

    // MARK: Idiophones

    private static func idiophone(
        recipe: AcousticRecipe,
        preset: SoundPreset,
        spec: ArticulationSpec,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        let tag = (spec.tag ?? "").lowercased()
        let seconds = recipe == .triangle ? min(2.5, max(0.4, Double(preset.decay) * 3)) : min(0.5, max(0.08, Double(preset.decay) * 2))
        var buffer = allocate(seconds: tag == "mute" ? min(0.12, seconds) : seconds, sampleRate: sampleRate)
        switch recipe {
        case .cowbell:
            let base = tuned(spec.f0 ?? 560, pitch: preset.pitch)
            addSquare(&buffer, hz: base, amp: 0.4, tau: 0.12, sampleRate: sampleRate)
            addSquare(&buffer, hz: base * 1.5, amp: 0.28, tau: 0.08, sampleRate: sampleRate)
            addBeater(&buffer, velocity: velocity, beater: 0.4, sampleRate: sampleRate, seed: seed, lowHz: 1_000, highHz: 4_000, tau: 0.005)
        case .agogo:
            let high = tag != "low"
            let base = tuned(high ? 780 : 520, pitch: preset.pitch)
            addMode(&buffer, hz: base, amp: 0.6, tau: 0.2, sampleRate: sampleRate)
            addMode(&buffer, hz: base * 2.4, amp: 0.2 * (0.4 + velocity), tau: 0.08, sampleRate: sampleRate)
        case .wood:
            let base = tuned(tag == "low" ? 900 : 1_800, pitch: preset.pitch)
            addMode(&buffer, hz: base, amp: 0.8, tau: 0.02, sampleRate: sampleRate)
            addMode(&buffer, hz: base * 1.6, amp: 0.25, tau: 0.01, sampleRate: sampleRate)
        case .triangle:
            let base = tuned(spec.f0 ?? 1_800, pitch: preset.pitch)
            for index in 0..<7 {
                let hz = base * (1 + Double(index) * 0.73)
                addMode(&buffer, hz: hz, amp: 0.2 * (1 - Double(index) * 0.1), tau: seconds * 0.5, sampleRate: sampleRate)
            }
        default:
            break
        }
        return buffer
    }

    // MARK: Mic

    /// Close, a short overhead, and a seeded room tail. Not the live effects rack.
    private static func bakeMic(
        _ dry: [Float],
        mic: MicMix,
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) -> [Float] {
        guard !dry.isEmpty else { return dry }
        let rt60: Double
        switch mic.resolvedRoomSize {
        case .small: rt60 = 0.35
        case .medium: rt60 = 0.7
        case .large: rt60 = 1.2
        case .hall: rt60 = 1.6
        }
        let extra = Int(min(1.5, rt60) * sampleRate)
        var out = [Float](repeating: 0, count: dry.count + extra)
        let close = Float(min(2.0, max(0.0, mic.resolvedClose)))
        for index in dry.indices { out[index] += dry[index] * close }
        let delay = max(1, Int(0.002 * sampleRate))
        var overhead = Pole(cutoff: 420, sampleRate: sampleRate, lowpass: false)
        let oh = Float(min(2.0, max(0.0, mic.resolvedOverhead)))
        for index in dry.indices {
            let filtered = overhead.process(dry[index])
            let at = index + delay
            if at < out.count { out[at] += filtered * oh }
            let comb = index + delay * 2
            if comb < out.count { out[comb] += filtered * oh * 0.35 }
        }
        let open = pow(max(velocity, 0), 0.7)
        // Hold the v=0.8 send and pull neighbors toward it so layer centroids stay close.
        let shaped = 0.855 * (0.86 + 0.14 * open / 0.855)
        let send = Float(min(2.0, max(0.0, mic.resolvedRoom))) * Float(shaped)
        let taps = [0.005, 0.008, 0.013, 0.018, 0.024, 0.031, 0.037, 0.044]
        let gains: [Float] = [0.55, 0.42, 0.33, 0.26, 0.2, 0.15, 0.11, 0.08]
        for (tap, gain) in zip(taps, gains) {
            let atDelay = Int(tap * sampleRate)
            for index in dry.indices {
                let dest = index + atDelay
                if dest < out.count { out[dest] += dry[index] * send * gain }
            }
        }
        let tone = min(1, max(-1, mic.resolvedRoomTone))
        let cutoff = 900 * pow(8, (tone + 1) / 2)
        var color = Pole(cutoff: cutoff, sampleRate: sampleRate, lowpass: true)
        var rng = UnitNoise(seed: seed ^ 0x5100_D)
        var env = Double(send) * 0.18
        let decay = exp(-6.9 / (max(0.05, rt60) * sampleRate))
        let start = min(out.count, Int(0.012 * sampleRate))
        for index in start..<out.count {
            out[index] += color.process(Float(rng.next())) * Float(env)
            env *= decay
        }
        return out
    }

    // MARK: Oscillators

    private static func allocate(seconds: Double, sampleRate: Double) -> [Float] {
        let count = max(8, Int(max(0.02, seconds) * sampleRate))
        return [Float](repeating: 0, count: count)
    }

    /// 1 at a bright accent, lower when velocity or `dynamics.brightness` is low.
    private static func harmonicTilt(preset: SoundPreset, velocity: Double) -> Double {
        let amount = min(1, max(0, preset.dynamics?.brightness ?? 0.45))
        return (1 - amount * 0.75) + amount * 0.75 * min(1, max(0, velocity))
    }

    private static func tuned(_ hz: Double, pitch: Float) -> Double {
        min(8_000, max(20, hz * pow(2, Double(pitch) / 12)))
    }

    private static func defaultF0(_ recipe: AcousticRecipe) -> Double {
        switch recipe {
        case .membraneKick: return 55
        case .orchestralBass: return 48
        case .timpani: return 110
        case .membraneTom: return 140
        default: return 180
        }
    }

    private static func addMode(
        _ buffer: inout [Float],
        hz: Double,
        amp: Double,
        tau: Double,
        sampleRate: Double,
        phase: Double = 0
    ) {
        guard hz > 1, amp != 0, tau > 0, sampleRate > 0 else { return }
        var cycle = phase.truncatingRemainder(dividingBy: 1)
        if cycle < 0 { cycle += 1 }
        let step = hz / sampleRate
        let decay = exp(-1 / (tau * sampleRate))
        var env = 1.0
        for index in buffer.indices {
            buffer[index] += Float(sin(cycle * 2 * Double.pi) * env * amp)
            cycle += step
            if cycle >= 1 { cycle -= 1 }
            env *= decay
        }
    }

    private static func addSweptModes(
        _ buffer: inout [Float],
        f0: Double,
        ratios: [Double],
        amps: [Double],
        tauScales: [Double],
        baseTau: Double,
        damping: Double,
        riseSemitones: Double,
        fallSeconds: Double,
        bodyAttack: Double = 0,
        sampleRate: Double
    ) {
        let count = min(ratios.count, min(amps.count, tauScales.count))
        var cycle = [Double](repeating: 0, count: count)
        var env = [Double](repeating: 1, count: count)
        var decay = [Double](repeating: 1, count: count)
        for index in 0..<count {
            let tau = max(0.008, baseTau * tauScales[index] * (index == 0 ? 1 : (1 - 0.7 * damping)))
            decay[index] = exp(-1 / (tau * sampleRate))
        }
        let fall = max(0.005, fallSeconds)
        for frame in buffer.indices {
            let t = Double(frame) / sampleRate
            let semis = riseSemitones * exp(-t / fall)
            let hz0 = f0 * pow(2, semis / 12)
            let open = bodyAttack > 0 ? min(1, t / bodyAttack) : 1
            var sample = 0.0
            for index in 0..<count {
                let modeAmp = amps[index] * (index == 0 ? 1 : (1 - 0.75 * damping))
                sample += sin(cycle[index] * 2 * Double.pi) * env[index] * modeAmp
                cycle[index] += hz0 * ratios[index] / sampleRate
                if cycle[index] >= 1 { cycle[index] -= floor(cycle[index]) }
                env[index] *= decay[index]
            }
            buffer[frame] += Float(sample * open)
        }
    }

    /// A second fundamental that starts sharp and falls. Tom pitch dive.
    private static func addPitchDrop(
        _ buffer: inout [Float],
        f0: Double,
        depthSemitones: Double,
        seconds: Double,
        amp: Double,
        tau: Double,
        sampleRate: Double
    ) {
        var cycle = 0.0
        let decay = exp(-1 / (max(0.01, tau) * sampleRate))
        var env = amp
        let span = max(0.02, seconds)
        for index in buffer.indices {
            let t = Double(index) / sampleRate
            let semis = depthSemitones * exp(-t / span)
            let hz = f0 * pow(2, semis / 12)
            buffer[index] += Float(sin(cycle * 2 * Double.pi) * env)
            cycle += hz / sampleRate
            if cycle >= 1 { cycle -= floor(cycle) }
            env *= decay
        }
    }

    private static func addSquare(
        _ buffer: inout [Float],
        hz: Double,
        amp: Double,
        tau: Double,
        sampleRate: Double
    ) {
        guard hz > 1, amp != 0 else { return }
        var cycle = 0.0
        let step = hz / sampleRate
        let decay = exp(-1 / (max(0.005, tau) * sampleRate))
        var env = amp
        for index in buffer.indices {
            let square: Double = cycle < 0.5 ? 1 : -1
            buffer[index] += Float(square * env)
            cycle += step
            if cycle >= 1 { cycle -= 1 }
            env *= decay
        }
    }

    private static func addBeater(
        _ buffer: inout [Float],
        velocity: Double,
        beater: Double,
        sampleRate: Double,
        seed: UInt64,
        lowHz: Double,
        highHz: Double,
        tau: Double
    ) {
        let v = min(1, max(velocity, 0))
        let curved: Double
        if v <= 0.5 {
            curved = pow(v, 1.5)
        } else {
            let mid = pow(0.5, 1.5)
            curved = mid + (1 - mid) * pow((v - 0.5) * 2, 0.35)
        }
        let level = curved * beater
        guard level > 0.0001 else { return }
        addBandNoise(&buffer, amp: level * 0.9, lowHz: lowHz, highHz: highHz, tau: tau, sampleRate: sampleRate, seed: seed ^ 0xBEA7)
    }

    /// Same wire-band color on every layer, stronger on the quiet ones, so adjacent
    /// centroids stay within 35 % after the round-robin noise leaves 3–8 kHz.
    static func brightenQuieterSnareLayers(_ layers: inout [[[Float]]], sampleRate: Double, gain: Double = 1) {
        let last = layers.count - 1
        guard last > 0 else { return }
        for layer in 0..<last {
            // Four-layer banks need a small extra on the quieter layers. The top layer stays dry.
            let amp: Double
            if last == 3 {
                amp = [0.34, 0.28, 0.22][layer] * gain
            } else {
                amp = 0.22 * Double(last - layer) * gain
            }
            for rr in layers[layer].indices {
                addBandNoise(
                    &layers[layer][rr],
                    amp: amp,
                    lowHz: 3_000,
                    highHz: 8_000,
                    tau: 0.07,
                    sampleRate: sampleRate,
                    seed: 0xB11D ^ (UInt64(rr) &* 0x9E37) ^ (UInt64(layer) &* 0x85EB)
                )
            }
        }
    }

    private static func addBandNoise(
        _ buffer: inout [Float],
        amp: Double,
        lowHz: Double,
        highHz: Double,
        tau: Double,
        sampleRate: Double,
        seed: UInt64
    ) {
        guard amp > 0, !buffer.isEmpty else { return }
        var rng = UnitNoise(seed: seed == 0 ? 1 : seed)
        var low = Pole(cutoff: max(40, lowHz), sampleRate: sampleRate, lowpass: false)
        var high = Pole(cutoff: max(lowHz + 50, highHz), sampleRate: sampleRate, lowpass: true)
        let decay = exp(-1 / (max(0.004, tau) * sampleRate))
        var env = amp
        for index in buffer.indices {
            let noise = Float(rng.next())
            buffer[index] += high.process(low.process(noise)) * Float(env)
            env *= decay
        }
    }

    private static func addPartialCluster(
        _ buffer: inout [Float],
        lowHz: Double,
        highHz: Double,
        count: Int,
        amp: Double,
        tau: Double,
        sampleRate: Double,
        seed: UInt64
    ) {
        guard count > 0, highHz > lowHz else { return }
        var rng = UnitNoise(seed: seed == 0 ? 1 : seed)
        for _ in 0..<count {
            let unit = (rng.next() + 1) * 0.5
            let hz = lowHz + (highHz - lowHz) * unit
            addMode(&buffer, hz: hz, amp: amp, tau: tau, sampleRate: sampleRate, phase: unit)
        }
    }

    private static func addFM(
        _ buffer: inout [Float],
        carrier: Double,
        mod: Double,
        index: Double,
        tau: Double,
        sampleRate: Double
    ) {
        var carrierCycle = 0.0
        var modCycle = 0.0
        let decay = exp(-1 / (max(0.01, tau) * sampleRate))
        var env = 0.35
        for frame in buffer.indices {
            let modulator = sin(modCycle * 2 * Double.pi)
            let hz = carrier + mod * index * modulator
            buffer[frame] += Float(sin(carrierCycle * 2 * Double.pi) * env)
            carrierCycle += max(20, hz) / sampleRate
            if carrierCycle >= 1 { carrierCycle -= floor(carrierCycle) }
            modCycle += mod / sampleRate
            if modCycle >= 1 { modCycle -= floor(modCycle) }
            env *= decay
        }
    }

    /// Highs bloom over 30–80 ms, then fall. Quiet hits stay darker.
    private static func bloomHighs(
        _ buffer: inout [Float],
        velocity: Double,
        sampleRate: Double,
        seed: UInt64
    ) {
        var rng = UnitNoise(seed: seed == 0 ? 1 : seed)
        var low = Pole(cutoff: 5_000, sampleRate: sampleRate, lowpass: false)
        let rise = Int((0.03 + 0.05 * (1 - velocity)) * sampleRate)
        for index in buffer.indices {
            let t = Double(index) / sampleRate
            let open = min(1, Double(index) / Double(max(rise, 1)))
            let fall = exp(-t / (0.25 + 0.4 * velocity))
            let noise = low.process(Float(rng.next()))
            buffer[index] += noise * Float(open * fall * (0.14 + 0.16 * velocity))
        }
    }

    private static func highpass(_ buffer: inout [Float], cutoff: Double, sampleRate: Double) {
        var pole = Pole(cutoff: cutoff, sampleRate: sampleRate, lowpass: false)
        for index in buffer.indices { buffer[index] = pole.process(buffer[index]) }
    }

    private static func bandpass(_ buffer: inout [Float], lowHz: Double, highHz: Double, sampleRate: Double) {
        var low = Pole(cutoff: lowHz, sampleRate: sampleRate, lowpass: false)
        var high = Pole(cutoff: highHz, sampleRate: sampleRate, lowpass: true)
        for index in buffer.indices {
            buffer[index] = high.process(low.process(buffer[index]))
        }
    }

    nonisolated private struct Pole {
        var state: Float = 0
        let alpha: Float
        let lowpass: Bool

        init(cutoff: Double, sampleRate: Double, lowpass: Bool) {
            let hz = min(sampleRate * 0.45, max(10, cutoff))
            alpha = Float(exp(-2 * Double.pi * hz / sampleRate))
            self.lowpass = lowpass
        }

        mutating func process(_ input: Float) -> Float {
            let low = (1 - alpha) * input + alpha * state
            state = low
            return lowpass ? low : input - low
        }
    }

    nonisolated private struct UnitNoise {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 20_000) / 10_000 - 1
        }
    }
}
