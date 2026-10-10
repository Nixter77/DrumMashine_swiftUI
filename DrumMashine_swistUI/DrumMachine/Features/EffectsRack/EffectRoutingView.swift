import SwiftUI
import UniformTypeIdentifiers

/// Signal chain as blocks: Voices → five rack effects in the chosen order → Limiter → Out.
/// Drag a block onto another to put it before that one; arrows move it one step; the power dot bypasses it.
struct EffectRoutingView: View {
    let chain: EffectsChain
    let onChange: ((inout EffectsChain) -> Void) -> Void
    @State private var dropTarget: EffectsChain.EffectSlot?

    private var order: [EffectsChain.EffectSlot] { EffectsChain.sanitized(chain.order) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("МАРШРУТИЗАЦИЯ · ROUTING")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button("Default order") {
                    onChange { $0.order = EffectsChain.EffectSlot.defaultOrder }
                }
                .disabled(order == EffectsChain.EffectSlot.defaultOrder)
                .accessibilityIdentifier("routing.default")
            }
            HStack(spacing: 6) {
                fixedBlock("Voices", icon: "music.note")
                arrow
                ForEach(Array(order.enumerated()), id: \.element) { index, slot in
                    effectBlock(slot, index: index)
                    arrow
                }
                fixedBlock("Limiter", icon: "speedometer")
                arrow
                fixedBlock("Out", icon: "speaker.wave.2.fill")
            }
            Text("Перетащите блок, чтобы изменить порядок. Точка — вкл/обход.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(16)
        .background(AppTheme.background)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(AppTheme.textTertiary)
    }

    private func fixedBlock(_ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12))
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundColor(AppTheme.textSecondary)
        .frame(width: 58, height: 64)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surfaceElevated.opacity(0.6)))
    }

    private func effectBlock(_ slot: EffectsChain.EffectSlot, index: Int) -> some View {
        let on = chain.isOn(slot)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: slot.icon).font(.system(size: 11))
                Button {
                    onChange { $0.setOn(slot, !on) }
                } label: {
                    Circle()
                        .fill(on ? AppTheme.accent : AppTheme.textTertiary.opacity(0.4))
                        .frame(width: 9, height: 9)
                }
                .buttonStyle(.plain)
                .help(on ? "Bypass" : "Enable")
                .accessibilityLabel(on ? "\(slot.title) on" : "\(slot.title) bypassed")
                .accessibilityIdentifier("routing.power.\(slot.rawValue)")
            }
            Text(slot.title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                Button { onChange { $0.move(slot, by: -1) } } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(slot.title) earlier")
                Button { onChange { $0.move(slot, by: 1) } } label: { Image(systemName: "chevron.right") }
                    .disabled(index == order.count - 1)
                    .accessibilityLabel("Move \(slot.title) later")
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(on ? AppTheme.textPrimary : AppTheme.textTertiary)
        .frame(width: 78, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(dropTarget == slot ? AppTheme.accent : (on ? AppTheme.accent.opacity(0.35) : Color.gray.opacity(0.2)),
                                lineWidth: dropTarget == slot ? 2 : 1)
                )
        )
        .opacity(on ? 1 : 0.6)
        .draggable(slot.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let moved = EffectsChain.EffectSlot(rawValue: raw), moved != slot else { return false }
            let fromIndex = order.firstIndex(of: moved) ?? 0
            onChange { chain in
                // Dragging right drops after the target, dragging left drops before it.
                if fromIndex < index {
                    let next = index + 1 < order.count ? order[index + 1] : nil
                    chain.move(moved, before: next)
                } else {
                    chain.move(moved, before: slot)
                }
            }
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? slot : (dropTarget == slot ? nil : dropTarget)
        }
        .accessibilityIdentifier("routing.block.\(slot.rawValue)")
    }
}
