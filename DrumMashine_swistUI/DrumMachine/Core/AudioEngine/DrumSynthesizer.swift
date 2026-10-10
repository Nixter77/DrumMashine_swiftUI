import Foundation
import Accelerate

/// Pure sample generators. Nonisolated so synthesis can run off the main actor.
nonisolated enum DrumSynthesizer {
    
    // MARK: - Core Utilities
    
    /// Peak at −6 dBFS, then a half-cosine tail so the buffer never ends mid-wave.
    /// The last sample is exactly zero (no DC step into the next voice).
    private static func finalize(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return samples }
        var copy = samples
        var maxVal: Float = 0
        vDSP_maxmgv(copy, 1, &maxVal, vDSP_Length(copy.count))

        if maxVal > 0.0001 {
            var scale = Float(0.5) / maxVal
            vDSP_vsmul(copy, 1, &scale, &copy, 1, vDSP_Length(copy.count))
        }

        let tenMilliseconds = Int(0.010 * sampleRate)
        let tenPercent = max(1, copy.count / 10)
        let fadeCount = min(copy.count, max(1, min(tenMilliseconds, tenPercent)))
        let fadeStart = copy.count - fadeCount
        let denom = Double(max(fadeCount - 1, 1))
        for i in 0..<fadeCount {
            let x = Double(i) / denom
            let gain = Float(0.5 * (1.0 + cos(.pi * x)))
            copy[fadeStart + i] *= gain
        }
        copy[copy.count - 1] = 0
        return copy
    }

    /// 0.5 ms ramp. Used where the raw wave does not start at zero (noise, squares).
    private static func applyAttack(_ samples: inout [Float], sampleRate: Double) {
        let count = min(samples.count, max(1, Int(0.0005 * sampleRate)))
        guard count > 1 else { return }
        let denom = Float(count - 1)
        for i in 0..<count {
            samples[i] *= Float(i) / denom
        }
    }

    /// How long a one-pole exponential needs to fall to −60 dB.
    private static func decayDuration(tau: Double, minimum: Double) -> Double {
        max(minimum, max(0.005, tau) * log(1000))
    }
    
    // MARK: - DSP Components
    
    /// Deterministic noise. Each render starts from the same seed, so tests can repeat.
    private struct Noise {
        var state: UInt64

        init(seed: UInt64 = 0xC0FFEE_D00D_F00D) {
            state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func next() -> Double {
            var x = state
            x ^= x << 13
            x ^= x >> 7
            x ^= x << 17
            if x == 0 { x = 0x9E3779B97F4A7C15 }
            state = x
            let unit = Double(x >> 11) / 9007199254740992.0
            return unit * 2 - 1
        }
    }

    /// PolyBLEP residual that pulls a naive square's step off the alias.
    private static func polyBLEP(_ phase: Double, _ dt: Double) -> Double {
        guard dt > 0 else { return 0 }
        if phase < dt {
            let x = phase / dt
            return x + x - x * x - 1
        }
        if phase > 1 - dt {
            let x = (phase - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }
    
    /// Simple One-Pole High Pass Filter
    nonisolated private struct OnePoleHPF {
        var y1: Double = 0
        var x1: Double = 0
        let alpha: Double
        
        init(cutoff: Double, sampleRate: Double) {
            let rc = 1.0 / (2.0 * .pi * cutoff)
            let dt = 1.0 / sampleRate
            self.alpha = rc / (rc + dt)
        }
        
        mutating func process(_ x: Double) -> Double {
            let y = alpha * (y1 + x - x1)
            x1 = x
            y1 = abs(y) < 1e-15 ? 0 : y
            return y1
        }
    }
    
    /// Simple One-Pole Low Pass Filter
    nonisolated private struct OnePoleLPF {
        var y1: Double = 0
        let alpha: Double
        
        init(cutoff: Double, sampleRate: Double) {
            let rc = 1.0 / (2.0 * .pi * cutoff)
            let dt = 1.0 / sampleRate
            self.alpha = dt / (rc + dt)
        }
        
        mutating func process(_ x: Double) -> Double {
            let y = y1 + alpha * (x - y1)
            y1 = abs(y) < 1e-15 ? 0 : y
            return y1
        }
    }

    /// Second-order section. State is flushed so Intel denormals do not stall the tail.
    private struct Biquad {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = abs(y) < 1e-15 ? 0 : y
            return y1
        }

        static func highpass(cutoff: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
            section(cutoff: cutoff, sampleRate: sampleRate, q: q, kind: .highpass)
        }

        static func lowpass(cutoff: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
            var hp = section(cutoff: cutoff, sampleRate: sampleRate, q: q, kind: .highpass)
            let w0 = 2 * Double.pi * min(max(20, cutoff), max(1, sampleRate * 0.45)) / sampleRate
            let cosine = cos(w0)
            let alpha = sin(w0) / (2 * max(0.1, q))
            let a0 = 1 + alpha
            hp.b0 = (1 - cosine) / 2 / a0
            hp.b1 = (1 - cosine) / a0
            hp.b2 = (1 - cosine) / 2 / a0
            return hp
        }

        static func bandpass(cutoff: Double, sampleRate: Double, q: Double = 1) -> Biquad {
            section(cutoff: cutoff, sampleRate: sampleRate, q: q, kind: .bandpass)
        }

        private enum Kind { case highpass, bandpass }

        private static func section(cutoff: Double, sampleRate: Double, q: Double, kind: Kind) -> Biquad {
            let nyquist = max(1, sampleRate * 0.45)
            let freq = min(max(20, cutoff), nyquist)
            let w0 = 2 * Double.pi * freq / sampleRate
            let cosine = cos(w0)
            let sine = sin(w0)
            let alpha = sine / (2 * max(0.1, q))
            let a0 = 1 + alpha
            var filter = Biquad()
            switch kind {
            case .highpass:
                filter.b0 = (1 + cosine) / 2 / a0
                filter.b1 = -(1 + cosine) / a0
                filter.b2 = (1 + cosine) / 2 / a0
            case .bandpass:
                filter.b0 = alpha / a0
                filter.b1 = 0
                filter.b2 = -alpha / a0
            }
            filter.a1 = -2 * cosine / a0
            filter.a2 = (1 - alpha) / a0
            return filter
        }
    }
    
    /// Peak-normalized buffer. Lo-fi runs first, and a nil chain leaves the samples untouched.
    private static func finish(_ samples: [Float], sampleRate: Double, lofi: SynthParams.LoFi?) -> [Float] {
        guard let lofi, lofiIsActive(lofi) else {
            return finalize(samples, sampleRate: sampleRate)
        }
        var copy = samples
        applyLoFi(&copy, lofi)
        return finalize(copy, sampleRate: sampleRate)
    }

    private static func lofiIsActive(_ lofi: SynthParams.LoFi) -> Bool {
        if let depth = lofi.bitDepth, depth >= 2 { return true }
        if let down = lofi.downsample, down > 1 { return true }
        if let saturation = lofi.saturation, saturation > 0 { return true }
        return false
    }

    /// Quantize last so an 8-bit setting stays inside 256 codes before `finalize` scales it.
    private static func applyLoFi(_ samples: inout [Float], _ lofi: SynthParams.LoFi) {
        if let saturation = lofi.saturation, saturation > 0 {
            let drive = 1 + saturation * 4
            for index in samples.indices {
                samples[index] = Float(tanh(Double(samples[index]) * drive))
            }
        }
        if let hold = lofi.downsample, hold > 1, !samples.isEmpty {
            var kept = samples[0]
            for index in samples.indices {
                if index % hold == 0 { kept = samples[index] }
                samples[index] = kept
            }
        }
        if let depth = lofi.bitDepth, depth >= 2, depth <= 16 {
            let codes = Double((1 << depth) - 1)
            for index in samples.indices {
                let clamped = min(1, max(-1, Double(samples[index])))
                let unit = (clamped + 1) * 0.5
                let quantized = (unit * codes).rounded() / codes
                samples[index] = Float(quantized * 2 - 1)
            }
        }
    }

    /// Generator plus lo-fi, before the −6 dBFS normalize. Tests count quantizer levels here.
    static func samplesBeforeNormalize(for preset: SoundPreset, sampleRate: Double) -> [Float] {
        var raw = rawVoice(preset, sampleRate: sampleRate)
        if let lofi = preset.synth?.lofi, lofiIsActive(lofi) {
            applyLoFi(&raw, lofi)
        }
        return raw
    }

    // MARK: - Generators
    
    /// Generates a punchy Kick drum (Sine sweep + Click)
    static func generateKick(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Kick? = nil
    ) -> [Float] {
        if let params, kickHasOverride(params) {
            return tunedKick(sampleRate: sampleRate, decay: decay, pitchMod: pitchMod, params: params)
        }
        let tau = max(0.005, decay * 0.4)
        let duration = decayDuration(tau: tau, minimum: 0.2)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        // Frequencies
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let fStart = 150.0 * pitchFactor
        let fEnd = 50.0 * pitchFactor
        let pitchDecay = 0.08
        
        // Phase accumulator
        var phase: Double = 0
        var rng = Noise(seed: 0xA11C_E001)
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            // 1. Frequency Envelope (Exponential decay)
            let freq = fEnd + (fStart - fEnd) * exp(-t / pitchDecay)
            
            // 2. Increment Phase
            phase += freq / sampleRate
            if phase > 1.0 { phase -= 1.0 }
            
            // 3. Oscillator (Sine)
            var signal = sin(2.0 * .pi * phase)
            
            // 4. Click Transient (First 10ms)
            if t < 0.010 {
                let clickEnv = (0.010 - t) / 0.010
                signal += rng.next() * clickEnv * 0.5
            }
            
            // 5. Amplitude Envelope (Exponential)
            let amp = exp(-t / tau)
            
            // 6. Distortion / Saturation (Clip)
            signal = tanh(signal * 1.5)
            
            buffer[i] = Float(signal * amp)
        }

        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }

    private static func kickHasOverride(_ params: SynthParams.Kick) -> Bool {
        params.startHz != nil || params.endHz != nil || params.sweep != nil
            || params.click != nil || params.clickMs != nil || params.drive != nil
            || (params.noise ?? 0) > 0
    }

    private static func tunedKick(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Kick
    ) -> [Float] {
        let tau = max(0.005, decay * 0.4)
        let duration = decayDuration(tau: tau, minimum: 0.2)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let fStart = (params.startHz ?? 150.0) * pitchFactor
        let fEnd = (params.endHz ?? 50.0) * pitchFactor
        let pitchDecay = max(0.001, params.sweep ?? 0.08)
        let clickLevel = params.click ?? 0.5
        let clickWindow = max(0.001, (params.clickMs ?? 10) / 1000.0)
        let drive = params.drive ?? 1.5
        let noiseLevel = params.noise ?? 0
        var phase: Double = 0
        var rng = Noise(seed: 0xA11C_E001)
        var beater = Biquad.bandpass(cutoff: 3_000, sampleRate: sampleRate, q: 1)
        var beaterRng = Noise(seed: 0xB3A7_0001)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let freq = fEnd + (fStart - fEnd) * exp(-t / pitchDecay)
            phase += freq / sampleRate
            if phase > 1.0 { phase -= 1.0 }
            var signal = sin(2.0 * .pi * phase)
            if t < clickWindow {
                let clickEnv = (clickWindow - t) / clickWindow
                signal += rng.next() * clickEnv * clickLevel
            }
            if noiseLevel > 0 {
                signal += beater.process(beaterRng.next()) * noiseLevel
            }
            signal = tanh(signal * drive)
            buffer[i] = Float(signal * exp(-t / tau))
        }
        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }
    
    /// Generates a Snare (Dual-Tone + Filtered Noise)
    static func generateSnare(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Snare? = nil
    ) -> [Float] {
        if let params, snareHasOverride(params) {
            return tunedSnare(sampleRate: sampleRate, decay: decay, pitchMod: pitchMod, params: params)
        }
        let noiseTau = max(0.005, decay * 0.8)
        let tau = max(0.15, noiseTau)
        let duration = decayDuration(tau: tau, minimum: 0.2)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let tone1 = 180.0 * pitchFactor
        let tone2 = 330.0 * pitchFactor
        
        var hpFilter = OnePoleHPF(cutoff: 1000.0, sampleRate: sampleRate)
        var rng = Noise(seed: 0x5AA3_E001)
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            // 1. Tonal Body (Two sines decaying fast)
            let bodyEnv = exp(-t / 0.15)
            let body = (sin(2 * .pi * tone1 * t) * 0.5 + sin(2 * .pi * tone2 * t) * 0.3) * bodyEnv
            
            // 2. Noise Wires (Broad spectrum noise)
            var wires = rng.next()
            
            // 3. Filter Noise (High Pass)
            wires = hpFilter.process(wires)
            
            // 4. Noise Envelope (Decays slower than body)
            let wiresEnv = exp(-t / noiseTau)
            
            let signal = body + (wires * wiresEnv * 0.8)
            buffer[i] = Float(signal)
        }

        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }

    private static func snareHasOverride(_ params: SynthParams.Snare) -> Bool {
        params.tone1Hz != nil || params.tone2Hz != nil || params.tone1Level != nil
            || params.tone2Level != nil || params.bodyTau != nil || params.noiseHPHz != nil
            || params.noiseLevel != nil
    }

    private static func tunedSnare(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Snare
    ) -> [Float] {
        let bodyTau = max(0.005, params.bodyTau ?? 0.15)
        let noiseTau = max(0.005, decay * 0.8)
        let tau = max(bodyTau, noiseTau)
        let duration = decayDuration(tau: tau, minimum: 0.2)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let tone1 = (params.tone1Hz ?? 180.0) * pitchFactor
        let tone2 = (params.tone2Hz ?? 330.0) * pitchFactor
        let level1 = params.tone1Level ?? 0.5
        let level2 = params.tone2Level ?? 0.3
        let noiseLevel = params.noiseLevel ?? 0.8
        var hpFilter = OnePoleHPF(cutoff: params.noiseHPHz ?? 1000.0, sampleRate: sampleRate)
        var rng = Noise(seed: 0x5AA3_E001)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let bodyEnv = exp(-t / bodyTau)
            let body = (sin(2 * .pi * tone1 * t) * level1 + sin(2 * .pi * tone2 * t) * level2) * bodyEnv
            let wires = hpFilter.process(rng.next())
            let wiresEnv = exp(-t / noiseTau)
            buffer[i] = Float(body + wires * wiresEnv * noiseLevel)
        }
        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }
    
    /// Generates a Hi-Hat (6-Oscillator Metallic Noise + Bandpass)
    static func generateHiHat(
        sampleRate: Double,
        decay: Double,
        isOpen: Bool = false,
        pitchMod: Double = 0,
        params: SynthParams.Hat? = nil
    ) -> [Float] {
        if let params, hatHasOverride(params) {
            return tunedHat(sampleRate: sampleRate, decay: decay, isOpen: isOpen, pitchMod: pitchMod, params: params)
        }
        let tau = max(0.005, isOpen ? decay : decay * 0.2)
        let duration = decayDuration(tau: tau, minimum: isOpen ? 0.5 : 0.1)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let freqs = [263.0, 400.0, 421.0, 474.0, 587.0, 845.0].map { $0 * pitchFactor }
        var phases = [Double](repeating: 0, count: freqs.count)
        
        // Second-order highpass plus a bandpass keep the square fundamentals out of the hat.
        var hpf = Biquad.highpass(cutoff: 8_000, sampleRate: sampleRate)
        var band = Biquad.bandpass(cutoff: 10_000, sampleRate: sampleRate, q: 0.8)
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            var metal: Double = 0
            for j in 0..<freqs.count {
                let dt = freqs[j] / sampleRate
                phases[j] += dt
                if phases[j] >= 1.0 { phases[j] -= 1.0 }
                let naive = phases[j] < 0.5 ? 1.0 : -1.0
                let wrapped = (phases[j] + 0.5).truncatingRemainder(dividingBy: 1)
                metal += naive + polyBLEP(phases[j], dt) - polyBLEP(wrapped, dt)
            }
            
            metal = hpf.process(metal)
            metal = band.process(metal)
            
            // 3. Amplitude Envelope
            let amp = exp(-t / tau)
            
            buffer[i] = Float(metal * amp)
        }

        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }

    private static func hatHasOverride(_ params: SynthParams.Hat) -> Bool {
        params.hpHz != nil || params.bandHz != nil || params.bandQ != nil || (params.noiseMix ?? 0) > 0
    }

    private static func tunedHat(
        sampleRate: Double,
        decay: Double,
        isOpen: Bool,
        pitchMod: Double,
        params: SynthParams.Hat
    ) -> [Float] {
        let tau = max(0.005, isOpen ? decay : decay * 0.2)
        let duration = decayDuration(tau: tau, minimum: isOpen ? 0.5 : 0.1)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let freqs = [263.0, 400.0, 421.0, 474.0, 587.0, 845.0].map { $0 * pitchFactor }
        var phases = [Double](repeating: 0, count: freqs.count)
        var hpf = Biquad.highpass(cutoff: params.hpHz ?? 8_000, sampleRate: sampleRate)
        var band = Biquad.bandpass(cutoff: params.bandHz ?? 10_000, sampleRate: sampleRate, q: params.bandQ ?? 0.8)
        let noiseMix = params.noiseMix ?? 0
        var rng = Noise(seed: 0x4A77_0001)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            var metal: Double = 0
            for j in 0..<freqs.count {
                let dt = freqs[j] / sampleRate
                phases[j] += dt
                if phases[j] >= 1.0 { phases[j] -= 1.0 }
                let naive = phases[j] < 0.5 ? 1.0 : -1.0
                let wrapped = (phases[j] + 0.5).truncatingRemainder(dividingBy: 1)
                metal += naive + polyBLEP(phases[j], dt) - polyBLEP(wrapped, dt)
            }
            if noiseMix > 0 {
                metal += rng.next() * noiseMix
            }
            metal = hpf.process(metal)
            metal = band.process(metal)
            buffer[i] = Float(metal * exp(-t / tau))
        }
        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }
    
    /// Generates a Clap (Multiple burst noise)
    static func generateClap(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Clap? = nil
    ) -> [Float] {
        if let params, clapHasOverride(params) {
            return tunedClap(sampleRate: sampleRate, decay: decay, pitchMod: pitchMod, params: params)
        }
        let tau = max(0.005, decay * 0.5)
        let duration = decayDuration(tau: tau, minimum: 0.3)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        // Bandpass filter for clap character (approx 1kHz - 2kHz)
        // Tune shifts the clap's band (noise has no pitch of its own). 0 st leaves it as before.
        let clapShift = pow(2.0, pitchMod / 12.0)
        var hpf = OnePoleHPF(cutoff: 800.0 * clapShift, sampleRate: sampleRate)
        var lpf = OnePoleLPF(cutoff: 2500.0 * clapShift, sampleRate: sampleRate)
        
        // Burst definition: time in seconds
        let bursts = [0.000, 0.012, 0.024]
        var rng = Noise(seed: 0xC1A9_0001)
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            // 1. Generate Noise
            var noiseSig = rng.next()
            
            // 2. Filter Noise
            noiseSig = hpf.process(noiseSig)
            noiseSig = lpf.process(noiseSig)
            
            // 3. Apply Multi-Burst Envelope
            var amp: Double = 0
            
            // Sum amps from each burst
            for burstTime in bursts {
                if t >= burstTime {
                    let localT = t - burstTime
                    // Sharp attack, fast decay
                    if localT < 0.040 { // 40ms bursts
                        amp += exp(-localT * 100.0) // Fast decay
                    }
                }
            }
            
            // Add a tail reverb-like decay starting after last burst
            if t > 0.030 {
                let tailT = t - 0.030
                amp += exp(-tailT / tau) * 0.4
            }
            
            // Clip amplitude to avoid excessive gain
            amp = min(1.0, amp)
            
            buffer[i] = Float(noiseSig * amp)
        }

        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }

    private static func clapHasOverride(_ params: SynthParams.Clap) -> Bool {
        params.bursts != nil || params.spacing != nil || params.hpHz != nil
            || params.lpHz != nil || params.tailLevel != nil
    }

    private static func tunedClap(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Clap
    ) -> [Float] {
        let clapShift = pow(2.0, pitchMod / 12.0)
        let tau = max(0.005, decay * 0.5)
        let duration = decayDuration(tau: tau, minimum: 0.3)
        let count = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: count)
        var hpf = OnePoleHPF(cutoff: (params.hpHz ?? 800.0) * clapShift, sampleRate: sampleRate)
        var lpf = OnePoleLPF(cutoff: (params.lpHz ?? 2500.0) * clapShift, sampleRate: sampleRate)
        let burstCount = max(1, params.bursts ?? 3)
        let spacing = params.spacing ?? 0.012
        let bursts = (0..<burstCount).map { Double($0) * spacing }
        let tailLevel = params.tailLevel ?? 0.4
        var rng = Noise(seed: 0xC1A9_0001)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let noiseSig = lpf.process(hpf.process(rng.next()))
            var amp: Double = 0
            for burstTime in bursts where t >= burstTime {
                let localT = t - burstTime
                if localT < 0.040 {
                    amp += exp(-localT * 100.0)
                }
            }
            if t > 0.030 {
                amp += exp(-(t - 0.030) / tau) * tailLevel
            }
            amp = min(1.0, amp)
            buffer[i] = Float(noiseSig * amp)
        }
        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }
    
    /// Generates a Tom (Pitch sweep sine with resonance)
    static func generateTom(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Tom? = nil
    ) -> [Float] {
        if let params, tomHasOverride(params) {
            return tunedTom(sampleRate: sampleRate, decay: decay, pitchMod: pitchMod, params: params)
        }
        let tau = max(0.005, decay * 0.6)
        let duration = decayDuration(tau: tau, minimum: 0.4)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let fStart = 200.0 * pitchFactor
        let fEnd = 80.0 * pitchFactor
        
        var phase: Double = 0
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            // Same exponential fall as the kick, then it sits on the low note.
            let freq = fEnd + (fStart - fEnd) * exp(-t / 0.07)
            let effectiveFreq = max(fEnd, freq)
            
            phase += effectiveFreq / sampleRate
            if phase > 1.0 { phase -= 1.0 }
            
            // Sine
            let val = sin(2 * .pi * phase)
            
            // Amp Envelope
            let amp = exp(-t / tau)
            
            buffer[i] = Float(val * amp)
        }

        return buffer
    }

    private static func tomHasOverride(_ params: SynthParams.Tom) -> Bool {
        params.startHz != nil || params.endHz != nil || params.sweep != nil || (params.stickNoise ?? 0) > 0
    }

    private static func tunedTom(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Tom
    ) -> [Float] {
        let tau = max(0.005, decay * 0.6)
        let duration = decayDuration(tau: tau, minimum: 0.4)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let fStart = (params.startHz ?? 200.0) * pitchFactor
        let fEnd = (params.endHz ?? 80.0) * pitchFactor
        let sweep = max(0.001, params.sweep ?? 0.07)
        let stick = params.stickNoise ?? 0
        var phase: Double = 0
        var rng = Noise(seed: 0x70E0_0001)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let freq = fEnd + (fStart - fEnd) * exp(-t / sweep)
            let effectiveFreq = max(fEnd, freq)
            phase += effectiveFreq / sampleRate
            if phase > 1.0 { phase -= 1.0 }
            var val = sin(2 * .pi * phase)
            if stick > 0, t < 0.012 {
                val += rng.next() * stick * (1 - t / 0.012)
            }
            buffer[i] = Float(val * exp(-t / tau))
        }
        return buffer
    }
    
    /// Generates a Crash Cymbal (Inharmonic FM + Noise)
    static func generateCrash(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double = 0,
        params: SynthParams.Crash? = nil
    ) -> [Float] {
        if let params, crashHasOverride(params) {
            return tunedCrash(sampleRate: sampleRate, decay: decay, pitchMod: pitchMod, params: params)
        }
        let tau = max(0.005, decay * 0.5)
        let duration = decayDuration(tau: tau, minimum: 1.5)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        var hpf = OnePoleHPF(cutoff: 2000.0, sampleRate: sampleRate)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let carrier = 300.0 * pitchFactor
        let modulator = 412.0 * pitchFactor
        var rng = Noise(seed: 0xC3A5_0001)
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            let fm = sin(2 * .pi * carrier * t + 5.0 * sin(2 * .pi * modulator * t))
            
            // White Noise
            let n = rng.next()
            
            // Mix
            var sig = (fm * 0.3) + (n * 0.7)
            
            // Filter High Pass
            sig = hpf.process(sig)
            
            // Envelope
            let amp = exp(-t / tau)
            
            buffer[i] = Float(sig * amp)
        }

        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }

    private static func crashHasOverride(_ params: SynthParams.Crash) -> Bool {
        params.carrierHz != nil || params.modHz != nil || params.index != nil
            || params.fmMix != nil || params.hpHz != nil
    }

    private static func tunedCrash(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Crash
    ) -> [Float] {
        let tau = max(0.005, decay * 0.5)
        let duration = decayDuration(tau: tau, minimum: 1.5)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        var hpf = OnePoleHPF(cutoff: params.hpHz ?? 2000.0, sampleRate: sampleRate)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let carrier = (params.carrierHz ?? 300.0) * pitchFactor
        let modulator = (params.modHz ?? 412.0) * pitchFactor
        let index = params.index ?? 5.0
        let fmMix = params.fmMix ?? 0.3
        let noiseMix = params.fmMix.map { 1 - $0 } ?? 0.7
        var rng = Noise(seed: 0xC3A5_0001)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let fm = sin(2 * .pi * carrier * t + index * sin(2 * .pi * modulator * t))
            var sig = (fm * fmMix) + (rng.next() * noiseMix)
            sig = hpf.process(sig)
            buffer[i] = Float(sig * exp(-t / tau))
        }
        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }
    
    /// Generates Percussion (FM Woodblock / Bongo)
    static func generatePerc(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Perc? = nil
    ) -> [Float] {
        if let params, percHasOverride(params) {
            return tunedPerc(sampleRate: sampleRate, decay: decay, pitchMod: pitchMod, params: params)
        }
        let tau = max(0.005, decay * 0.4)
        let duration = decayDuration(tau: tau, minimum: 0.2)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let carrierF = 800.0 * pitchFactor
        let modulatorF = carrierF * 1.43 // Inharmonic
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            // FM
            // Modulation Index decays fast (impact sound)
            let modIndex = 3.0 * exp(-t * 20.0)
            
            let val = sin(2 * .pi * carrierF * t + modIndex * sin(2 * .pi * modulatorF * t))
            
            // Amp
            let amp = exp(-t / tau)
            
            buffer[i] = Float(val * amp)
        }

        return buffer
    }

    private static func percHasOverride(_ params: SynthParams.Perc) -> Bool {
        if let mode = params.mode, mode != .fm { return true }
        return params.carrierHz != nil || params.secondHz != nil || params.ratio != nil
            || params.index != nil || params.indexDecay != nil || params.bandHz != nil
            || params.bandQ != nil || params.bursts != nil || params.spacing != nil
    }

    private static func tunedPerc(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Perc
    ) -> [Float] {
        let mode = params.mode ?? .fm
        let tau = max(0.005, decay * 0.4)
        let minimum = mode == .noise ? 0.15 : 0.2
        let duration = decayDuration(tau: tau, minimum: minimum)
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        switch mode {
        case .cowbell:
            let first = (params.carrierHz ?? 540) * pitchFactor
            let second = (params.secondHz ?? (params.carrierHz ?? 540) * (params.ratio ?? (800.0 / 540.0))) * pitchFactor
            var phaseA = 0.0
            var phaseB = 0.0
            var band = Biquad.bandpass(
                cutoff: params.bandHz ?? 2640,
                sampleRate: sampleRate,
                q: params.bandQ ?? 1.5
            )
            for i in 0..<samples {
                let t = Double(i) / sampleRate
                let dtA = first / sampleRate
                let dtB = second / sampleRate
                phaseA += dtA
                phaseB += dtB
                if phaseA >= 1 { phaseA -= 1 }
                if phaseB >= 1 { phaseB -= 1 }
                let squareA = (phaseA < 0.5 ? 1.0 : -1.0) + polyBLEP(phaseA, dtA) - polyBLEP((phaseA + 0.5).truncatingRemainder(dividingBy: 1), dtA)
                let squareB = (phaseB < 0.5 ? 1.0 : -1.0) + polyBLEP(phaseB, dtB) - polyBLEP((phaseB + 0.5).truncatingRemainder(dividingBy: 1), dtB)
                let sig = band.process((squareA + squareB) * 0.5)
                buffer[i] = Float(sig * exp(-t / tau))
            }
        case .noise:
            let bursts = max(1, params.bursts ?? 1)
            let spacing = params.spacing ?? 0.015
            var band = Biquad.bandpass(
                cutoff: (params.bandHz ?? 6000) * pitchFactor,
                sampleRate: sampleRate,
                q: params.bandQ ?? 1.5
            )
            var rng = Noise(seed: 0x5A4E_0001)
            for i in 0..<samples {
                let t = Double(i) / sampleRate
                var amp = 0.0
                for burst in 0..<bursts {
                    let start = Double(burst) * spacing
                    if t >= start {
                        amp += exp(-(t - start) * 80)
                    }
                }
                amp = min(1, amp)
                buffer[i] = Float(band.process(rng.next()) * amp * exp(-t / tau))
            }
        case .fm:
            let carrierF = (params.carrierHz ?? 800.0) * pitchFactor
            let ratio = params.ratio ?? 1.43
            let modulatorF = carrierF * ratio
            let index = params.index ?? 3.0
            let indexDecay = params.indexDecay ?? 20.0
            for i in 0..<samples {
                let t = Double(i) / sampleRate
                let modIndex = index * exp(-t * indexDecay)
                let val = sin(2 * .pi * carrierF * t + modIndex * sin(2 * .pi * modulatorF * t))
                buffer[i] = Float(val * exp(-t / tau))
            }
        }
        return buffer
    }
    
    /// Generates Ride Cymbal (Ping + Noise)
    static func generateRide(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double = 0,
        params: SynthParams.Ride? = nil
    ) -> [Float] {
        if let params, rideHasOverride(params) {
            return tunedRide(sampleRate: sampleRate, decay: decay, pitchMod: pitchMod, params: params)
        }
        // Sizzle is the long envelope: exp(-t * 2), so tau = 0.5 s.
        let duration = decayDuration(tau: 0.5, minimum: max(1.0, decay))
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        
        // Bandpass for ping
        var bpf_hpf = OnePoleHPF(cutoff: 3000.0, sampleRate: sampleRate)
        var bpf_lpf = OnePoleLPF(cutoff: 6000.0, sampleRate: sampleRate)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let pingFrequency = 5000.0 * pitchFactor
        let pingModulator = 720.0 * pitchFactor
        var rng = Noise(seed: 0x31DE_0001)
        
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            
            let ping = sin(2 * .pi * pingFrequency * t + 0.5 * sin(2 * .pi * pingModulator * t))
            
            // Sizzle (Noise)
            let sizzle = rng.next()
            
            // Mix: Ping is prominent initially, sizzle sustains
            let pingEnv = exp(-t * 10.0)
            let sizzleEnv = exp(-t * 2.0)
            
            var sig = (ping * pingEnv * 0.6) + (sizzle * sizzleEnv * 0.4)
            
            // Filter
            sig = bpf_hpf.process(sig)
            sig = bpf_lpf.process(sig)
            
            buffer[i] = Float(sig)
        }

        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }

    private static func rideHasOverride(_ params: SynthParams.Ride) -> Bool {
        params.pingHz != nil || params.pingModHz != nil || params.pingLevel != nil
            || params.sizzleLevel != nil || params.sizzleTau != nil || params.hpHz != nil
            || params.lpHz != nil
    }

    private static func tunedRide(
        sampleRate: Double,
        decay: Double,
        pitchMod: Double,
        params: SynthParams.Ride
    ) -> [Float] {
        let sizzleTau = max(0.05, params.sizzleTau ?? 0.5)
        let duration = decayDuration(tau: sizzleTau, minimum: max(1.0, decay))
        let samples = Int(sampleRate * duration)
        var buffer = [Float](repeating: 0, count: samples)
        var bpfHPF = OnePoleHPF(cutoff: params.hpHz ?? 3000.0, sampleRate: sampleRate)
        var bpfLPF = OnePoleLPF(cutoff: params.lpHz ?? 6000.0, sampleRate: sampleRate)
        let pitchFactor = pow(2.0, pitchMod / 12.0)
        let pingFrequency = (params.pingHz ?? 5000.0) * pitchFactor
        let pingModulator = (params.pingModHz ?? 720.0) * pitchFactor
        let pingLevel = params.pingLevel ?? 0.6
        let sizzleLevel = params.sizzleLevel ?? 0.4
        var rng = Noise(seed: 0x31DE_0001)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let ping = sin(2 * .pi * pingFrequency * t + 0.5 * sin(2 * .pi * pingModulator * t))
            let sizzle = rng.next()
            let pingEnv = exp(-t * 10.0)
            let sizzleEnv = params.sizzleTau == nil ? exp(-t * 2.0) : exp(-t / sizzleTau)
            var sig = (ping * pingEnv * pingLevel) + (sizzle * sizzleEnv * sizzleLevel)
            sig = bpfHPF.process(sig)
            sig = bpfLPF.process(sig)
            buffer[i] = Float(sig)
        }
        applyAttack(&buffer, sampleRate: sampleRate)
        return buffer
    }

    /// The eight voices created at launch, before the user picks a preset.
    static func startupSamples(track index: Int, sampleRate: Double) -> [Float] {
        let raw: [Float]
        switch index {
        case 0:
            raw = generateKick(sampleRate: sampleRate, decay: 0.35, pitchMod: 0)
        case 1:
            raw = generateSnare(sampleRate: sampleRate, decay: 0.18, pitchMod: 0)
        case 2:
            raw = generateHiHat(sampleRate: sampleRate, decay: 0.05, isOpen: false)
        case 3:
            raw = generateClap(sampleRate: sampleRate, decay: 0.25, pitchMod: 0)
        case 4:
            raw = generateTom(sampleRate: sampleRate, decay: 0.35, pitchMod: 0)
        case 5:
            raw = generateRide(sampleRate: sampleRate, decay: 0.8)
        case 6:
            raw = generateCrash(sampleRate: sampleRate, decay: 0.8)
        default:
            raw = generatePerc(sampleRate: sampleRate, decay: 0.08, pitchMod: 0)
        }
        return finish(raw, sampleRate: sampleRate, lofi: nil)
    }

    /// Tone filter and level, run on the render thread (never the audio thread).
    /// Peak stays at or below the 0.5 the buffer already had.
    static func applyToneAndLevel(_ buffer: inout [Float], preset: SoundPreset, sampleRate: Double) {
        guard !buffer.isEmpty, sampleRate > 0 else { return }
        let tone = Double(min(max(preset.toneFilter ?? 0, -1), 1))
        if abs(tone) > 0.01 {
            let before = buffer.reduce(Float(0)) { max($0, abs($1)) }
            var filter = tone < 0
                ? Biquad.lowpass(cutoff: 18_000 * pow(0.02, -tone), sampleRate: sampleRate)
                : Biquad.highpass(cutoff: 30 * pow(100, tone), sampleRate: sampleRate)
            for i in buffer.indices {
                buffer[i] = Float(filter.process(Double(buffer[i])))
            }
            let after = buffer.reduce(Float(0)) { max($0, abs($1)) }
            if after > 0.0001, before > 0 {
                var scale = before / after
                vDSP_vsmul(buffer, 1, &scale, &buffer, 1, vDSP_Length(buffer.count))
            }
        }
        var level = min(max(preset.volume, 0), 1)
        if level < 1 {
            vDSP_vsmul(buffer, 1, &level, &buffer, 1, vDSP_Length(buffer.count))
        }
    }

    /// One entry point for every preset the library and the engine play.
    /// Generators own the drum decay. ADSR then shapes attack, the drop to sustain, and the tail.
    static func samples(
        for preset: SoundPreset,
        sampleRate: Double,
        sampleRoot: URL? = nil
    ) -> [Float] {
        if case .sample(let fileName, _) = preset.source {
            let root = sampleRoot ?? URL(fileURLWithPath: "/dev/null")
            var raw = SampleImporter.render(
                fileName: fileName,
                sampleRoot: root,
                sampleRate: sampleRate,
                pitch: preset.pitch
            )
            if raw.isEmpty { raw = [0] }
            var buffer = finalize(raw, sampleRate: sampleRate)
            applyToneAndLevel(&buffer, preset: preset, sampleRate: sampleRate)
            applyADSR(&buffer, preset: preset, sampleRate: sampleRate)
            return buffer
        }
        if case .bundled(let fileName) = preset.source {
            guard let url = BundledSamples.url(for: fileName) else { return [0] }
            var raw = SampleImporter.render(
                fileName: url.lastPathComponent,
                sampleRoot: url.deletingLastPathComponent(),
                sampleRate: sampleRate,
                pitch: preset.pitch
            )
            if raw.isEmpty { raw = [0] }
            var buffer = finalize(raw, sampleRate: sampleRate)
            applyToneAndLevel(&buffer, preset: preset, sampleRate: sampleRate)
            applyADSR(&buffer, preset: preset, sampleRate: sampleRate)
            return buffer
        }
        var buffer = renderedVoice(preset, sampleRate: sampleRate)
        applyToneAndLevel(&buffer, preset: preset, sampleRate: sampleRate)
        applyADSR(&buffer, preset: preset, sampleRate: sampleRate)
        return buffer
    }

    private static func renderedVoice(_ preset: SoundPreset, sampleRate: Double) -> [Float] {
        finish(rawVoice(preset, sampleRate: sampleRate), sampleRate: sampleRate, lofi: preset.synth?.lofi)
    }

    private static func rawVoice(_ preset: SoundPreset, sampleRate: Double) -> [Float] {
        let decay = Double(preset.decay)
        let pitch = Double(preset.pitch)
        let synth = preset.synth
        let hatOpen = synth?.hat?.open ?? (decay > 0.15)

        switch preset.resolvedVoice {
        case .kick:
            return generateKick(sampleRate: sampleRate, decay: decay, pitchMod: pitch, params: synth?.kick)
        case .snare:
            return generateSnare(sampleRate: sampleRate, decay: decay, pitchMod: pitch, params: synth?.snare)
        case .closedHat, .openHat:
            return generateHiHat(
                sampleRate: sampleRate,
                decay: decay,
                isOpen: hatOpen,
                pitchMod: pitch,
                params: synth?.hat
            )
        case .clap:
            return generateClap(sampleRate: sampleRate, decay: decay, pitchMod: pitch, params: synth?.clap)
        case .tom:
            return generateTom(sampleRate: sampleRate, decay: decay, pitchMod: pitch, params: synth?.tom)
        case .ride:
            return generateRide(sampleRate: sampleRate, decay: decay, pitchMod: pitch, params: synth?.ride)
        case .crash:
            return generateCrash(sampleRate: sampleRate, decay: decay, pitchMod: pitch, params: synth?.crash)
        case .perc:
            return generatePerc(sampleRate: sampleRate, decay: decay, pitchMod: pitch, params: synth?.perc)
        case .fx:
            return generateFX(sampleRate: sampleRate, preset: preset)
        }
    }

    /// Attack rises to full, decay falls to sustain, release ends the tail at zero.
    /// Drums have no held sustain stage: the hold exists only when decay finishes before the tail.
    /// The generator already faded the last 10 ms, and the last sample stays zero.
    private static func applyADSR(_ samples: inout [Float], preset: SoundPreset, sampleRate: Double) {
        let count = samples.count
        guard count > 1, sampleRate > 0 else { return }
        let sustain = min(1, max(0, preset.sustain))
        let attack = min(count - 1, max(0, Int((Double(max(0, preset.attack)) * sampleRate).rounded())))
        let decay = min(count, max(0, Int((Double(max(0, preset.decay)) * sampleRate).rounded())))
        let release = min(count - 1, max(0, Int((Double(max(0, preset.release)) * sampleRate).rounded())))
        let releaseStart = count - release

        func bodyGain(_ index: Int) -> Float {
            if attack > 0, index < attack {
                return Float(index) / Float(attack)
            }
            let intoDecay = index - attack
            if decay > 0, intoDecay < decay {
                let progress = Float(intoDecay) / Float(decay)
                return 1 - (1 - sustain) * progress
            }
            return sustain
        }

        let releaseLevel = release > 0 ? bodyGain(releaseStart) : 0
        let releaseSpan = Float(max(release - 1, 1))
        for index in 0..<count {
            var gain = bodyGain(index)
            if release > 0, index >= releaseStart {
                let progress = min(1, Float(index - releaseStart) / releaseSpan)
                gain = releaseLevel * (1 - progress)
            }
            samples[index] *= gain
        }
        samples[count - 1] = 0
    }

    /// FX voices. Amplitude time constants match the previous curves.
    private static func generateFX(sampleRate: Double, preset: SoundPreset) -> [Float] {
        let name = preset.filename
        let ampRate: Double
        let noisy: Bool
        if name.contains("zap") {
            ampRate = 10
            noisy = false
        } else if name.contains("laser") {
            ampRate = 5
            noisy = false
        } else if name.contains("blip") {
            ampRate = 40
            noisy = false
        } else if name.contains("sweep_up") || name.contains("sweep_dn") {
            ampRate = 2
            noisy = false
        } else {
            ampRate = 10
            noisy = true
        }
        let duration = decayDuration(tau: 1.0 / ampRate, minimum: 0.05)
        let count = Int(sampleRate * duration)
        var audioData = [Float](repeating: 0, count: count)
        let pitchMult = pow(2.0, Double(preset.pitch) / 12.0)
        var rng = Noise(seed: 0xF00D_0001)
        var vinyl = OnePoleLPF(cutoff: 1_200, sampleRate: sampleRate)
        var reverseHP = OnePoleHPF(cutoff: 900, sampleRate: sampleRate)
        var reverseLP = OnePoleLPF(cutoff: 2_200, sampleRate: sampleRate)
        var burstHP = OnePoleHPF(cutoff: 6_000, sampleRate: sampleRate)
        var held = 0.0

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let progress = t / duration
            var sample: Double = 0

            if name.contains("zap") {
                let freq = 1500.0 * pitchMult * pow(0.1, progress)
                sample = sin(2 * .pi * freq * t) * exp(-t * ampRate)
            } else if name.contains("laser") {
                let freq = 2500.0 * pitchMult * pow(0.5, progress)
                sample = sin(2 * .pi * freq * t) * exp(-t * ampRate)
            } else if name.contains("blip") {
                // Library pitch is +8. 1200 Hz landed on the same centroid as Zap.
                let freq = 1800.0 * pitchMult
                sample = sin(2 * .pi * freq * t) * exp(-t * ampRate)
            } else if name.contains("sweep_up") {
                let freq = 200.0 * pitchMult * pow(10.0, progress)
                sample = sin(2 * .pi * freq * t) * exp(-t * ampRate)
            } else if name.contains("sweep_dn") {
                let freq = 2000.0 * pitchMult * pow(0.1, progress)
                sample = sin(2 * .pi * freq * t) * exp(-t * ampRate)
            } else if name.contains("vinyl") {
                let crack = rng.next() > 0.96 ? rng.next() : 0
                sample = vinyl.process(crack) * exp(-t * 2) * 0.3
            } else if name.contains("reverse") {
                // Swell across the open ADSR. The full buffer ends in silence, so a
                // rise mapped onto that length peaks after the decay has reached zero.
                let rise = max(0.05, Double(preset.attack) + Double(preset.decay) * 0.7)
                let swell = min(1.0, t / rise)
                let env = swell * exp(-(1.0 - swell) * 5)
                var grain = rng.next()
                grain = reverseHP.process(grain)
                grain = reverseLP.process(grain)
                sample = grain * env * 0.5
            } else if name.contains("impact") {
                let freq = 80.0 * pitchMult
                sample = sin(2 * .pi * freq * t) * exp(-t * 6) * 0.8
                    + rng.next() * exp(-t * 20) * 0.2
            } else if name.contains("glitch") {
                if i % 32 == 0 { held = rng.next() }
                let gate = (i / 700) % 2 == 0 ? 1.0 : 0.15
                sample = held * gate * exp(-t * ampRate)
            } else {
                sample = burstHP.process(rng.next()) * exp(-t * ampRate)
            }
            audioData[i] = Float(sample)
        }

        if noisy {
            applyAttack(&audioData, sampleRate: sampleRate)
        }
        return audioData
    }
}
