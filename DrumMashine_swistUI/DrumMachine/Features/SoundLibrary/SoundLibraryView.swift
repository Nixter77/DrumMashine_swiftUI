import SwiftUI

private enum LibraryPage: Hashable {
    case voice(SoundPreset.VoiceKind)
    case user
    case kits
    case patterns
}

// MARK: - Sound Library View
struct SoundLibraryView: View {
    @Bindable var sequencer: SequencerEngine
    @Environment(\.undoManager) private var undoManager

    @State private var page: LibraryPage = .voice(.kick)
    @State private var styleFilter: FactoryStyle? = nil
    @State private var query = ""
    @State private var selectedPreset: SoundPreset? = nil
    @State private var justAssigned: UUID? = nil
    @State private var presetPendingRename: SoundPreset?
    @State private var renameDraft = ""
    @State private var importingSample = false
    @State private var showSampleRights = false

    private let library = SoundLibraryManager.shared
    private let styleChips: [FactoryStyle?] = [.classic808, .style909, .acoustic, .lofi, .trap, nil]
    /// ImageRenderer does not draw `ScrollView` or `TextField`. Snapshots use plain stacks.
    private let snapshotLayout: Bool

    init(sequencer: SequencerEngine, startsOnPatterns: Bool = false, snapshotLayout: Bool = false) {
        self.sequencer = sequencer
        self.snapshotLayout = snapshotLayout
        if startsOnPatterns {
            _page = State(initialValue: .patterns)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            libraryHeader
            
            Divider()
                .overlay(AppTheme.accent.opacity(0.15))
            
            libraryTabs
            if case .voice = page {
                styleChipRow
            }
            
            Divider()
                .overlay(AppTheme.hairline.opacity(0.05))
            
            if page == .kits {
                kitList
            } else if page == .patterns {
                patternList
            } else {
                soundGrid
            }
            
            // ── Assignment Footer ──
            if let preset = selectedPreset {
                assignmentFooter(preset: preset)
            }
        }
        .glassPanel()
        .onAppear {
            selectedPreset = listedPresets().first
        }
        .alert(
            "Переименовать",
            isPresented: Binding(
                get: { presetPendingRename != nil },
                set: { if !$0 { presetPendingRename = nil } }
            )
        ) {
            TextField("Имя", text: $renameDraft)
            Button("Сохранить") {
                if let id = presetPendingRename?.id {
                    UserPresetStore.shared.rename(id: id, to: renameDraft)
                    UserPresetStore.shared.flush()
                    selectedPreset = UserPresetStore.shared.preset(id: id)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $importingSample,
            allowedContentTypes: SampleImporter.readableTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                SampleImporter.storeInLibrary(url, voice: .perc)
            }
        }
        .confirmationDialog("Импорт сэмпла", isPresented: $showSampleRights, titleVisibility: .visible) {
            Button("Выбрать файл") { importingSample = true }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(SampleImporter.rightsLine)
        }
    }
    
    // MARK: - Header
    private var libraryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(.callout, weight: .semibold))
                .foregroundColor(AppTheme.accent)
            
            Text("SOUND LIBRARY")
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundColor(AppTheme.textPrimary)
            
            Spacer()

            if page != .kits {
                if snapshotLayout {
                    Text("Поиск")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(maxWidth: 140, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.hairline.opacity(0.08)))
                } else {
                    TextField("Поиск", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: 140)
                }
            }
            
            Text("\(library.availableSounds.count + UserPresetStore.shared.presets.count) SOUNDS")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(AppTheme.accent.opacity(0.1))
                        .overlay(Capsule().stroke(AppTheme.accent.opacity(0.2), lineWidth: 1))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private var libraryTabs: some View {
        // Two rows of five. A hidden horizontal scroller clipped every tab after SNARE
        // on a mouse (no sideways scroll), so hats, toms and cymbals could not be reached.
        let voices = LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 34), spacing: 4), count: 5),
            spacing: 4
        ) {
            ForEach(SoundPreset.VoiceKind.allCases, id: \.self) { voice in
                LibraryTabButton(
                    title: tabTitle(voice),
                    count: voiceCount(voice),
                    isSelected: page == .voice(voice),
                    color: voiceColor(voice)
                ) {
                    show(.voice(voice))
                }
            }
        }
        // USER, KITS and PATTERNS stay on screen at the 260 pt inspector.
        // A horizontal scroller clips PATTERNS down to a few points at 1100.
        let modes = HStack(spacing: 4) {
            LibraryTabButton(
                title: "USER",
                count: UserPresetStore.shared.presets.count,
                isSelected: page == .user,
                color: AppTheme.accent
            ) {
                show(.user)
            }
            LibraryTabButton(
                title: "KITS",
                count: FactoryKits.all().count + KitStore.shared.kits.count,
                isSelected: page == .kits,
                color: AppTheme.accentSecondary
            ) {
                show(.kits)
            }
            LibraryTabButton(
                title: "PATTERNS",
                count: FactoryPatterns.all().count,
                isSelected: page == .patterns,
                color: AppTheme.accent,
                identifier: "library.page.patterns"
            ) {
                show(.patterns)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            voices
                .accessibilityIdentifier("library.tabs")
            modes
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var styleChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(styleChips.indices, id: \.self) { index in
                    let chip = styleChips[index]
                    let selected = styleFilter == chip
                    Button(chip?.title ?? "ВСЕ") {
                        styleFilter = chip
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(selected ? AppTheme.onAccent : AppTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(selected ? AppTheme.accent : AppTheme.hairline.opacity(0.08)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var soundGrid: some View {
        let sounds = listedPresets()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                if page == .user {
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Импорт…") { showSampleRights = true }
                            .buttonStyle(.plain)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(AppTheme.accent)
                        Text(SampleImporter.rightsLine)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(AppTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gridCellColumns(2)
                }
                if sounds.isEmpty {
                    Text(page == .user && trimmedQuery.isEmpty ? "Нет своих пресетов" : "Ничего не найдено")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .gridCellColumns(2)
                }
                ForEach(sounds) { preset in
                    SoundPresetCell(
                        preset: preset,
                        isSelected: selectedPreset?.id == preset.id,
                        isJustAssigned: justAssigned == preset.id
                    ) {
                        withAnimation(.spring(response: 0.2)) {
                            selectedPreset = preset
                        }
                        AudioEngineManager.shared.previewSound(preset: preset)
                    } onDoubleTap: {
                        guard sequencer.assignToMatchingVoice(preset) != nil else { return }
                        flashAssigned(preset.id)
                    }
                    .draggable(preset.id.uuidString)
                    .contextMenu {
                        Button("Сохранить копию в USER") {
                            guard let copy = UserPresetStore.shared.saveCopy(of: preset) else { return }
                            UserPresetStore.shared.flush()
                            query = ""
                            show(.user)
                            selectedPreset = copy
                        }
                        if page == .user {
                            Button("Переименовать") {
                                renameDraft = preset.name
                                presetPendingRename = preset
                            }
                            Button("Удалить") {
                                UserPresetStore.shared.delete(id: preset.id)
                                UserPresetStore.shared.flush()
                                if selectedPreset?.id == preset.id {
                                    selectedPreset = UserPresetStore.shared.presets.first
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard page == .user, let url = urls.first else { return false }
            Task { @MainActor in
                SampleImporter.storeInLibrary(url, voice: .perc)
            }
            return true
        }
    }

    private var kitList: some View {
        let factory = FactoryKits.all()
        let saved = KitStore.shared.kits
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(factory) { kit in
                    kitButton(kit)
                }
                if !saved.isEmpty {
                    Divider().overlay(AppTheme.hairline.opacity(0.08)).padding(.vertical, 4)
                    ForEach(saved) { kit in
                        kitButton(kit)
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
    }

    private func kitButton(_ kit: DrumKit) -> some View {
        Button {
            sequencer.loadKit(kit, undoManager: undoManager)
        } label: {
            HStack {
                Text(kit.name)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(kit.sounds.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.surfaceElevated.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Assignment Footer
    private func assignmentFooter(preset: SoundPreset) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(AppTheme.accent.opacity(0.15))
            
            HStack(spacing: 10) {
                // Preset info
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    HStack(spacing: 6) {
                        // ADSR mini display
                        ADSRMiniDisplay(preset: preset)
                        
                        if preset.pitch != 0 {
                            Text(preset.pitch > 0 ? "+\(Int(preset.pitch))st" : "\(Int(preset.pitch))st")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(AppTheme.accentSecondary)
                        }
                    }
                }
                
                Spacer()
                
                // Preview button
                Button(action: {
                    AudioEngineManager.shared.previewSound(preset: preset)
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
                
                // Track assignment picker
                Menu {
                    ForEach(sequencer.tracks.indices, id: \.self) { idx in
                        Button(action: {
                            assignPreset(preset, toTrack: idx)
                        }) {
                            Label(
                                "Track \(idx + 1): \(sequencer.tracks[idx].soundPreset.name)",
                                systemImage: "arrow.right.circle"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("ASSIGN")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(AppTheme.accent)
                            .shadow(color: AppTheme.accent.opacity(0.4), radius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - Assign Preset to Track
    private func assignPreset(_ preset: SoundPreset, toTrack trackIndex: Int) {
        sequencer.assign(preset, toTrack: trackIndex)
        flashAssigned(preset.id)
    }

    private func flashAssigned(_ id: UUID) {
        withAnimation(.spring(response: 0.3)) {
            justAssigned = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { justAssigned = nil }
        }
    }

    private func show(_ next: LibraryPage) {
        // listedPresets reads page, so resolve the selection after the page changes.
        page = next
        let first = listedPresets().first
        withAnimation(.spring(response: 0.25)) {
            selectedPreset = first
        }
    }

    private func listedPresets() -> [SoundPreset] {
        switch page {
        case .voice(let voice):
            return library.presets(for: voice, style: styleFilter).filter { nameMatches($0.name) }
        case .user:
            return UserPresetStore.shared.presets.filter { nameMatches($0.name) }
        case .kits, .patterns:
            return []
        }
    }

    private var patternSections: [(genre: String, specs: [FactoryPatternSpec])] {
        var sections: [(genre: String, specs: [FactoryPatternSpec])] = []
        for spec in FactoryPatterns.all() where patternMatches(spec) {
            if let last = sections.indices.last, sections[last].genre == spec.genre {
                sections[last].specs.append(spec)
            } else {
                sections.append((genre: spec.genre, specs: [spec]))
            }
        }
        return sections
    }

    private func patternMatches(_ spec: FactoryPatternSpec) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return spec.name.localizedStandardContains(trimmed)
            || spec.genre.localizedStandardContains(trimmed)
    }

    @ViewBuilder
    private var patternList: some View {
        let sections = patternSections
        let stack = VStack(alignment: .leading, spacing: 6) {
            if sections.isEmpty {
                Text("Ничего не найдено")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(sections, id: \.genre) { section in
                Text(section.genre.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.top, 4)
                ForEach(section.specs) { spec in
                    patternRow(spec)
                }
            }
        }
        .padding(10)
        if snapshotLayout {
            stack
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) { stack }
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("pattern.factory.list")
        }
    }

    private func patternRow(_ spec: FactoryPatternSpec) -> some View {
        let loaded = FactoryPatterns.matchesLoadedGrid(
            tracks: sequencer.tracks,
            stepCount: sequencer.stepCount,
            spec: spec
        )
        return HStack(spacing: 4) {
            rowButton(spec, loaded: loaded)
            if loaded {
                // Outside the button: a button's accessibility element hides child identifiers.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accentSuccess)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loaded")
                    .accessibilityIdentifier("pattern.factory.loaded.\(spec.id)")
            }
        }
    }

    private func rowButton(_ spec: FactoryPatternSpec, loaded: Bool) -> some View {
        Button {
            loadFactory(spec, notesOnly: false)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.name)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(Int(spec.bpm)) BPM")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                }
                Spacer(minLength: 4)
                Text(FactoryPatterns.kitName(for: spec))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(loaded ? AppTheme.accent.opacity(0.16) : AppTheme.surfaceElevated.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.name)
        .accessibilityIdentifier("pattern.factory.\(spec.id)")
        .focusable()
        .onKeyPress(.return) {
            loadFactory(spec, notesOnly: false)
            return .handled
        }
        .contextMenu {
            Button("Загрузить только ноты") {
                loadFactory(spec, notesOnly: true)
            }
        }
    }

    private func loadFactory(_ spec: FactoryPatternSpec, notesOnly: Bool) {
        PatternManager.shared.loadFactoryPattern(
            spec,
            notesOnly: notesOnly,
            into: sequencer,
            undoManager: undoManager
        )
    }

    private func voiceCount(_ voice: SoundPreset.VoiceKind) -> Int {
        library.presets(for: voice, style: styleFilter).count
    }

    private func styleMatches(_ preset: SoundPreset) -> Bool {
        guard let styleFilter else { return true }
        return preset.style == styleFilter
    }

    private func nameMatches(_ name: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.localizedStandardContains(trimmed)
    }

    private func tabTitle(_ voice: SoundPreset.VoiceKind) -> String {
        switch voice {
        case .kick: return "KICK"
        case .snare: return "SNARE"
        case .closedHat: return "HH CL"
        case .openHat: return "HH OP"
        case .clap: return "CLAP"
        case .tom: return "TOM"
        case .ride: return "RIDE"
        case .crash: return "CRASH"
        case .perc: return "PERC"
        case .fx: return "FX"
        }
    }

    private func voiceColor(_ voice: SoundPreset.VoiceKind) -> Color {
        switch voice {
        case .kick: return Color(hex: "FF6B35")
        case .snare: return Color(hex: "FFD60A")
        case .closedHat, .openHat: return Color(hex: "30D158")
        case .clap, .perc: return AppTheme.accent
        case .tom: return Color(hex: "0A84FF")
        case .ride, .crash: return Color(hex: "BF5AF2")
        case .fx: return AppTheme.accentSecondary
        }
    }
}

private struct LibraryTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let color: Color
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(isSelected ? color : AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? AppTheme.onAccent : AppTheme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(isSelected ? color : AppTheme.hairline.opacity(0.08)))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: isSelected)
        .modifier(LibraryTabIdentifier(identifier: identifier))
    }
}

/// An empty identifier would collide with unnamed controls. Voice tabs stay unlabeled.
private struct LibraryTabIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

// MARK: - Sound Preset Cell
struct SoundPresetCell: View {
    let preset: SoundPreset
    let isSelected: Bool
    let isJustAssigned: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    
    private var catColor: Color {
        switch preset.category {
        case .kick:        return Color(hex: "FF6B35")
        case .snare:       return Color(hex: "FFD60A")
        case .hihat:       return Color(hex: "30D158")
        case .percussion:  return AppTheme.accent
        case .cymbals:     return Color(hex: "BF5AF2")
        case .fx:          return AppTheme.accentSecondary
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(catColor.opacity(isSelected ? 0.25 : 0.1))
                        .frame(width: 30, height: 30)
                    Image(systemName: preset.category.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(catColor)
                }
                
                // Name + ADSR hint
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                        .lineLimit(1)
                    if SampleImporter.isMissing(preset) {
                        Text("файл не найден")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(AppTheme.accentMute)
                    }
                    
                    // Mini waveform bar (decay length visual)
                    DecayBar(decay: preset.decay, color: catColor)
                }
                
                Spacer(minLength: 0)
                
                // Assigned checkmark
                if isJustAssigned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.accentSuccess)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? catColor.opacity(0.15)
                            : AppTheme.surfaceElevated.opacity(0.6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? catColor.opacity(0.5) : AppTheme.hairline.opacity(0.05),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .shadow(color: isSelected ? catColor.opacity(0.2) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) { onDoubleTap() }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Decay Bar (visual hint of sound length)
struct DecayBar: View {
    let decay: Float
    let color: Color
    
    // Map decay (0.02...1.2) to bar width fraction (0.1...1.0)
    private var fraction: Double {
        let clamped = Double(min(1.2, max(0.02, decay)))
        return 0.1 + (clamped / 1.2) * 0.9
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.hairline.opacity(0.06))
                    .frame(height: 3)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * fraction, height: 3)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - ADSR Mini Display
struct ADSRMiniDisplay: View {
    let preset: SoundPreset
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(["A", "D", "S", "R"], id: \.self) { label in
                let value: Float = {
                    switch label {
                    case "A": return preset.attack
                    case "D": return preset.decay
                    case "S": return preset.sustain
                    case "R": return preset.release
                    default: return 0
                    }
                }()
                
                VStack(spacing: 1) {
                    Text(label)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppTheme.accent.opacity(0.6))
                        .frame(width: 4, height: CGFloat(value * 20).clampedTo(2...20))
                }
            }
        }
    }
}

// MARK: - CGFloat clamp helper (avoids conflict with Swift stdlib clamped(to:))
extension CGFloat {
    func clampedTo(_ range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
