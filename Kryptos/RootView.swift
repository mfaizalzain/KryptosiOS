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
    @State private var showingSettings = false

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
                        Label(auth.isWorking ? "Signing in..." : "Sign in with Apple", systemImage: "apple.logo")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.black)
                    .disabled(auth.isWorking)

                    Button {
                        Task { _ = await auth.signIn() }
                    } label: {
                        Label(auth.isWorking ? "Signing in..." : "Sign in with Google", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
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
