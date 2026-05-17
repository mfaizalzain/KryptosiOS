import AuthenticationServices
import SwiftData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @StateObject private var gate = BiometricGate()

    var body: some View {
        Group {
            if auth.account == nil || !gate.unlocked {
                LockView()
                    .environmentObject(gate)
            } else {
                VaultListView()
                    .environmentObject(gate)
            }
        }
        .tint(BrandPalette.primary)
    }
}

struct LockView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var gate: BiometricGate
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false

    private var buttonBackground: Color { colorScheme == .dark ? .white : .black }
    private var buttonForeground: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 18) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: BrandPalette.primary.opacity(0.35), radius: 22, y: 12)

                VStack(spacing: 6) {
                    Text("Kryptos")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Your private vault.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let account = auth.account {
                AccountBadge(account: account)
            } else {
                Text("Securely back up your data with encrypted cloud storage. Your data never leaves your device unencrypted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                if auth.account == nil {
                    Button {
                        Task { _ = await auth.signInWithApple() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                            Text(auth.isWorking ? "Signing in..." : "Sign in with Apple")
                                .font(.headline)
                        }
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color.primary)
                    .disabled(auth.isWorking)

                    Button {
                        Task { _ = await auth.signIn() }
                    } label: {
                        HStack(spacing: 10) {
                            Image("GoogleLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text(auth.isWorking ? "Signing in..." : "Sign in with Google")
                                .font(.headline)
                        }
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color.primary)
                    .disabled(auth.isWorking)
                } else {
                    Button {
                        gate.unlock()
                    } label: {
                        Label("Unlock Vault", systemImage: "faceid")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)

                    HStack(spacing: 12) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Restore", systemImage: "arrow.clockwise.icloud")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)

                        Button {
                            auth.signOut()
                            gate.lock()
                        } label: {
                            Label("Switch", systemImage: "arrow.left.arrow.right")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }

                if let message = auth.errorMessage ?? gate.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 18) {
                    Link("Privacy Policy", destination: URL(string: "https://kryptos.faizalmzain.com/privacy")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("Terms & FAQ", destination: URL(string: "https://kryptos.faizalmzain.com/faq")!)
                }
                .font(.footnote)
                .padding(.top, 6)
            }
        }
        .padding(28)
        .sheet(isPresented: $showingSettings) {
            AccountSettingsView()
        }
        .onAppear {
            if auth.account != nil && !gate.unlocked {
                gate.unlock()
            }
        }
    }
}

private struct AccountBadge: View {
    let account: GoogleAccount

    var body: some View {
        VStack(spacing: 12) {
            AsyncImage(url: account.photoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())

            VStack(spacing: 3) {
                Text(account.displayName ?? account.email ?? "Signed in")
                    .font(.title3.bold())
                    .lineLimit(1)
                Text("Signed in with \(account.provider.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let email = account.email, email != account.displayName {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct GoogleGLogo: View {
    private let blue = Color(red: 0.259, green: 0.522, blue: 0.957)
    private let red = Color(red: 0.918, green: 0.263, blue: 0.208)
    private let yellow = Color(red: 0.984, green: 0.737, blue: 0.020)
    private let green = Color(red: 0.204, green: 0.659, blue: 0.325)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = size * 0.22
            let radius = (size - lineWidth) / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                // Blue: right side, above the bar
                arc(center: center, radius: radius, start: -20, end: -110)
                    .stroke(blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                // Red: top going to left
                arc(center: center, radius: radius, start: -110, end: -200)
                    .stroke(red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                // Yellow: left going to bottom
                arc(center: center, radius: radius, start: -200, end: -290)
                    .stroke(yellow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                // Green: bottom going to right (stops below the bar)
                arc(center: center, radius: radius, start: -290, end: -340)
                    .stroke(green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

                // Horizontal bar coming from center to the right edge (blue)
                Rectangle()
                    .fill(blue)
                    .frame(width: size * 0.38, height: lineWidth)
                    .offset(x: size * 0.20, y: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func arc(center: CGPoint, radius: CGFloat, start: Double, end: Double) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(start),
                endAngle: .degrees(end),
                clockwise: true
            )
        }
    }
}
