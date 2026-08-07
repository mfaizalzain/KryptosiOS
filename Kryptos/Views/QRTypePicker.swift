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
                                .fill(selected == type ? BrandPalette.primary.opacity(0.16) : Color.secondary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected == type ? BrandPalette.primary : .primary)
            }
        }
        .padding(.vertical, 4)
    }
}
