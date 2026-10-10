import SwiftUI

/// Transport across the full window: play, tempo, pattern slots, and the
/// sequencer controls. A narrow window stacks the controls on a second row.
struct TransportBarView: View {
    @Bindable var sequencer: SequencerEngine
    @Environment(\.undoManager) private var undoManager
    @State private var kitNameDraft = ""
    @State private var showingKitSave = false
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideRow
                .frame(minWidth: AppLayout.transportWideMinWidth)
            compactRows
        }
        .frame(maxWidth: .infinity, minHeight: AppLayout.transportBarHeight, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassPanel()
    }

    private var wideRow: some View {
        HStack(spacing: 12) {
            themeToggle
            playButton
            FillControlView(sequencer: sequencer)
            bpmControls
            PatternSlotsView(sequencer: sequencer)
            barDivider
            swingControl
            humanizeControl
            GrooveControlView(sequencer: sequencer)
            recordControl
            Spacer(minLength: 8)
            patternOps
        }
    }

    private var compactRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                themeToggle
                playButton
                FillControlView(sequencer: sequencer)
                bpmControls
                PatternSlotsView(sequencer: sequencer)
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                swingControl
                humanizeControl
                GrooveControlView(sequencer: sequencer)
                recordControl
                Spacer(minLength: 8)
                patternOps
            }
            .frame(minHeight: AppLayout.sequencerControlBarHeight)
        }
    }

    private var playButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2)) {
                sequencer.togglePlayPause()
            }
        }) {
            ZStack {
                if theme.style.isLight {
                    let c = sequencer.isPlaying ? AppTheme.accentMute : AppTheme.accentSuccess
                    CandyFill(color: c, cornerRadius: AppLayout.playButtonSize / 2,
                              glow: 0.5)
                        .frame(width: AppLayout.playButtonSize, height: AppLayout.playButtonSize)
                    Image(systemName: sequencer.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .offset(x: sequencer.isPlaying ? 0 : 2)
                } else {
                Circle()
                    .fill(
                        sequencer.isPlaying
                            ? AppTheme.accentMute.opacity(0.22)
                            : AppTheme.accentSuccess.opacity(0.22)
                    )
                    .frame(width: AppLayout.playButtonSize, height: AppLayout.playButtonSize)
                    .overlay(
                        Circle()
                            .stroke(
                                sequencer.isPlaying ? AppTheme.accentMute : AppTheme.accentSuccess,
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: sequencer.isPlaying
                            ? AppTheme.accentMute.opacity(0.5)
                            : AppTheme.accentSuccess.opacity(0.4),
                        radius: 16
                    )
                Image(systemName: sequencer.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(sequencer.isPlaying ? AppTheme.accentMute : AppTheme.accentSuccess)
                    .offset(x: sequencer.isPlaying ? 0 : 2)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .layoutPriority(2)
        .accessibilityLabel(sequencer.isPlaying ? "Stop" : "Play")
        .accessibilityIdentifier("transport.play")
    }

    private var bpmControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button(action: {
                    sequencer.bpm = max(40, sequencer.bpm - 1)
                }) {
                    Image(systemName: "minus")
                        .font(.system(.callout, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 1) {
                    Text("\(Int(sequencer.bpm))")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.style.isLight ? Color(hex: "1FB84A") : .white)
                        .shadow(color: theme.style.isLight ? Color(hex: "36E067").opacity(0.55) : .clear, radius: 4)
                        .contentTransition(.numericText())
                        .frame(width: 68)
                        .accessibilityIdentifier("transport.bpm")
                        .accessibilityValue("\(Int(sequencer.bpm))")
                    Text("BPM")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(AppTheme.textTertiary)
                        .tracking(2)
                }

                Button(action: {
                    sequencer.bpm = min(300, sequencer.bpm + 1)
                }) {
                    Image(systemName: "plus")
                        .font(.system(.callout, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transport.bpm.plus")
                .accessibilityLabel("Increase BPM")
            }

            Button(action: {
                sequencer.tapTempo()
            }) {
                Text("TAP TEMPO")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 96)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(AppTheme.accentSecondary.opacity(theme.style.isLight ? 0.9 : 0.35))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(AppTheme.accentSecondary.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .fixedSize()
    }

    private var themeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35)) { theme.toggle() }
        } label: {
            Image(systemName: theme.style.isLight ? "moon.fill" : "sun.max.fill")
                .font(.system(.callout, weight: .semibold))
                .foregroundColor(theme.style.isLight ? AppTheme.textSecondary : AppTheme.accentWarning)
                .frame(width: 30, height: 30)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.style.isLight ? "Тёмная тема" : "Светлая тема Studio Light")
        .accessibilityIdentifier("transport.theme")
    }

    private var swingControl: some View {
        HStack(spacing: 8) {
            Text("SWING")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(AppTheme.textTertiary)
            Slider(value: $sequencer.swing, in: 0...100, step: 5)
                .tint(AppTheme.accent)
                .frame(minWidth: 70, idealWidth: 100, maxWidth: 140)
            Text("\(Int(sequencer.swing))%")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 32)
                .accessibilityIdentifier("transport.swing")
                .accessibilityValue("\(Int(sequencer.swing))")
        }
    }

    private var humanizeControl: some View {
        HStack(spacing: 8) {
            Text("HUMAN")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(AppTheme.textTertiary)
            Slider(value: $sequencer.humanize, in: 0...100, step: 5)
                .tint(Color(hex: "30D158"))
                .frame(minWidth: 70, idealWidth: 100, maxWidth: 140)
            Text("\(Int(sequencer.humanize))%")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 32)
        }
    }

    private var recordControl: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sequencer.recordMode != .off ? AppTheme.accentMute : Color.gray.opacity(0.3))
                .frame(width: 7, height: 7)
                .shadow(color: sequencer.recordMode != .off ? AppTheme.accentMute.opacity(0.7) : .clear, radius: 4)
            Text("REC")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(sequencer.recordMode != .off ? AppTheme.accentMute : AppTheme.textTertiary)
            Picker("", selection: $sequencer.recordMode) {
                ForEach(RecordMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).font(.system(.caption, design: .monospaced)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 150)
        }
    }

    private var patternOps: some View {
        HStack(spacing: 8) {
            kitMenu
            Button(action: {
                PatternManager.shared.performUndoable(
                    sequencer: sequencer,
                    undoManager: undoManager,
                    actionName: "Clear Pattern"
                ) {
                    sequencer.clearPattern()
                }
            }) {
                Label("CLEAR", systemImage: "trash")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.surfaceElevated)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: {
                PatternManager.shared.performUndoable(
                    sequencer: sequencer,
                    undoManager: undoManager,
                    actionName: "Randomize Pattern"
                ) {
                    sequencer.randomizePattern()
                }
            }) {
                Label("RANDOM", systemImage: "dice")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.surfaceElevated)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .fixedSize()
        .alert("Сохранить кит как…", isPresented: $showingKitSave) {
            TextField("Имя", text: $kitNameDraft)
            Button("Сохранить") { saveCurrentKit() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Восемь пэдов записываются копией.")
        }
    }

    private var kitMenu: some View {
        Menu {
            ForEach(FactoryKits.all()) { kit in
                Button(kit.name) {
                    sequencer.loadKit(kit, undoManager: undoManager)
                }
            }
            if !KitStore.shared.kits.isEmpty {
                Divider()
                ForEach(KitStore.shared.kits) { kit in
                    Button(kit.name) {
                        sequencer.loadKit(kit, undoManager: undoManager)
                    }
                }
            }
            Divider()
            Button("Сохранить кит как…") {
                kitNameDraft = sequencer.loadedKitName ?? ""
                showingKitSave = true
            }
        } label: {
            Text(sequencer.kitBadge ?? "КИТ")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 108)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.surfaceElevated)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("transport.kit")
        .accessibilityLabel(sequencer.kitBadge ?? "Кит")
    }

    private func saveCurrentKit() {
        let name = kitNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let kit = DrumKit(
            id: UUID(),
            name: name,
            sounds: sequencer.tracks.map(\.soundPreset)
        )
        KitStore.shared.save(kit)
        KitStore.shared.flush()
        sequencer.markKitSaved(named: name)
    }

    private var barDivider: some View {
        Divider().frame(height: 22).overlay(Color.gray.opacity(0.3))
    }
}

#Preview {
    TransportBarView(sequencer: SequencerEngine())
        .padding()
        .background(AppTheme.background)
}
