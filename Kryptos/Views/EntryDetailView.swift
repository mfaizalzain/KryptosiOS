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
                
                await MainActor.run {
                    self.fields = decryptedFields
                    self.attachment = decryptedAttachment
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.decryptError = "This entry's data could not be decrypted. It may be corrupted or encrypted with a different key."
                }
            }
        }
    }

    private func triggerToast(message: String) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        toastTask?.cancel()
        toastMessage = message
        
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                toastMessage = nil
            }
        }
    }

    private var reminderText: String? {
        guard ExpiryReminderService.shared.isEnabled else { return nil }
        guard let expiry = ExpiryReminderService.shared.expiryDate(forFields: fields, template: record.template) else { return nil }
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

    var body: some View {
        ZStack {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(BrandPalette.primary)
                    Text("Decrypting securely...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
            } else if let decryptError {
                ContentUnavailableView(
                    "Unable to decrypt",
                    systemImage: "exclamationmark.lock",
                    description: Text(decryptError)
                )
            } else {
                List {
                    Section {
                        HStack {
                            VaultHeroCard(template: record.template, title: record.title, fields: fields, attachment: attachment)
                                .frame(maxWidth: 320)
                            Spacer(minLength: 0)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
                        .listRowBackground(Color.clear)
                    }

                    let copyableFields = fields.filter { !$0.value.isEmpty }
                    if !copyableFields.isEmpty {
                        Section("Values") {
                            ForEach(copyableFields) { field in
                                FieldRow(
                                    field: field,
                                    sensitive: isSensitive(field),
                                    revealed: !isSensitive(field) || revealedFields.contains(field.id),
                                    onToggle: {
                                        if revealedFields.contains(field.id) {
                                            revealedFields.remove(field.id)
                                        } else {
                                            revealedFields.insert(field.id)
                                        }
                                    },
                                    onValueTap: {
                                        if isSensitive(field) {
                                            revealedFields.insert(field.id)
                                        }
                                        SecureClipboard.copy(label: field.name, value: field.value)
                                        triggerToast(message: "Copied \(field.name)")
                                    },
                                    onCopy: {
                                        SecureClipboard.copy(label: field.name, value: field.value)
                                        triggerToast(message: "Copied \(field.name)")
                                    }
                                )
                            }
                        }
                    }

                    if let attachment, !heroShowsAttachment, let image = UIImage(data: attachment) {
                        Section("Attachment") {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    if let reminderText {
                        Section {
                            Label {
                                Text(reminderText)
                                    .font(.footnote)
                            } icon: {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundStyle(BrandPalette.primary)
                            }
                        }
                    }

                    Section {
                        Button {
                            qrPayload = QRPayload(value: makeQRPayload(), title: record.title)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                  Text("Share with another device")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                        .listRowBackground(Color.clear)

                        Text("Scan the QR from another Kryptos app (iOS or Android) to import this entry instantly. Works fully offline.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)

                        if record.template == .qrCode, let rawValue = originalQRValue, !rawValue.isEmpty {
                            Button {
                                qrPayload = QRPayload(value: rawValue, title: record.title)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "qrcode")
                                    Text("Show original QR")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                            .listRowBackground(Color.clear)

                            Text("The original QR — scannable by any QR reader (Wi-Fi, URL, vCard, etc.).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        Text("Tap a value to reveal and copy it. The clipboard clears automatically after 30 seconds.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let message = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    )
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastMessage)
            }
        }
        .navigationTitle(record.title.isEmpty ? "Entry Details" : record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    qrPayload = QRPayload(value: makeQRPayload(), title: record.title)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share entry")
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
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
                modelContext.delete(record)
                try? modelContext.save()
                ExpiryReminderService.shared.cancelReminders(for: id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(record.title.isEmpty ? "this entry" : record.title) from your vault.")
        }
        .task {
            decryptRecord()
        }
        .onChange(of: record.updatedAt) { _, _ in
            decryptRecord()
        }
    }

    private var originalQRValue: String? {
        fields.first { $0.name.localizedCaseInsensitiveCompare("Data") == .orderedSame }?.value
            ?? fields.first?.value
    }

    private func makeQRPayload() -> String {
        let fieldDict = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
        let envelope: [String: Any] = [
            "kryptos": 1,
            "template": record.template.rawValue,
            "title": record.title,
            "fields": fieldDict
        ]
        let data = (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
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
