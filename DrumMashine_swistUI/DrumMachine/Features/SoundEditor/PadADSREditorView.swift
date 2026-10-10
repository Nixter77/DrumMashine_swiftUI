import SwiftUI
// MARK: - Pad ADSR Editor (popup sheet for editing per-pad envelope)
struct PadADSREditorView: View {
    @Binding var preset: SoundPreset
    let padColor: Color
    let onClose: () -> Void
    @State private var isSavingPreset = false
    @State private var draftName = ""
    @State private var draftCategory: SoundPreset.SoundCategory = .snare
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Circle()
                    .fill(padColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: padColor.opacity(0.6), radius: 4)
                
                Text(preset.name + " — ENVELOPE")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textTertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            // ADSR Visualizer
            ADSRCurveView(
                attack: Double(preset.attack),
                decay: Double(preset.decay),
                sustain: Double(preset.sustain),
                release: Double(preset.release),
                color: padColor
            )
            .frame(height: 80)
            
            // ADSR Sliders
            VStack(spacing: 10) {
                ADSRSliderRow(
                    label: "ATK",
                    value: Binding(
                        get: { Double(preset.attack) },
                        set: { preset.attack = Float($0) }
                    ),
                    range: 0...0.5,
                    color: Color(hex: "30D158"),
                    unit: "s"
                )
                
                ADSRSliderRow(
                    label: "DEC",
                    value: Binding(
                        get: { Double(preset.decay) },
                        set: { preset.decay = Float($0) }
                    ),
                    range: 0...1.0,
                    color: Color(hex: "FFD60A"),
                    unit: "s"
                )
                
                ADSRSliderRow(
                    label: "SUS",
                    value: Binding(
                        get: { Double(preset.sustain) },
                        set: { preset.sustain = Float($0) }
                    ),
                    range: 0...1.0,
                    color: Color(hex: "0A84FF"),
                    unit: "%",
                    displayMultiplier: 100
                )
                
                ADSRSliderRow(
                    label: "REL",
                    value: Binding(
                        get: { Double(preset.release) },
                        set: { preset.release = Float($0) }
                    ),
                    range: 0...2.0,
                    color: Color(hex: "BF5AF2"),
                    unit: "s"
                )
            }
            
            Divider()
                .overlay(Color.gray.opacity(0.2))

            voiceControls

            Divider()
                .overlay(Color.gray.opacity(0.2))
            
            // Pitch & Volume row
            HStack(spacing: 16) {
                // Pitch
                VStack(spacing: 4) {
                    Text("PITCH")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    HStack(spacing: 6) {
                        Button(action: { preset.pitch = max(-24, preset.pitch - 1) }) {
                            Image(systemName: "minus")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(AppTheme.textPrimary)
                                .frame(width: 22, height: 22)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Text("\(Int(preset.pitch > 0 ? preset.pitch : preset.pitch)) st")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(preset.pitch != 0 ? padColor : AppTheme.textSecondary)
                            .frame(minWidth: 40)
                        
                        Button(action: { preset.pitch = min(24, preset.pitch + 1) }) {
                            Image(systemName: "plus")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(AppTheme.textPrimary)
                                .frame(width: 22, height: 22)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    draftName = preset.name
                    draftCategory = preset.category
                    isSavingPreset = true
                }) {
                    Text("Сохранить как пресет…")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.surfaceElevated)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        preset = preset.restored(
                            fromFactory: SoundLibraryManager.shared.availableSounds,
                            users: UserPresetStore.shared.presets
                        )
                    }
                }) {
                    Label("RESET", systemImage: "arrow.counterclockwise")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.surfaceElevated)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            if isSavingPreset {
                savePresetForm
            }
        }
        .padding(16)
        .glassPanel()
    }

    /// Three or four knobs for this voice. The rest of the generator stays at its constants.
    @ViewBuilder
    private var voiceControls: some View {
        VStack(spacing: 10) {
            switch preset.resolvedVoice {
            case .kick:
                toneSlider("Тон", value: Binding(get: { preset.synth?.kick?.startHz ?? 150 }, set: { value in editKick { $0.startHz = value } }), range: 40...400, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { preset.synth?.kick?.click ?? 0.5 }, set: { value in editKick { $0.click = value } }), range: 0...1, unit: "")
                toneSlider("Шум", value: Binding(get: { preset.synth?.kick?.noise ?? 0 }, set: { value in editKick { $0.noise = value } }), range: 0...1, unit: "")
            case .snare:
                toneSlider("Тон", value: Binding(get: { preset.synth?.snare?.tone1Hz ?? 180 }, set: { value in editSnare { $0.tone1Hz = value } }), range: 80...800, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { preset.synth?.snare?.tone2Hz ?? 330 }, set: { value in editSnare { $0.tone2Hz = value } }), range: 100...2000, unit: "Hz")
                toneSlider("Шум", value: Binding(get: { preset.synth?.snare?.noiseLevel ?? 0.8 }, set: { value in editSnare { $0.noiseLevel = value } }), range: 0...1.5, unit: "")
            case .closedHat, .openHat:
                toneSlider("Тон", value: Binding(get: { preset.synth?.hat?.bandHz ?? 10_000 }, set: { value in editHat { $0.bandHz = value } }), range: 2_000...14_000, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { preset.synth?.hat?.bandQ ?? 0.8 }, set: { value in editHat { $0.bandQ = value } }), range: 0.2...4, unit: "")
                toneSlider("Шум", value: Binding(get: { preset.synth?.hat?.noiseMix ?? 0 }, set: { value in editHat { $0.noiseMix = value } }), range: 0...1, unit: "")
            case .clap:
                toneSlider("Тон", value: Binding(get: { preset.synth?.clap?.hpHz ?? 800 }, set: { value in editClap { $0.hpHz = value } }), range: 200...4000, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { Double(preset.synth?.clap?.bursts ?? 3) }, set: { value in editClap { $0.bursts = Int(value.rounded()) } }), range: 1...6, unit: "")
                toneSlider("Шум", value: Binding(get: { preset.synth?.clap?.tailLevel ?? 0.4 }, set: { value in editClap { $0.tailLevel = value } }), range: 0...1, unit: "")
            case .tom:
                toneSlider("Тон", value: Binding(get: { preset.synth?.tom?.startHz ?? 200 }, set: { value in editTom { $0.startHz = value } }), range: 60...500, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { preset.synth?.tom?.stickNoise ?? 0 }, set: { value in editTom { $0.stickNoise = value } }), range: 0...1, unit: "")
                toneSlider("Шум", value: Binding(get: { preset.synth?.tom?.endHz ?? 80 }, set: { value in editTom { $0.endHz = value } }), range: 40...300, unit: "Hz")
            case .ride:
                toneSlider("Тон", value: Binding(get: { preset.synth?.ride?.pingHz ?? 5000 }, set: { value in editRide { $0.pingHz = value } }), range: 1_000...8_000, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { preset.synth?.ride?.pingLevel ?? 0.6 }, set: { value in editRide { $0.pingLevel = value } }), range: 0...1, unit: "")
                toneSlider("Шум", value: Binding(get: { preset.synth?.ride?.sizzleLevel ?? 0.4 }, set: { value in editRide { $0.sizzleLevel = value } }), range: 0...1, unit: "")
            case .crash:
                toneSlider("Тон", value: Binding(get: { preset.synth?.crash?.carrierHz ?? 300 }, set: { value in editCrash { $0.carrierHz = value } }), range: 80...800, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { preset.synth?.crash?.index ?? 5 }, set: { value in editCrash { $0.index = value } }), range: 0...12, unit: "")
                toneSlider("Шум", value: Binding(get: { preset.synth?.crash?.fmMix ?? 0.3 }, set: { value in editCrash { $0.fmMix = value } }), range: 0...1, unit: "")
            case .perc:
                toneSlider("Тон", value: Binding(get: { preset.synth?.perc?.carrierHz ?? 800 }, set: { value in editPerc { $0.carrierHz = value } }), range: 80...4000, unit: "Hz")
                toneSlider("Щелчок", value: Binding(get: { preset.synth?.perc?.index ?? 3 }, set: { value in editPerc { $0.index = value } }), range: 0...8, unit: "")
                toneSlider("Шум", value: Binding(get: { preset.synth?.perc?.bandHz ?? 6000 }, set: { value in editPerc { $0.bandHz = value; if $0.mode == nil { $0.mode = .noise } } }), range: 200...12_000, unit: "Hz")
            case .fx:
                EmptyView()
            }
            toneSlider("Lo-fi", value: Binding(get: { lofiAmount }, set: { setLofi($0) }), range: 0...1, unit: "")
        }
    }

    private var lofiAmount: Double {
        if let saturation = preset.synth?.lofi?.saturation { return saturation }
        if preset.synth?.lofi?.bitDepth == 8 { return 1 }
        if preset.synth?.lofi?.bitDepth == 12 { return 0.5 }
        return 0
    }

    private func toneSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        ADSRSliderRow(
            label: title,
            value: value,
            range: range,
            color: padColor,
            unit: unit,
            labelWidth: 52
        )
    }

    private func editSynth(_ body: (inout SynthParams) -> Void) {
        var synth = preset.synth ?? SynthParams()
        body(&synth)
        preset.synth = synth
    }

    private func editKick(_ body: (inout SynthParams.Kick) -> Void) {
        editSynth { synth in
            var kick = synth.kick ?? SynthParams.Kick()
            body(&kick)
            synth.kick = kick
        }
    }

    private func editSnare(_ body: (inout SynthParams.Snare) -> Void) {
        editSynth { synth in
            var snare = synth.snare ?? SynthParams.Snare()
            body(&snare)
            synth.snare = snare
        }
    }

    private func editHat(_ body: (inout SynthParams.Hat) -> Void) {
        editSynth { synth in
            var hat = synth.hat ?? SynthParams.Hat()
            body(&hat)
            synth.hat = hat
        }
    }

    private func editClap(_ body: (inout SynthParams.Clap) -> Void) {
        editSynth { synth in
            var clap = synth.clap ?? SynthParams.Clap()
            body(&clap)
            synth.clap = clap
        }
    }

    private func editTom(_ body: (inout SynthParams.Tom) -> Void) {
        editSynth { synth in
            var tom = synth.tom ?? SynthParams.Tom()
            body(&tom)
            synth.tom = tom
        }
    }

    private func editRide(_ body: (inout SynthParams.Ride) -> Void) {
        editSynth { synth in
            var ride = synth.ride ?? SynthParams.Ride()
            body(&ride)
            synth.ride = ride
        }
    }

    private func editCrash(_ body: (inout SynthParams.Crash) -> Void) {
        editSynth { synth in
            var crash = synth.crash ?? SynthParams.Crash()
            body(&crash)
            synth.crash = crash
        }
    }

    private func editPerc(_ body: (inout SynthParams.Perc) -> Void) {
        editSynth { synth in
            var perc = synth.perc ?? SynthParams.Perc()
            body(&perc)
            synth.perc = perc
        }
    }

    private func setLofi(_ value: Double) {
        editSynth { synth in
            if value <= 0.001 {
                synth.lofi = nil
                return
            }
            var lofi = synth.lofi ?? SynthParams.LoFi()
            lofi.saturation = value
            if value >= 0.66 {
                lofi.bitDepth = 8
                lofi.downsample = 3
            } else if value >= 0.33 {
                lofi.bitDepth = 12
                lofi.downsample = 2
            } else {
                lofi.bitDepth = nil
                lofi.downsample = nil
            }
            synth.lofi = lofi
        }
    }

    private var savePresetForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("СОХРАНИТЬ КАК ПРЕСЕТ")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(AppTheme.textTertiary)
            TextField("Имя", text: $draftName)
                .textFieldStyle(.roundedBorder)
            Picker("Инструмент", selection: $draftCategory) {
                ForEach(SoundPreset.SoundCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Button("Отмена") { isSavingPreset = false }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Button("Сохранить") { commitSavedPreset() }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.accent)
            }
        }
    }

    private func commitSavedPreset() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var saved = preset
        saved.id = UUID()
        saved.name = trimmed
        saved.category = draftCategory
        saved.origin = .user
        saved.basedOn = preset.basedOn ?? preset.id
        UserPresetStore.shared.save(saved)
        UserPresetStore.shared.flush()
        isSavingPreset = false
    }
}

// MARK: - ADSR Curve Visualizer
struct ADSRCurveView: View {
    var attack: Double
    var decay: Double
    var sustain: Double
    var release: Double
    var color: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            // Normalize time segments
            let total = attack + decay + 0.3 + release + 0.1
            let atkEnd = w * (attack / total)
            let decEnd = atkEnd + w * (decay / total)
            let susEnd = decEnd + w * (0.3 / total)
            let relEnd = susEnd + w * (release / total)
            
            let susY = h * (1.0 - sustain)
            
            ZStack {
                // Fill
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: atkEnd, y: 0))
                    path.addLine(to: CGPoint(x: decEnd, y: susY))
                    path.addLine(to: CGPoint(x: susEnd, y: susY))
                    path.addLine(to: CGPoint(x: relEnd, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Stroke
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: atkEnd, y: 0))
                    path.addLine(to: CGPoint(x: decEnd, y: susY))
                    path.addLine(to: CGPoint(x: susEnd, y: susY))
                    path.addLine(to: CGPoint(x: relEnd, y: h))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                
                // Glow
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: atkEnd, y: 0))
                    path.addLine(to: CGPoint(x: decEnd, y: susY))
                    path.addLine(to: CGPoint(x: susEnd, y: susY))
                    path.addLine(to: CGPoint(x: relEnd, y: h))
                }
                .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .blur(radius: 4)
                
                // Labels
                HStack {
                    Text("A").font(.system(size: 8, design: .monospaced)).foregroundColor(Color(hex: "30D158"))
                    Spacer()
                    Text("D").font(.system(size: 8, design: .monospaced)).foregroundColor(Color(hex: "FFD60A"))
                    Spacer()
                    Text("S").font(.system(size: 8, design: .monospaced)).foregroundColor(Color(hex: "0A84FF"))
                    Spacer()
                    Text("R").font(.system(size: 8, design: .monospaced)).foregroundColor(Color(hex: "BF5AF2"))
                }
                .padding(.horizontal, 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: 2)
            }
        }
    }
}

// MARK: - ADSR Slider Row
struct ADSRSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let unit: String
    var displayMultiplier: Double = 1.0
    var labelWidth: CGFloat = 28
    
    var displayValue: String {
        let v = value * displayMultiplier
        if unit == "%" {
            return "\(Int(v))%"
        } else {
            return String(format: "%.2f\(unit)", v)
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(color)
                .frame(width: labelWidth, alignment: .leading)
            
            Slider(value: $value, in: range)
                .tint(color)
            
            Text(displayValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
