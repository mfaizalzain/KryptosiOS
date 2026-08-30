import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let record: VaultEntryRecord
    @State private var showingEditor = false
    @State private var confirmingDelete = false
    @State private var revealedFields = Set<UUID>()
    @State private var qrPayload: QRPayload?

    @State private var fields: [VaultField] = []
    @State private var attachment: Data? = nil
    @State private var isLoading = true
    @State private var decryptError: String? = nil
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if isLoading {
                loadingState
            } else if let decryptError {
                ContentUnavailableView(
                    "Unable to decrypt",
                    systemImage: "exclamationmark.lock",
                    description: Text(decryptError)
                )
            } else {
                detailContent
            }

            toastOverlay
        }
        .navigationTitle(record.title.ifBlank("Entry Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    shareEntry()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share entry")

                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit entry")

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete entry")
            }
        }
        .sheet(isPresented: $showingEditor) {
            EntryEditorView(record: record, ownerId: record.ownerId)
        }
        .sheet(item: $qrPayload) { payload in
            QRShareView(payload: payload)
        }
        .alert("Delete this entry?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                let id = record.id
                // Pop first: the list's navigationDestination resolves the
                // record by id, so deleting while still pushed briefly renders
                // the "Entry not found" fallback.
                dismiss()
                modelContext.delete(record)
                try? modelContext.save()
                ExpiryReminderService.shared.cancelReminders(for: id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(record.title.ifBlank("this entry")) from your vault.")
        }
        .task { decryptRecord() }
        .onChange(of: record.updatedAt) { _, _ in decryptRecord() }
        .onDisappear { toastTask?.cancel() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Theme.space3) {
            ProgressView()
                .tint(Theme.accent)
            Text("Decrypting securely…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailContent: some View {
        ScrollView {
            VStack(spacing: Theme.space5) {
                heroSection

                if let status = ExpiryStatus(date: expiryDate) {
                    expiryBanner(status)
                }

                if !populatedFields.isEmpty {
                    valuesSection
                }

                if let attachment, !heroShowsAttachment, let image = UIImage(data: attachment) {
                    attachmentSection(image)
                }

                shareSection

                Text("Tap a value to reveal and copy it. The clipboard clears automatically after 30 seconds.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.space4)
            }
            .padding(.horizontal, Theme.space4)
            .padding(.top, Theme.space4)
            .padding(.bottom, Theme.space8)
        }
        .scrollIndicators(.hidden)
    }

    private var heroSection: some View {
        VaultHeroCard(template: record.template, title: record.title, fields: fields, attachment: attachment)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private func expiryBanner(_ status: ExpiryStatus) -> some View {
        HStack(spacing: Theme.space3) {
            Image(systemName: status.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(status.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.label)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let reminderText {
                    Text(reminderText)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.space4)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(status.tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .stroke(status.tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var valuesSection: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            VaultSectionHeader(title: "Values", symbol: "list.bullet.rectangle", tint: record.template.accentColor)

            VaultCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(populatedFields.enumerated()), id: \.element.id) { index, field in
                        if index > 0 { VaultDivider() }
                        FieldRow(
                            template: record.template,
                            field: field,
                            sensitive: isSensitive(field),
                            revealed: !isSensitive(field) || revealedFields.contains(field.id),
                            onToggle: { toggleReveal(field) },
                            onValueTap: {
                                if isSensitive(field) {
                                    revealedFields.insert(field.id)
                                }
                                copy(field)
                            },
                            onCopy: { copy(field) }
                        )
                    }
                }
            }
        }
    }

    private func attachmentSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            VaultSectionHeader(title: "Attachment", symbol: "paperclip", tint: record.template.accentColor)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
                .accessibilityLabel("Scanned attachment")
        }
    }

    private var shareSection: some View {
        VStack(spacing: Theme.space3) {
            Button {
                shareEntry()
            } label: {
                Label("Share with another device", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("Scan the QR from another Kryptos app (iOS or Android) to import this entry instantly. Works fully offline.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)

            if record.template == .qrCode, let rawValue = originalQRValue, !rawValue.isEmpty {
                Button {
                    qrPayload = QRPayload(value: rawValue, title: record.title)
                } label: {
                    Label("Show original QR", systemImage: "qrcode")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Theme.space2)

                Text("The original QR — scannable by any QR reader (Wi-Fi, URL, vCard, etc.).")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        VStack {
            Spacer()
            if let toastMessage {
                VaultToast(message: toastMessage)
                    .padding(.bottom, Theme.space6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.springSoft, value: toastMessage)
        .allowsHitTesting(false)
    }

    // MARK: - Derived data

    private var populatedFields: [VaultField] {
        fields.filter { !$0.value.isEmpty }
    }

    private var expiryDate: Date? {
        ExpiryReminderService.shared.expiryDate(forFields: fields, template: record.template)
    }

    private var reminderText: String? {
        guard ExpiryReminderService.shared.isEnabled, let expiry = expiryDate else { return nil }
        let formatted = expiry.formatted(date: .abbreviated, time: .omitted)
        if expiry < .now {
            return "Expired on \(formatted). Update the Expiry field to schedule new reminders."
        }
        return "Reminders set for 30, 7, and 1 day before \(formatted)."
    }

    private var heroShowsAttachment: Bool {
        guard attachment != nil else { return false }
        switch record.template {
        case .idCard, .driversLicense, .paymentCard, .passport, .birthCertificate:
            return true
        case .bankAccount, .taxNumber, .apiKey, .note, .qrCode:
            return false
        }
    }

    private var originalQRValue: String? {
        fields.first { $0.name.localizedCaseInsensitiveCompare("Data") == .orderedSame }?.value
            ?? fields.first?.value
    }

    // MARK: - Actions

    private func decryptRecord() {
        isLoading = true
        decryptError = nil
        let encryptedFields = record.encryptedFields
        let encryptedAttachment = record.encryptedAttachment

        Task {
            do {
                let decryptedFields = try await Task.detached(priority: .userInitiated) {
                    try VaultCrypto.shared.decodeFields(encryptedFields)
                }.value

                let decryptedAttachment = try await Task.detached(priority: .userInitiated) {
                    try encryptedAttachment.map { try VaultCrypto.shared.open($0) }
                }.value

                self.fields = decryptedFields
                self.attachment = decryptedAttachment
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.decryptError = "This entry's data could not be decrypted. It may be corrupted or encrypted with a different key."
            }
        }
    }

    private func toggleReveal(_ field: VaultField) {
        withAnimation(Theme.snappy) {
            if revealedFields.contains(field.id) {
                revealedFields.remove(field.id)
            } else {
                revealedFields.insert(field.id)
            }
        }
    }

    private func copy(_ field: VaultField) {
        SecureClipboard.copy(value: field.value)
        triggerToast(message: "Copied \(field.name)")
    }

    private func shareEntry() {
        let value = QRPayloadBuilder.shareEnvelope(
            template: record.template,
            title: record.title,
            fields: fields
        )
        qrPayload = QRPayload(value: value, title: record.title)
    }

    private func triggerToast(message: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        toastTask?.cancel()
        withAnimation(Theme.springSoft) { toastMessage = message }

        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.springSoft) { toastMessage = nil }
        }
    }


    private func isSensitive(_ field: VaultField) -> Bool {
        let fieldName = field.name.lowercased()
        if fieldName.looksSecretFieldName {
            return true
        }
        if record.template == .paymentCard {
            return fieldName == "number" || fieldName.contains("card number")
        }
        return false
    }
}

// MARK: - Previews

#Preview("Entry Detail", traits: .sizeThatFitsLayout) {
    NavigationStack {
        EntryDetailView(
            record: VaultEntryRecord(
                ownerId: "preview",
                template: .paymentCard,
                title: "Platinum Rewards",
                encryptedFields: (try? VaultCrypto.shared.encodeFields([
                    VaultField(name: "Issuer", value: "Kryptos Bank"),
                    VaultField(name: "Cardholder", value: "Faizal Zain"),
                    VaultField(name: "Number", value: "4539123456789012"),
                    VaultField(name: "Expiry", value: "0928")
                ])) ?? Data()
            )
        )
    }
    .preferredColorScheme(.dark)
}
