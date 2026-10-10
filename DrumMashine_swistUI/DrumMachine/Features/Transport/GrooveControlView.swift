import SwiftUI

/// GROOVE pill in the transport: pick a groove, open the popover for strength / timing / velocity / random,
/// per-track switches, extract from the pattern and bake into it.
struct GrooveControlView: View {
    @Bindable var sequencer: SequencerEngine
    @Environment(\.undoManager) private var undoManager
    @State private var showingDetails = false

    private var isOn: Bool { sequencer.grooveSettings.grooveID != FactoryGrooves.cleanID }
    private var tint: Color { Color(hex: "BF5AF2") }

    var body: some View {
        HStack(spacing: 6) {
            Text("GROOVE")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(isOn ? tint : AppTheme.textTertiary)
            Menu {
                Section("Заводские") {
                    ForEach(FactoryGrooves.all) { g in choice(g) }
                }
                if !UserGrooveStore.shared.grooves.isEmpty {
                    Section("Мои") {
                        ForEach(UserGrooveStore.shared.grooves) { g in choice(g) }
                    }
                    if let active = sequencer.activeGroove,
                       UserGrooveStore.shared.grooves.contains(where: { $0.id == active.id }) {
                        Button("Удалить «\(active.name)»", role: .destructive) {
                            UserGrooveStore.shared.delete(id: active.id)
                            setSettings { $0.grooveID = FactoryGrooves.cleanID }
                        }
                    }
                }
            } label: {
                Text(sequencer.activeGroove?.name ?? "Чистый")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(isOn ? tint.opacity(0.18) : AppTheme.hairline.opacity(0.08)))
            .accessibilityIdentifier("transport.groove")

            Button { showingDetails.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundColor(isOn ? tint : AppTheme.textTertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Настройки грува")
            .popover(isPresented: $showingDetails, arrowEdge: .bottom) { details }
        }
    }

    private func choice(_ g: GrooveTemplate) -> some View {
        Button {
            setSettings { $0.grooveID = g.id }
        } label: {
            if g.id == sequencer.grooveSettings.grooveID { Label(g.name, systemImage: "checkmark") } else { Text(g.name) }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GROOVE QUANTIZE · \(sequencer.activeGroove?.name ?? "Чистый")")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(tint)
            HStack(spacing: 18) {
                knob("STRENGTH", \.amount)
                knob("TIMING", \.timing)
                knob("VELOCITY", \.velocity)
                knob("RANDOM", \.random)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Дорожки с грувом")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        let on = sequencer.grooveSettings.isTrackOn(i)
                        let color = i < AppTheme.padColors.count ? AppTheme.padColors[i] : tint
                        Button {
                            setSettings { s in
                                while s.perTrack.count < 8 { s.perTrack.append(true) }
                                s.perTrack[i].toggle()
                            }
                        } label: {
                            Text(i < sequencer.tracks.count ? String(sequencer.tracks[i].soundPreset.name.prefix(3)) : "\(i + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(on ? .white : AppTheme.textTertiary)
                                .frame(width: 34, height: 22)
                                .background(RoundedRectangle(cornerRadius: 5).fill(on ? color : AppTheme.hairline.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button("Извлечь из паттерна") { extract() }
                Button("Запечь в паттерн") { bake() }
                    .disabled(!isOn)
                    .help("Записать акценты грува в громкость шагов (тайминг остаётся на сетке)")
                Spacer()
                Button("Чистый") { setSettings { $0 = GrooveSettings() } }
            }
            .font(.system(.caption, design: .rounded))
        }
        .padding(16)
        .frame(width: 380)
    }

    private func knob(_ title: String, _ key: WritableKeyPath<GrooveSettings, Double>) -> some View {
        KnobView(
            value: Binding(
                get: { sequencer.grooveSettings[keyPath: key] },
                set: { sequencer.grooveSettings[keyPath: key] = max(0, min(100, $0)) }
            ),
            range: 0...100,
            title: title,
            color: tint,
            size: 44,
            valueFormatter: { "\(Int($0))%" }
        )
    }

    private func setSettings(_ change: (inout GrooveSettings) -> Void) {
        let before = sequencer.grooveSettings
        var next = before
        change(&next)
        guard next != before else { return }
        sequencer.grooveSettings = next
        registerSettingsUndo(before)
    }

    private func registerSettingsUndo(_ before: GrooveSettings) {
        guard let undoManager else { return }
        let engine = sequencer
        undoManager.registerUndo(withTarget: engine) { e in
            let redo = e.grooveSettings
            e.grooveSettings = before
            undoManager.registerUndo(withTarget: e) { $0.grooveSettings = redo }
        }
        undoManager.setActionName("Грув")
    }

    private func bake() {
        guard let before = sequencer.bakeGrooveVelocities() else { return }
        registerStateUndo(tracks: before.tracks, settings: before.settings, name: "Запечь грув")
    }

    /// Undo swaps tracks + settings back; redo swaps them forward again.
    private func registerStateUndo(tracks: [SequencerTrack], settings: GrooveSettings, name: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: sequencer) { e in
            let redoTracks = e.tracks, redoSettings = e.grooveSettings
            e.tracks = tracks
            e.grooveSettings = settings
            Self.registerSwap(undoManager, e, redoTracks, redoSettings, name)
        }
        undoManager.setActionName(name)
    }

    private static func registerSwap(_ um: UndoManager, _ e: SequencerEngine, _ t: [SequencerTrack], _ s: GrooveSettings, _ name: String) {
        um.registerUndo(withTarget: e) { e in
            let backT = e.tracks, backS = e.grooveSettings
            e.tracks = t
            e.grooveSettings = s
            registerSwap(um, e, backT, backS, name)
        }
        um.setActionName(name)
    }

    /// Undo removes the groove it created; redo puts the same groove back.
    private func extract() {
        let before = sequencer.grooveSettings
        let created = sequencer.extractGrooveFromPattern()
        guard let undoManager else { return }
        Self.registerExtract(undoManager, sequencer, created, before)
    }

    private static func registerExtract(_ um: UndoManager, _ e: SequencerEngine, _ g: GrooveTemplate, _ before: GrooveSettings) {
        um.registerUndo(withTarget: e) { e in
            let after = e.grooveSettings
            UserGrooveStore.shared.delete(id: g.id)
            e.grooveSettings = before
            um.registerUndo(withTarget: e) { e in
                let restored = UserGrooveStore.shared.add(g)
                var s = after
                s.grooveID = restored.id
                e.grooveSettings = s
                registerExtract(um, e, restored, before)
            }
        }
        um.setActionName("Извлечь грув")
    }
}
