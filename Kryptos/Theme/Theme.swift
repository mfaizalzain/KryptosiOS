import SwiftUI

// MARK: - Brand identity
//
// Kryptos 2.0 design system. The app is dark-first by design: a vault that
// glows in the dark feels secure. All screens read their colors, gradients,
// spacing, radii, and type from this single file so the whole product stays
// consistent and can be re-themed in one place.

enum Theme {
    // MARK: Surfaces

    /// App background (deep space navy).
    static let background = Color(red: 9/255, green: 13/255, blue: 26/255)
    /// Elevated surfaces — cards, rows, sheets.
    static let surface = Color(red: 17/255, green: 24/255, blue: 44/255)
    /// Slightly lighter surface for hover/pressed states and separators.
    static let surfaceRaised = Color(red: 26/255, green: 35/255, blue: 60/255)
    /// Subtle stroke color for cards and controls.
    static let stroke = Color.white.opacity(0.08)

    // MARK: Text

    static let textPrimary = Color(red: 235/255, green: 240/255, blue: 250/255)
    static let textSecondary = Color(red: 155/255, green: 166/255, blue: 192/255)
    static let textTertiary = Color(red: 110/255, green: 121/255, blue: 150/255)

    // MARK: Accent

    static let accent = Color(red: 96/255, green: 152/255, blue: 255/255)
    static let accentDeep = Color(red: 0/255, green: 86/255, blue: 210/255)

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Full-bleed app background gradient used behind scroll content.
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 9/255, green: 13/255, blue: 26/255),
            Color(red: 13/255, green: 19/255, blue: 38/255)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Semantic colors

    static let success = Color(red: 66/255, green: 199/255, blue: 138/255)
    static let warning = Color(red: 255/255, green: 176/255, blue: 60/255)
    static let danger = Color(red: 255/255, green: 105/255, blue: 115/255)

    // MARK: Spacing scale

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    // MARK: Radii

    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 22
    static let radiusPill: CGFloat = 999

    // MARK: Type ramp

    static let titleLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    static let titleMedium = Font.system(size: 24, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular)
    static let bodyMedium = Font.system(size: 16, weight: .medium)
    static let caption = Font.system(size: 13, weight: .medium)
    static let captionSmall = Font.system(size: 11, weight: .semibold)
}

// MARK: - Shared view modifiers

/// Dark-first scroll background that works inside a NavigationStack.
struct VaultBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

extension View {
    /// Applies the dark-first vault background.
    func vaultBackground() -> some View {
        modifier(VaultBackground())
    }

    /// Springy press feedback used by cards and primary buttons.
    func pressScale(_ isPressed: Bool, amount: CGFloat = 0.97) -> some View {
        scaleEffect(isPressed ? amount : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}

/// A 1px divider in the theme stroke color.
struct VaultDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
    }
}

// MARK: - Card container

/// The standard elevated card container used across the app.
struct VaultCard<Content: View>: View {
    var padding: CGFloat = Theme.space4
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - Reusable small components

/// A status chip used on cards and headers (e.g. "Expiring soon", "Count").
struct VaultChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(Theme.captionSmall)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }
}
