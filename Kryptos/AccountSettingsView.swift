import SwiftData
import SwiftUI

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var billing: BillingService
    @Query(sort: \VaultEntryRecord.updatedAt, order: .reverse) private var allRecords: [VaultEntryRecord]

    @StateObject private var backup = DriveBackupService()
    @ObservedObject private var reminders = ExpiryReminderService.shared
    @State private var confirmingDeleteAll = false
    @State private var confirmingDriveRestore = false
    @State private var confirmingICloudRestore = false

    private var ownerId: String { auth.account?.id ?? "local" }
    private var records: [VaultEntryRecord] { allRecords.filter { $0.ownerId == ownerId } }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                proSection
                remindersSection
                backupSection
                aboutSection
                dangerSection
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
            .alert("Delete account and all data?", isPresented: $confirmingDeleteAll) {
                Button("Delete Account", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your Kryptos account from this device along with every vault entry, the encryption key, and all expiry reminders. You will be signed out and this cannot be undone. If you've previously backed up to iCloud or Google Drive, delete those backups separately to remove all copies.")
            }
            .alert("Restore from Google Drive?", isPresented: $confirmingDriveRestore) {
                Button("Restore") {
                    Task { await restoreFromDrive() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces the current local vault with the latest Drive AppData backup.")
            }
            .alert("Restore from iCloud?", isPresented: $confirmingICloudRestore) {
                Button("Restore") {
                    Task { await restoreFromICloud() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces the current local vault with the latest iCloud backup.")
            }
        }
    }

    private var accountSection: some View {
        Section {
            if let account = auth.account {
                HStack(spacing: 14) {
                    AsyncImage(url: account.photoURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName ?? account.email ?? "Signed in")
                            .font(.headline)
                        Text("Signed in with \(account.provider.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let email = account.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button(role: .destructive) {
                    auth.signOut()
                    dismiss()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    Task { _ = await auth.signInWithApple() }
                } label: {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                }

                Button {
                    Task { _ = await auth.signIn() }
                } label: {
                    Label("Sign in with Google", systemImage: "lock.shield")
                }
            }
        }
    }

    private var proSection: some View {
        Section("Pro Version") {
            if billing.isPremium {
                Label("Pro version unlocked. Thank you for your support.", systemImage: "crown.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("Upgrade to Pro to remove the \(BillingService.freeEntryLimit) entry limit and support future development.")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await billing.purchasePremium() }
                } label: {
                    Label("Upgrade to Pro (One-time)", systemImage: "crown")
                }
            }

            Button {
                Task { await billing.restorePurchases() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }

            if let message = billing.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var backupSection: some View {
        Section {
            Text(backupDescription)
                .foregroundStyle(.secondary)

            Text(backup.lastICloudBackupAt.map { "Last iCloud backup: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No iCloud backup yet.")
                .font(.footnote)

            Button {
                Task { await runICloudBackup() }
            } label: {
                Label("Back up to iCloud", systemImage: "icloud.and.arrow.up")
            }
            .disabled(auth.account == nil || backup.workingMessage != nil)

            Button {
                confirmingICloudRestore = true
            } label: {
                Label("Restore from iCloud", systemImage: "arrow.clockwise.icloud")
            }
            .disabled(auth.account == nil || backup.workingMessage != nil)

            Text(driveBackupTimestampLabel)
                .font(.footnote)
                .padding(.top, 8)

            Button {
                Task { await runDriveBackup(toMyDrive: billing.isPremium) }
            } label: {
                Label(billing.isPremium ? "Back up to My Drive (Pro)" : "Back up to Google Drive", systemImage: "externaldrive.badge.icloud")
            }
            .disabled(auth.account == nil || backup.workingMessage != nil)

            Button {
                confirmingDriveRestore = true
            } label: {
                Label("Restore from Google Drive", systemImage: "arrow.clockwise.icloud")
            }
            .disabled(auth.account == nil || backup.workingMessage != nil)

            if let working = backup.workingMessage {
                Label(working, systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(BrandPalette.primary)
            }

            if let feedback = backup.feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Cloud Backup")
        } footer: {
            if billing.isPremium {
                Text("Restore scans both your visible \"KryptosBackups\" folder and any older hidden backup, and uses whichever is newest.")
            } else {
                Text("Backups go to a hidden Google Drive folder only your device can see. Upgrade to Pro to back up to a visible \"KryptosBackups\" folder you can copy or move yourself.")
            }
        }
    }

    private var backupDescription: String {
        billing.isPremium
            ? "Backs up the encrypted vault package to your private iCloud database or a visible \"KryptosBackups\" folder in your Google Drive."
            : "Backs up the encrypted vault package to your private iCloud database or a hidden Google Drive folder."
    }

    private var driveBackupTimestampLabel: String {
        if billing.isPremium {
            if let myDrive = backup.lastMyDriveBackupAt {
                var line = "Last My Drive backup: \(myDrive.formatted(date: .abbreviated, time: .shortened))"
                if let appData = backup.lastAppDataBackupAt, appData > myDrive {
                    line += " · Newer hidden backup: \(appData.formatted(date: .abbreviated, time: .shortened))"
                }
                return line
            }
            if let appData = backup.lastAppDataBackupAt {
                return "Last Google Drive backup (hidden): \(appData.formatted(date: .abbreviated, time: .shortened))"
            }
            return "No Google Drive backup yet."
        }
        if let appData = backup.lastAppDataBackupAt {
            return "Last Google Drive backup: \(appData.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No Google Drive backup yet."
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { reminders.isEnabled },
                set: { newValue in
                    reminders.isEnabled = newValue
                    Task {
                        if newValue {
                            _ = await reminders.requestAuthorization()
                        }
                        await reminders.sync(records: records)
                    }
                }
            )) {
                Label("Expiry reminders", systemImage: "bell.badge")
            }

            Text("Sends a local notification 30, 7, and 1 day before expiry for any entry that has an Expiry field, regardless of type.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if reminders.isEnabled, reminders.authorizationStatus == .denied {
                Label("Notifications are turned off for Kryptos in iOS Settings. Enable them to receive expiry reminders.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Reminders")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Link(destination: URL(string: "https://kryptos.faizalmzain.com/privacy")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://kryptos.faizalmzain.com/faq")!) {
                Label("Terms & FAQ", systemImage: "doc.text")
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Text("Permanently deletes your Kryptos account and every vault entry, encryption key, and reminder stored on this device. You will be signed out. This cannot be undone.")
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                confirmingDeleteAll = true
            } label: {
                Label("Delete account and all data", systemImage: "person.crop.circle.badge.xmark")
            }
        } header: {
            Text("Delete Account")
        } footer: {
            Text("To also remove copies stored in iCloud or Google Drive, delete those backups before deleting your account.")
        }
    }

    private func runICloudBackup() async {
        await backup.backupToICloud(records: records)
    }

    private func restoreFromICloud() async {
        await backup.restoreFromICloud(modelContext: modelContext, ownerId: ownerId)
        await reminders.sync(records: records)
    }

    private func runDriveBackup(toMyDrive: Bool) async {
        let scope = toMyDrive ? GoogleAuthService.driveFileScope : GoogleAuthService.appDataScope
        guard let token = await auth.accessToken(requiring: scope) else { return }
        await backup.backup(records: records, accessToken: token, toMyDrive: toMyDrive, refresh: driveTokenRefresher(scope: scope))
    }

    private func restoreFromDrive() async {
        let appDataToken = await auth.accessToken(requiring: GoogleAuthService.appDataScope)
        let myDriveToken: String?
        if billing.isPremium {
            myDriveToken = await auth.accessToken(requiring: GoogleAuthService.driveFileScope)
        } else if auth.account?.grantedScopes.contains(GoogleAuthService.driveFileScope) == true {
            myDriveToken = auth.account?.accessToken
        } else {
            myDriveToken = nil
        }
        let refresher = driveTokenRefresher(scope: billing.isPremium ? GoogleAuthService.driveFileScope : GoogleAuthService.appDataScope)
        await backup.restore(appDataToken: appDataToken, myDriveToken: myDriveToken, modelContext: modelContext, ownerId: ownerId, refresh: refresher)
        await reminders.sync(records: records)
    }

    private func driveTokenRefresher(scope: String) -> DriveBackupService.TokenRefresher {
        { [auth] in
            if let token = await auth.refreshAccessToken() {
                return token
            }
            return await auth.signIn(scopes: [scope])?.accessToken
        }
    }

    private func deleteAllData() {
        allRecords.forEach { modelContext.delete($0) }
        try? modelContext.save()
        VaultCrypto.shared.destroyLocalKey()
        Task { await reminders.cancelAll() }
        auth.signOut()
        dismiss()
    }
}
