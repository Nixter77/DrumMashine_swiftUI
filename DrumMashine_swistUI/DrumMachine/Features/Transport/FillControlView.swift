import SwiftUI

/// FILL: click = one fill at the end of the current loop; hold = fill while held.
/// The chevron menu picks the fill style and the auto-fill period.
struct FillControlView: View {
    @Bindable var sequencer: SequencerEngine
    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?

    private var tint: Color { Color(hex: "FF9F0A") }
    private var lit: Bool { sequencer.isFillActive }

    var body: some View {
        HStack(spacing: 2) {
            Text("FILL")
                .font(.system(.caption, design: .monospaced).weight(.heavy))
                .foregroundColor(lit ? .white : tint)
                .frame(width: 46, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(lit ? tint : tint.opacity(0.15))
                )
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.6), lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard pressStart == nil else { return }
                            pressStart = Date()
                            // Held longer than 250 ms: fill while held.
                            holdTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                guard !Task.isCancelled, pressStart != nil else { return }
                                sequencer.fillHeld = true
                            }
                        }
                        .onEnded { _ in
                            holdTask?.cancel()
                            if sequencer.fillHeld {
                                sequencer.fillHeld = false
                            } else {
                                sequencer.fillOnce.toggle()
                            }
                            pressStart = nil
                        }
                )
                .help("Клик — сбивка в конце такта, удержание — сбивка, пока держишь")
                .accessibilityIdentifier("transport.fill")
                .accessibilityAddTraits(.isButton)

            Menu {
                Picker("Сбивка", selection: $sequencer.fillStyle) {
                    ForEach(FillStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Автосбивка", selection: $sequencer.autoFillEvery) {
                    Text("Выкл").tag(0)
                    Text("Каждый 2-й такт").tag(2)
                    Text("Каждый 4-й такт").tag(4)
                    Text("Каждый 8-й такт").tag(8)
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(sequencer.autoFillEvery > 0 ? tint : AppTheme.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Стиль сбивки и автосбивка")
        }
        .fixedSize()
    }
}
