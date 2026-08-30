import SwiftUI

struct QRTypePicker: View {
    let selected: QRPayloadType
    let onSelect: (QRPayloadType) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(QRPayloadType.allCases) { type in
                Button {
                    onSelect(type)
                } label: {
                    Label(type.label, systemImage: type.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected == type ? Theme.accent.opacity(0.18) : Theme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected == type ? Theme.accent.opacity(0.5) : Theme.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableButtonStyle(amount: 0.95))
                .foregroundStyle(selected == type ? Theme.accent : Theme.textSecondary)
                .accessibilityAddTraits(selected == type ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}
