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
                
                soundPicker
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textTertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            if isSynth {
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
            
            }

            Divider()
                .overlay(Color.gray.opacity(0.2))

            voiceControls

            Divider()
                .overlay(Color.gray.opacity(0.2))
            
            HStack(spacing: 16) {
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

    private var isSynth: Bool { preset.source == .synth }

    /// Pick another sound for this track without leaving the editor. Hats list both closed and open.
    private var soundPicker: some View {
        Menu {
            ForEach(SoundLibraryManager.shared.presets(forTrackVoice: preset.resolvedVoice)) { option in
                Button(option.name + (option.style == .acoustic ? "  · acoustic" : "")) {
                    var copy = option
                    copy.basedOn = option.id
                    preset = copy
                }
            }
        } label: {
            Text(preset.name + "  ▾")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("soundEditor.picker")
    }

    /// Tune, decay or length, voice knobs, tone, level. Same list for every track (see SoundControls).
    @ViewBuilder
    private var voiceControls: some View {
        VStack(spacing: 10) {
            ForEach(SoundControls.controls(for: preset)) { control in
                toneSlider(
                    control.title,
                    value: Binding(get: { control.get(preset) }, set: { value in
                        var copy = preset
                        control.set(&copy, value)
                        preset = copy
                    }),
                    range: control.range,
                    unit: control.unit
                )
            }
            if isSynth {
                toneSlider("Lo-fi", value: Binding(get: { lofiAmount }, set: { setLofi($0) }), range: 0...1, unit: "")
            }
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
