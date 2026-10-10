import SwiftUI
struct PadsGridView: View {
    var sequencer: SequencerEngine?
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    @State private var pads: [DrumPad] = [
        DrumPad(id: UUID(), name: "KICK",  iconName: "circle.fill",            colorHex: "FF453A", soundPresetId: UUID()),
        DrumPad(id: UUID(), name: "SNARE", iconName: "hexagon.fill",           colorHex: "FFD60A", soundPresetId: UUID()),
        DrumPad(id: UUID(), name: "HIHAT", iconName: "triangle.fill",          colorHex: "30D158", soundPresetId: UUID()),
        DrumPad(id: UUID(), name: "CLAP",  iconName: "hands.clap.fill",        colorHex: "5AC8FA", soundPresetId: UUID()),
        DrumPad(id: UUID(), name: "TOM",   iconName: "square.fill",            colorHex: "0A84FF", soundPresetId: UUID()),
        DrumPad(id: UUID(), name: "RIDE",  iconName: "circle.grid.cross.fill", colorHex: "BF5AF2", soundPresetId: UUID()),
        DrumPad(id: UUID(), name: "CRASH", iconName: "star.fill",              colorHex: "FF6B35", soundPresetId: UUID()),
        DrumPad(id: UUID(), name: "PERC",  iconName: "diamond.fill",           colorHex: "FF375F", soundPresetId: UUID())
    ]
    
    @ObservedObject private var router = SoundEditorRouter.shared
    /// Pads (long press) and sequencer track names (click) open the same editor.
    private var editingPadIndex: Int? {
        get { router.trackIndex }
        nonmutating set { router.trackIndex = newValue }
    }
    @State private var soundReloadTasks: [Int: Task<Void, Never>] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<8, id: \.self) { index in
                    DrumPadView(pad: pads[index], padIndex: index) { velocity in
                        AudioEngineManager.shared.trigger(trackIndex: index, velocity: velocity)
                        if let seq = sequencer {
                            Task { @MainActor in
                                seq.recordPadHit(trackIndex: index, velocity: velocity)
                            }
                        }
                    } onLongPress: {
                        withAnimation(.spring(response: 0.3)) {
                            editingPadIndex = index
                        }
                    } soundMenu: {
                        AnyView(soundMenu(track: index))
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first, let sequencer else { return false }
                        let track = index
                        Task { @MainActor in
                            SampleImporter.place(url, onTrack: track, sequencer: sequencer)
                        }
                        return true
                    }
                    .dropDestination(for: String.self) { values, _ in
                        guard let raw = values.first,
                              let id = UUID(uuidString: raw),
                              let sequencer else { return false }
                        let track = index
                        Task { @MainActor in
                            guard let preset = Self.libraryPreset(id: id) else { return }
                            sequencer.assign(preset, toTrack: track)
                        }
                        return true
                    }
                }
            }
            .padding(12)
            // Four columns and two rows of square pads, fitted to the column.
            .aspectRatio(2, contentMode: .fit)
        }
        .glassPanel()
        .sheet(isPresented: editingPresented) {
            editorSheet
        }
    }

    private var editingPresented: Binding<Bool> {
        Binding(
            get: { editingPadIndex != nil },
            set: { if !$0 { editingPadIndex = nil } }
        )
    }

    @ViewBuilder
    private var editorSheet: some View {
        if let idx = editingPadIndex, idx < (sequencer?.tracks.count ?? 0) {
            PadADSREditorView(
                preset: Binding(
                    get: {
                        sequencer?.tracks[idx].soundPreset
                            ?? SoundLibraryManager.shared.defaultPreset(forTrackIndex: idx)
                    },
                    set: { newValue in
                        sequencer?.tracks[idx].soundPreset = newValue
                        sequencer?.notePadSoundEdited()
                    }
                ),
                padColor: AppTheme.padColors[idx]
            ) {
                withAnimation(.spring(response: 0.3)) {
                    editingPadIndex = nil
                }
            }
            .frame(minWidth: 420, idealWidth: 470, maxWidth: 520)
            .onChange(of: sequencer?.tracks[idx].soundPreset) { _, updated in
                guard let updated else { return }
                scheduleSoundReload(track: idx, preset: updated)
            }
        }
    }

    /// Slider drags rewrite the preset many times. Reload the track buffer once the value settles.
    private func scheduleSoundReload(track: Int, preset: SoundPreset) {
        soundReloadTasks[track]?.cancel()
        soundReloadTasks[track] = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            AudioEngineManager.shared.loadSound(preset: preset, forTrack: track)
        }
    }

    @ViewBuilder
    private func soundMenu(track index: Int) -> some View {
        if let sequencer, sequencer.tracks.indices.contains(index) {
            let current = sequencer.tracks[index].soundPreset
            let sections = SoundLibraryManager.shared.pickerSections(
                forTrackVoice: current.resolvedVoice,
                users: UserPresetStore.shared.presets
            )
            Button("Edit sound…") { editingPadIndex = index }
            Divider()
            soundSection("Synth", sections.synth, track: index, current: current, sequencer: sequencer)
            soundSection("Acoustic", sections.acoustic, track: index, current: current, sequencer: sequencer)
            soundSection("User", sections.user, track: index, current: current, sequencer: sequencer)
        }
    }

    @ViewBuilder
    private func soundSection(
        _ title: String,
        _ presets: [SoundPreset],
        track: Int,
        current: SoundPreset,
        sequencer: SequencerEngine
    ) -> some View {
        if !presets.isEmpty {
            Section(title) {
                ForEach(presets) { preset in
                    Button {
                        sequencer.assign(preset, toTrack: track)
                    } label: {
                        if (current.basedOn ?? current.id) == preset.id {
                            Label(preset.name, systemImage: "checkmark")
                        } else {
                            Text(preset.name)
                        }
                    }
                }
            }
        }
    }

    private static func libraryPreset(id: UUID) -> SoundPreset? {
        if let preset = SoundLibraryManager.shared.availableSounds.first(where: { $0.id == id }) {
            return preset
        }
        return UserPresetStore.shared.preset(id: id)
    }
}
