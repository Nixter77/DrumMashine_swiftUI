import SwiftUI
// MARK: - Pattern Slots View (A/B/C/D, live slot)
struct PatternSlotsView: View {
    @Bindable var sequencer: SequencerEngine
    private var patternManager: PatternManager { PatternManager.shared }
    @Environment(\.undoManager) private var undoManager
    @State private var showSaveConfirm: Int? = nil
    @State private var renameSlot: Int? = nil
    @State private var renameText = ""

    private let slotNames = ["A", "B", "C", "D"]

    var body: some View {
        HStack(spacing: 8) {
            Text("PAT")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(AppTheme.textTertiary)

            ForEach(0..<4, id: \.self) { slot in
                PatternSlotButton(
                    slot: slot,
                    isActive: patternManager.activePatternIndex == slot,
                    hasContent: patternManager.hasContent(slot: slot),
                    showSaveConfirm: showSaveConfirm == slot,
                    onTap: {
                        withAnimation(.spring(response: 0.2)) {
                            patternManager.selectSlot(slot, in: sequencer)
                        }
                    },
                    onCopy: { destination in
                        patternManager.copyActivePattern(to: destination, from: sequencer)
                        flash(destination)
                    },
                    onClear: {
                        patternManager.clearSlot(slot, sequencer: sequencer, undoManager: undoManager)
                    },
                    onRename: {
                        renameText = patternManager.patterns[slot].name
                        renameSlot = slot
                    }
                )
            }

            Button(action: {
                let slot = patternManager.copyActivePattern(from: sequencer)
                flash(slot)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(.caption2))
                    .foregroundColor(AppTheme.textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Copy into the next empty slot")
        }
        .alert("Переименовать", isPresented: renamePresented) {
            TextField("Имя", text: $renameText)
            Button("Сохранить") {
                if let slot = renameSlot {
                    patternManager.renameSlot(slot, to: renameText)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameSlot != nil },
            set: { if !$0 { renameSlot = nil } }
        )
    }

    private func flash(_ slot: Int) {
        withAnimation(.spring(response: 0.2)) {
            showSaveConfirm = slot
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { showSaveConfirm = nil }
        }
    }
}

// MARK: - Individual Pattern Slot Button
struct PatternSlotButton: View {
    let slot: Int
    let isActive: Bool
    let hasContent: Bool
    let showSaveConfirm: Bool
    let onTap: () -> Void
    let onCopy: (Int) -> Void
    let onClear: () -> Void
    let onRename: () -> Void

    private let slotNames = ["A", "B", "C", "D"]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isActive
                        ? AppTheme.accent.opacity(0.2)
                        : (hasContent ? AppTheme.surfaceElevated : AppTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isActive ? AppTheme.accent : (hasContent ? AppTheme.accent.opacity(0.2) : Color.gray.opacity(0.2)),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )

            if showSaveConfirm {
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.accentSuccess.opacity(0.3))
                    .transition(.opacity)
            }

            VStack(spacing: 2) {
                Text(slotNames[slot])
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(
                        showSaveConfirm ? AppTheme.accentSuccess :
                        (isActive ? AppTheme.accent : (hasContent ? AppTheme.textSecondary : AppTheme.textTertiary))
                    )

                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle()
                            .fill(hasContent ? AppTheme.accent.opacity(0.5) : Color.gray.opacity(0.2))
                            .frame(width: 2, height: 2)
                    }
                }
            }
        }
        .frame(width: 36, height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pattern \(slotNames[slot])")
        .accessibilityIdentifier("pattern.slot.\(slotNames[slot])")
        .accessibilityAddTraits(.isButton)
        .help("Слот \(slotNames[slot]): клик загружает, правый клик — копировать, очистить или переименовать")
        .contextMenu {
            Menu("Копировать в…") {
                ForEach(0..<4, id: \.self) { destination in
                    Button(slotNames[destination]) { onCopy(destination) }
                }
            }
            Button("Очистить", action: onClear)
            Button("Переименовать", action: onRename)
        }
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.spring(response: 0.2), value: isActive)
        .shadow(color: isActive ? AppTheme.accent.opacity(0.3) : .clear, radius: 6)
        .onTapGesture { onTap() }
    }
}

#Preview {
    PatternSlotsView(sequencer: SequencerEngine())
        .padding()
        .background(AppTheme.background)
}
