import SwiftUI

// MARK: - Effects Rack (Reverb + Delay + Distortion + 3-Band EQ)
struct EffectsRackView: View {
    let bpm: Double
    /// ImageRenderer cannot flatten a horizontal ScrollView, so snapshots lay the modules out in a row.
    var showsLayoutForSnapshot: Bool = false
    @Bindable private var audioManager = AudioEngineManager.shared
    @Environment(\.undoManager) private var undoManager
    @State private var edits = EffectPresetEditSession()
    @State private var savePresented = false
    @State private var saveDraft = ""
    @State private var renameTarget: EffectScene?
    @State private var renameDraft = ""
    @State private var routingPresented = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            sceneMenu
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 8)
                .padding(.top, 10)

            Group {
                if showsLayoutForSnapshot {
                    // Full module width, then the row clips like the scroll view's first screen.
                    moduleRow
                        .fixedSize(horizontal: true, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        moduleRow
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .glassPanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("effects.rack")
        .alert("Сохранить текущие эффекты…", isPresented: $savePresented) {
            TextField("Имя", text: $saveDraft)
            Button("Сохранить") { saveCurrentScene() }
            Button("Отмена", role: .cancel) {}
        }
        .alert(
            "Переименовать сцену",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Имя", text: $renameDraft)
            Button("Сохранить") { commitRename() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var moduleRow: some View {
        // Modules follow the signal order chosen in Routing.
        HStack(spacing: 8) {
            sidechainModule
            ForEach(EffectsChain.sanitized(audioManager.effectsChain.order)) { slot in
                switch slot {
                case .reverb: reverbModule
                case .delay: delayModule
                case .distortion: distortModule
                case .eq: EQModuleView(edits: edits, showsLayoutForSnapshot: showsLayoutForSnapshot)
                case .compressor: compressorModule
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var sceneMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsLayoutForSnapshot {
                Text("SCENE ▾")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
            } else {
                Menu {
                    ForEach(EffectPresets.scenes) { scene in
                        Button(scene.name) {
                            choose(scene)
                        }
                        .accessibilityIdentifier(sceneItemID(scene))
                    }
                    Divider()
                    Button("Сохранить текущие эффекты…") {
                        saveDraft = ""
                        savePresented = true
                    }
                    .accessibilityIdentifier("effects.scene.save")
                    if !EffectSceneStore.shared.scenes.isEmpty {
                        Divider()
                        ForEach(EffectSceneStore.shared.scenes) { scene in
                            // Click applies. The chevron and the context menu rename or delete.
                            // contextMenu on a row inside Menu is not shown, so the actions are repeated there.
                            Menu(scene.name) {
                                sceneActions(scene)
                            } primaryAction: {
                                applyUserScene(scene)
                            }
                            .contextMenu { sceneActions(scene) }
                            .accessibilityIdentifier("effects.scene.user.\(scene.id.uuidString)")
                        }
                    }
                } label: {
                    Text("SCENE ▾")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .fixedSize()
                .accessibilityIdentifier("effects.scene")
            }

            if !showsLayoutForSnapshot {
                Button {
                    routingPresented = true
                } label: {
                    Label("ROUTING", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Маршрутизация эффектов")
                .accessibilityIdentifier("effects.routing")
                .popover(isPresented: $routingPresented, arrowEdge: .bottom) {
                    EffectRoutingView(
                        chain: audioManager.effectsChain,
                        onChange: { mutate in
                            prepareEdit()
                            edits.apply { chain, _ in mutate(&chain) }
                            undoManager?.setActionName("Effect Routing")
                        }
                    )
                }
            }

            if let name = edits.labels.scene {
                Text(name)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                // Text does not publish its string as an AX label on macOS. The probe does.
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("effects.scene.name")
                    .accessibilityLabel(name)
            }
        }
    }

    private var reverbModule: some View {
        EffectModuleView(
            title: "REVERB",
            icon: "waveform",
            color: Color(hex: "BF5AF2"),
            isOn: $audioManager.effectsChain.reverb.isOn,
            powerIdentifier: "effect.reverb.power",
            showsLayoutForSnapshot: showsLayoutForSnapshot,
            presetIdentifier: "effect.reverb.preset",
            presetName: edits.labels.reverb,
            presets: EffectPresets.reverb.map { EffectMenuItem(id: $0.id, name: $0.name) },
            onPreset: { id in
                let preset = EffectPresets.reverbPreset(id)
                prepareEdit()
                edits.chooseReverb(preset, bpm: bpm)
            }
        ) {
            KnobView(
                value: Binding(
                    get: { Double(audioManager.effectsChain.reverb.wetDryMix) },
                    set: { newValue in
                        audioManager.effectsChain.reverb.wetDryMix = Float(newValue)
                        edits.labels.clear(.reverb)
                        audioManager.updateEffects()
                    }
                ),
                title: "MIX",
                color: Color(hex: "BF5AF2"),
                size: 40
            )
            VStack(spacing: 6) {
                Text("ROOM")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Picker("ROOM", selection: Binding(
                    get: { audioManager.effectsChain.reverb.room },
                    set: { room in
                        audioManager.effectsChain.reverb.room = room
                        edits.labels.clear(.reverb)
                        audioManager.updateEffects()
                    }
                )) {
                    ForEach(EffectsChain.ReverbRoom.allCases) { room in
                        Text(room.label).tag(room)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }
        }
    }

    private var delayModule: some View {
        EffectModuleView(
            title: "DELAY",
            icon: "repeat",
            color: AppTheme.accentSecondary,
            isOn: $audioManager.effectsChain.delay.isOn,
            powerIdentifier: "effect.delay.power",
            showsLayoutForSnapshot: showsLayoutForSnapshot,
            presetIdentifier: "effect.delay.preset",
            presetName: edits.labels.delay,
            presets: EffectPresets.delay.map { EffectMenuItem(id: $0.id, name: $0.name) },
            onPreset: { id in
                let preset = EffectPresets.delayPreset(id)
                prepareEdit()
                edits.chooseDelay(preset, bpm: bpm)
            }
        ) {
            KnobView(
                value: Binding(
                    get: { Double(audioManager.effectsChain.delay.wetDryMix) },
                    set: { newValue in
                        audioManager.effectsChain.delay.wetDryMix = Float(newValue)
                        edits.labels.clear(.delay)
                        audioManager.updateEffects()
                    }
                ),
                title: "MIX",
                color: AppTheme.accentSecondary,
                size: 40
            )
            KnobView(
                value: Binding(
                    get: { audioManager.effectsChain.delay.delayTime },
                    set: { newValue in
                        audioManager.effectsChain.delay.applyManualTime(newValue)
                        edits.labels.clear(.delay)
                        audioManager.updateEffects()
                    }
                ),
                range: 0.05...2.0,
                title: "TIME",
                color: AppTheme.accentSecondary,
                size: 40,
                valueFormatter: { seconds in
                    if let beats = audioManager.effectsChain.delay.syncBeats {
                        return EffectPresets.delayFractionLabel(beats: beats)
                    }
                    return String(format: "%.2fs", seconds)
                }
            )
            KnobView(
                value: Binding(
                    get: { Double(audioManager.effectsChain.delay.feedback) / 100.0 },
                    set: { newValue in
                        audioManager.effectsChain.delay.feedback = Float(newValue * 100.0)
                        edits.labels.clear(.delay)
                        audioManager.updateEffects()
                    }
                ),
                title: "FDBK",
                color: AppTheme.accentSecondary,
                size: 40
            )
        }
    }

    private var distortModule: some View {
        EffectModuleView(
            title: "DISTORT",
            icon: "bolt.fill",
            color: AppTheme.accent,
            isOn: $audioManager.effectsChain.distortion.isOn,
            powerIdentifier: "effect.distortion.power",
            showsLayoutForSnapshot: showsLayoutForSnapshot,
            presetIdentifier: "effect.distortion.preset",
            presetName: edits.labels.distortion,
            presets: EffectPresets.distortion.map { EffectMenuItem(id: $0.id, name: $0.name) },
            onPreset: { id in
                let preset = EffectPresets.distortionPreset(id)
                prepareEdit()
                edits.chooseDistortion(preset, bpm: bpm)
            }
        ) {
            KnobView(
                value: Binding(
                    get: { Double(audioManager.effectsChain.distortion.wetDryMix) },
                    set: { newValue in
                        audioManager.effectsChain.distortion.wetDryMix = Float(newValue)
                        edits.labels.clear(.distortion)
                        audioManager.updateEffects()
                    }
                ),
                title: "DRIVE",
                color: AppTheme.accent,
                size: 40
            )
            KnobView(
                value: Binding(
                    get: { Double(audioManager.effectsChain.distortion.preGain + 20) / 40.0 },
                    set: { newValue in
                        audioManager.effectsChain.distortion.preGain = Float(newValue * 40.0 - 20.0)
                        edits.labels.clear(.distortion)
                        audioManager.updateEffects()
                    }
                ),
                title: "GAIN",
                color: AppTheme.accent,
                size: 40,
                valueFormatter: { String(format: "%.0fdB", $0 * 40.0 - 20.0) }
            )
        }
    }

    private var compressorModule: some View {
        let tint = Color(hex: "30D158")
        return EffectModuleView(
            title: "COMP",
            icon: "rectangle.compress.vertical",
            color: tint,
            isOn: $audioManager.effectsChain.compressor.isOn,
            powerIdentifier: "effect.compressor.power",
            showsLayoutForSnapshot: showsLayoutForSnapshot,
            presetIdentifier: "effect.compressor.preset",
            presetName: edits.labels.compressor,
            presets: EffectPresets.compressor.map { EffectMenuItem(id: $0.id, name: $0.name) },
            onPreset: { id in
                let preset = EffectPresets.compressorPreset(id)
                prepareEdit()
                edits.chooseCompressor(preset)
            }
        ) {
            compKnob("THRESH", tint, get: { Double(($0.threshold + 40) / 40) },
                     set: { $0.threshold = Float($1 * 40 - 40) },
                     format: { String(format: "%.0fdB", $0 * 40 - 40) })
            compKnob("AMOUNT", tint, get: { Double($0.amount) }, set: { $0.amount = Float($1) },
                     format: { "\(Int($0 * 100))%" })
            compKnob("ATTACK", tint, get: { Double(log10(max(0.1, $0.attackMs) / 0.1) / log10(2000)) },
                     set: { $0.attackMs = Float(0.1 * pow(2000, $1)) },
                     format: { String(format: "%.1fms", 0.1 * pow(2000, $0)) })
            compKnob("RELEASE", tint, get: { Double(log10(max(10, $0.releaseMs) / 10) / 2) },
                     set: { $0.releaseMs = Float(10 * pow(100, $1)) },
                     format: { String(format: "%.0fms", 10 * pow(100, $0)) })
            compKnob("GAIN", tint, get: { Double($0.makeup / 20) }, set: { $0.makeup = Float($1 * 20) },
                     format: { String(format: "+%.1fdB", $0 * 20) })
        }
    }

    static let trackShortNames = ["KICK", "SNR", "HAT", "CLAP", "TOM", "RIDE", "CRSH", "PERC"]

    /// Pre-FX ducking in the voice mixer. Knobs edit live; source, ducked tracks and presets go through undo.
    private var sidechainModule: some View {
        let tint = Color(hex: "FF9F0A")
        let sc = audioManager.effectsChain.sidechain
        return EffectModuleView(
            title: "SIDECHAIN",
            icon: "arrow.down.to.line",
            color: tint,
            isOn: Binding(
                get: { audioManager.effectsChain.sidechain.isOn },
                set: { on in editSidechain("Sidechain") { $0.isOn = on } }
            ),
            powerIdentifier: "effect.sidechain.power",
            showsLayoutForSnapshot: showsLayoutForSnapshot,
            presetIdentifier: "effect.sidechain.preset",
            presetName: SidechainSettings.presets.first { $0.amount == sc.amount && $0.releaseMs == sc.releaseMs }?.name,
            presets: SidechainSettings.presets.map { EffectMenuItem(id: $0.id, name: $0.name) },
            onPreset: { id in
                guard let preset = SidechainSettings.presets.first(where: { $0.id == id }) else { return }
                editSidechain("Sidechain Preset") { preset.apply(to: &$0) }
            }
        ) {
            VStack(spacing: 4) {
                Menu {
                    ForEach(0..<8, id: \.self) { index in
                        Button(Self.trackShortNames[index]) { editSidechain("Sidechain Source") { $0.sourceTrack = index } }
                    }
                } label: {
                    Text("SRC " + Self.trackShortNames[sc.sourceTrack] + " ▾")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(tint)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("effect.sidechain.source")
                Menu {
                    ForEach(0..<8, id: \.self) { index in
                        if index != sc.sourceTrack {
                            Toggle(Self.trackShortNames[index], isOn: Binding(
                                get: { audioManager.effectsChain.sidechain.ducked[index] },
                                set: { value in editSidechain("Sidechain Tracks") { $0.ducked[index] = value } }
                            ))
                        }
                    }
                    Divider()
                    Toggle("Velocity → depth", isOn: Binding(
                        get: { audioManager.effectsChain.sidechain.velocityScaling },
                        set: { value in editSidechain("Sidechain Velocity") { $0.velocityScaling = value } }
                    ))
                } label: {
                    Text("DUCK \(sc.duckMask.nonzeroBitCount) ▾")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("effect.sidechain.tracks")
            }
            KnobView(
                value: Binding(
                    get: { Double(audioManager.effectsChain.sidechain.amount) },
                    set: { audioManager.effectsChain.sidechain.amount = Float(min(1, max(0, $0))); audioManager.updateEffects() }
                ),
                title: "DEPTH", color: tint, size: 40,
                valueFormatter: { "\(Int($0 * 100))%" }
            )
            KnobView(
                value: Binding(
                    get: { Double((audioManager.effectsChain.sidechain.releaseMs - 50) / 550) },
                    set: { audioManager.effectsChain.sidechain.releaseMs = Float(50 + min(1, max(0, $0)) * 550); audioManager.updateEffects() }
                ),
                title: "RELEASE", color: tint, size: 40,
                valueFormatter: { String(format: "%.0fms", 50 + $0 * 550) }
            )
        }
    }

    private func editSidechain(_ action: String, _ body: @escaping (inout SidechainSettings) -> Void) {
        prepareEdit()
        edits.apply { chain, _ in body(&chain.sidechain) }
        undoManager?.setActionName(action)
    }

    private func compKnob(
        _ title: String, _ color: Color,
        get: @escaping (EffectsChain.CompressorSettings) -> Double,
        set: @escaping (inout EffectsChain.CompressorSettings, Double) -> Void,
        format: @escaping (Double) -> String
    ) -> some View {
        KnobView(
            value: Binding(
                get: { get(audioManager.effectsChain.compressor) },
                set: { newValue in
                    set(&audioManager.effectsChain.compressor, min(1, max(0, newValue)))
                    edits.labels.clear(.compressor)
                    audioManager.updateEffects()
                }
            ),
            title: title,
            color: color,
            size: 40,
            valueFormatter: format
        )
    }

    private func choose(_ scene: EffectPresets.Scene) {
        prepareEdit()
        edits.chooseScene(scene, bpm: bpm)
    }

    @ViewBuilder
    private func sceneActions(_ scene: EffectScene) -> some View {
        Button("Переименовать") {
            renameTarget = scene
            renameDraft = scene.name
        }
        Button("Удалить", role: .destructive) {
            deleteUserScene(scene)
        }
    }

    private func applyUserScene(_ scene: EffectScene) {
        prepareEdit()
        edits.chooseUserScene(scene, bpm: bpm)
    }

    private func saveCurrentScene() {
        let name = saveDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        EffectSceneStore.shared.save(name: name, chain: audioManager.effectsChain)
        EffectSceneStore.shared.flush()
    }

    private func commitRename() {
        guard let id = renameTarget?.id else { return }
        let previous = renameTarget?.name
        EffectSceneStore.shared.rename(id: id, to: renameDraft)
        if edits.labels.scene == previous {
            let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                edits.labels.scene = trimmed
            }
        }
        EffectSceneStore.shared.flush()
    }

    private func deleteUserScene(_ scene: EffectScene) {
        EffectSceneStore.shared.delete(id: scene.id)
        EffectSceneStore.shared.flush()
        if edits.labels.scene == scene.name {
            edits.labels.scene = nil
        }
    }

    /// The undo target reads the live chain. Bound on each edit, not in `body`.
    private func prepareEdit() {
        edits.read = { audioManager.effectsChain }
        edits.commit = { chain in
            audioManager.effectsChain = chain
            audioManager.updateEffects()
        }
        edits.undoManager = undoManager
    }

    private func sceneItemID(_ scene: EffectPresets.Scene) -> String {
        let suffix = scene.id.split(separator: ".").last.map(String.init) ?? scene.id
        return "effects.scene.\(suffix)"
    }
}

// MARK: - 3-Band EQ Module
struct EQModuleView: View {
    @Bindable private var audioManager = AudioEngineManager.shared
    @Environment(\.undoManager) private var undoManager
    var edits: EffectPresetEditSession
    var showsLayoutForSnapshot: Bool = false

    var body: some View {
        EffectModuleView(
            title: "3-BAND EQ",
            icon: "slider.horizontal.3",
            color: Color(hex: "30D158"),
            isOn: Binding(
                get: { audioManager.effectsChain.eq.isOn },
                set: { audioManager.effectsChain.eq.isOn = $0 }
            ),
            powerIdentifier: "effect.eq.power",
            showsLayoutForSnapshot: showsLayoutForSnapshot,
            presetIdentifier: "effect.eq.preset",
            presetName: edits.labels.eq,
            presets: EffectPresets.eq.map { EffectMenuItem(id: $0.id, name: $0.name) },
            onPreset: { id in
                let preset = EffectPresets.eqPreset(id)
                edits.read = { audioManager.effectsChain }
                edits.commit = { chain in
                    audioManager.effectsChain = chain
                    audioManager.updateEffects()
                }
                edits.undoManager = undoManager
                edits.chooseEQ(preset)
            }
        ) {
            KnobView(
                value: gainBinding(\.low),
                title: "LOW",
                color: Color(hex: "FF6B35"),
                size: 40,
                valueFormatter: { String(format: "%+.0fdB", ($0 - 0.5) * 24) }
            )
            KnobView(
                value: gainBinding(\.mid),
                title: "MID",
                color: Color(hex: "30D158"),
                size: 40,
                valueFormatter: { String(format: "%+.0fdB", ($0 - 0.5) * 24) }
            )
            KnobView(
                value: gainBinding(\.high),
                title: "HIGH",
                color: Color(hex: "5AC8FA"),
                size: 40,
                valueFormatter: { String(format: "%+.0fdB", ($0 - 0.5) * 24) }
            )
        }
    }

    /// Knob 0...1 is −12...+12 dB.
    private func gainBinding(_ key: WritableKeyPath<EffectsChain.EQSettings, Float>) -> Binding<Double> {
        Binding(
            get: { Double(audioManager.effectsChain.eq[keyPath: key] + 12) / 24 },
            set: { newValue in
                audioManager.effectsChain.eq[keyPath: key] = Float(newValue) * 24 - 12
                edits.labels.clear(.eq)
                audioManager.updateEffects()
            }
        )
    }
}

// MARK: - Effect Module (with on/off toggle + power LED animation)
struct EffectModuleView<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    let powerIdentifier: String
    var showsLayoutForSnapshot: Bool = false
    let presetIdentifier: String
    let presetName: String?
    let presets: [EffectMenuItem]
    let onPreset: (String) -> Void
    let content: Content

    init(
        title: String,
        icon: String = "waveform",
        color: Color,
        isOn: Binding<Bool>,
        powerIdentifier: String,
        showsLayoutForSnapshot: Bool = false,
        presetIdentifier: String,
        presetName: String?,
        presets: [EffectMenuItem],
        onPreset: @escaping (String) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self._isOn = isOn
        self.powerIdentifier = powerIdentifier
        self.showsLayoutForSnapshot = showsLayoutForSnapshot
        self.presetIdentifier = presetIdentifier
        self.presetName = presetName
        self.presets = presets
        self.onPreset = onPreset
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(isOn ? color : AppTheme.textTertiary)

                Text(title)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(isOn ? color : AppTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()

                presetControl

                if let presetName {
                    Text(presetName)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(isOn ? color : AppTheme.textTertiary)
                        .lineLimit(1)
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("\(presetIdentifier).name")
                        .accessibilityLabel(presetName)
                }

                Spacer(minLength: 4)

                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier(powerIdentifier)
                    .accessibilityLabel(isOn ? "on" : "off")

                Button(action: {
                    withAnimation(.spring(response: 0.2)) {
                        isOn.toggle()
                        AudioEngineManager.shared.updateEffects()
                    }
                }) {
                    Circle()
                        .fill(isOn ? color : Color.gray.opacity(0.25))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(isOn ? color.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(isOn ? color.opacity(0.25) : Color.gray.opacity(0.1)),
                alignment: .bottom
            )

            HStack(spacing: 8) {
                content
            }
            .opacity(isOn ? 1.0 : 0.35)
            .animation(.easeInOut(duration: 0.2), value: isOn)
        }
        .padding(6)
        .frame(minWidth: 130)
        .glassPanel(cornerRadius: AppTheme.cornerRadiusButton)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusButton)
                .frame(height: 2)
                .foregroundColor(isOn ? color.opacity(0.6) : Color.clear),
            alignment: .top
        )
    }

    @ViewBuilder
    private var presetControl: some View {
        if showsLayoutForSnapshot {
            Text("PRESET ▾")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
                .fixedSize()
        } else {
            Menu {
                ForEach(presets) { preset in
                    Button(preset.name) {
                        onPreset(preset.id)
                    }
                    .accessibilityIdentifier("\(presetIdentifier).\(preset.id)")
                }
            } label: {
                Text("PRESET ▾")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .fixedSize()
            .accessibilityIdentifier(presetIdentifier)
        }
    }
}

struct EffectMenuItem: Identifiable {
    let id: String
    let name: String
}

/// Names next to PRESET and SCENE. A knob move clears that block and the scene.
@MainActor
@Observable
final class EffectPresetLabels {
    var reverb: String?
    var delay: String?
    var distortion: String?
    var eq: String?
    var compressor: String?
    var scene: String?

    struct Snapshot: Equatable, Sendable {
        var reverb: String?
        var delay: String?
        var distortion: String?
        var eq: String?
        var compressor: String?
        var scene: String?
    }

    enum Block {
        case reverb, delay, distortion, eq, compressor
    }

    func snapshot() -> Snapshot {
        Snapshot(reverb: reverb, delay: delay, distortion: distortion, eq: eq, compressor: compressor, scene: scene)
    }

    func restore(_ snapshot: Snapshot) {
        reverb = snapshot.reverb
        delay = snapshot.delay
        distortion = snapshot.distortion
        eq = snapshot.eq
        compressor = snapshot.compressor
        scene = snapshot.scene
    }

    func clear(_ block: Block) {
        switch block {
        case .reverb: reverb = nil
        case .delay: delay = nil
        case .distortion: distortion = nil
        case .eq: eq = nil
        case .compressor: compressor = nil
        }
        scene = nil
    }
}

/// Applies a preset or a scene and registers Cmd+Z as "Effect Preset".
/// `read` and `commit` stay on this object so the undo closure does not capture them.
@MainActor
final class EffectPresetEditSession {
    let labels = EffectPresetLabels()
    var read: () -> EffectsChain = { EffectsChain() }
    var commit: (EffectsChain) -> Void = { _ in }
    var undoManager: UndoManager?

    func chooseScene(_ scene: EffectPresets.Scene, bpm: Double) {
        apply { chain, labels in
            scene.apply(to: &chain, bpm: bpm)
            labels.scene = scene.name
            labels.reverb = nil
            labels.delay = nil
            labels.distortion = nil
            labels.eq = nil
            labels.compressor = nil
        }
    }

    /// Applies the saved copy. A synced delay follows the tempo playing now.
    func chooseUserScene(_ scene: EffectScene, bpm: Double) {
        apply { chain, labels in
            chain = scene.chain
            if chain.delay.syncBeats != nil {
                chain.delay.retime(bpm: bpm)
            }
            labels.scene = scene.name
            labels.reverb = nil
            labels.delay = nil
            labels.distortion = nil
            labels.eq = nil
            labels.compressor = nil
        }
    }

    func chooseCompressor(_ preset: EffectPresets.CompressorPreset) {
        apply { chain, labels in
            preset.apply(to: &chain, bpm: 120)
            labels.compressor = preset.name
            labels.scene = nil
        }
    }

    func chooseReverb(_ preset: EffectPresets.ReverbPreset, bpm: Double) {
        apply { chain, labels in
            preset.apply(to: &chain, bpm: bpm)
            labels.reverb = preset.name
            labels.scene = nil
        }
    }

    func chooseDelay(_ preset: EffectPresets.DelayPreset, bpm: Double) {
        apply { chain, labels in
            preset.apply(to: &chain, bpm: bpm)
            labels.delay = preset.name
            labels.scene = nil
        }
    }

    func chooseDistortion(_ preset: EffectPresets.DistortionPreset, bpm: Double) {
        apply { chain, labels in
            preset.apply(to: &chain, bpm: bpm)
            labels.distortion = preset.name
            labels.scene = nil
        }
    }

    func chooseEQ(_ preset: EffectPresets.EQPreset) {
        apply { chain, labels in
            preset.apply(to: &chain, bpm: 120)
            labels.eq = preset.name
            labels.scene = nil
        }
    }

    func apply(mutate: (inout EffectsChain, EffectPresetLabels) -> Void) {
        let previousChain = read()
        let previousNames = labels.snapshot()
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { session in
                MainActor.assumeIsolated {
                    session.apply { chain, labels in
                        chain = previousChain
                        labels.restore(previousNames)
                    }
                }
            }
            undoManager.setActionName("Effect Preset")
        }
        var chain = read()
        mutate(&chain, labels)
        commit(chain)
    }
}
