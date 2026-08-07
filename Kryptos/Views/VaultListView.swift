import SwiftData
import SwiftUI

struct VaultListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var billing: BillingService
    @Query(sort: \VaultEntryRecord.updatedAt, order: .reverse) private var allRecords: [VaultEntryRecord]

    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var showingQRScanner = false
    @State private var importedQRPayload: String?

    private var ownerId: String { auth.account?.id ?? "local" }
    private var records: [VaultEntryRecord] { allRecords.filter { $0.ownerId == ownerId } }
    private var reachedLimit: Bool { !billing.isPremium && records.count >= BillingService.freeEntryLimit }

    var body: some View {
        NavigationStack {
            content
        }
        .task { await ExpiryReminderService.shared.sync(records: records) }
        .onChange(of: records.map(\.updatedAt)) { _, _ in
            Task { await ExpiryReminderService.shared.sync(records: records) }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
                if records.isEmpty {
                    ContentUnavailableView("Your vault is empty.", systemImage: "lock.doc", description: Text("Tap Add Entry to secure your first document."))
                } else if filteredGroups.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(filteredGroups, id: \.template) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    CategoryHeader(template: group.template, count: group.records.count)
                                    CategoryCarousel(records: group.records)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .padding(.bottom, 84)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search your vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Image("BrandMark")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text("Kryptos")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .fixedSize()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if reachedLimit {
                            showingSettings = true
                        } else {
                            showingQRScanner = true
                        }
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Scan QR to import")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        if let photoURL = auth.account?.photoURL {
                            AsyncImage(url: photoURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.crop.circle")
                            }
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityLabel("Account")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button {
                        if reachedLimit {
                            showingSettings = true
                        } else {
                            showingEditor = true
                        }
                    } label: {
                        Label(reachedLimit ? "Unlock Pro" : "Add Entry", systemImage: reachedLimit ? "crown.fill" : "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 56)
                            .background(
                                Capsule().fill(BrandPalette.primaryGradient)
                            )
                            .shadow(color: BrandPalette.primary.opacity(0.35), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 14)
                }
                .background(.clear)
            }
            .navigationDestination(for: UUID.self) { id in
                if let record = allRecords.first(where: { $0.id == id }) {
                    EntryDetailView(record: record)
                } else {
                    ContentUnavailableView("Entry not found", systemImage: "questionmark.folder")
                }
            }
            .sheet(isPresented: $showingEditor) {
                EntryEditorView(record: nil, ownerId: ownerId)
            }
            .sheet(isPresented: $showingSettings) {
                AccountSettingsView()
            }
            .sheet(isPresented: $showingQRScanner) {
                NavigationStack {
                    QRScannerView { value in
                        showingQRScanner = false
                        importedQRPayload = value
                    }
                    .navigationTitle("Scan QR")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showingQRScanner = false }
                        }
                    }
                }
            }
            .sheet(item: Binding(get: { importedQRPayload.map { ImportedPayload(value: $0) } }, set: { if $0 == nil { importedQRPayload = nil } })) { payload in
                EntryEditorView(record: nil, ownerId: ownerId, initialQRPayload: payload.value)
            }
    }

    private var filteredGroups: [(template: VaultTemplate, records: [VaultEntryRecord])] {
        let filtered = records.filter(matchesSearch)
        return VaultTemplate.allCases.compactMap { template in
            let items = filtered.filter { $0.template == template }
            return items.isEmpty ? nil : (template, items)
        }
    }

    private func matchesSearch(_ record: VaultEntryRecord) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        if record.title.lowercased().contains(query) { return true }
        if record.template.pluralTitle.lowercased().contains(query) { return true }
        let fields = (try? VaultCrypto.shared.decodeFields(record.encryptedFields)) ?? []
        return fields.contains { $0.name.lowercased().contains(query) || $0.value.lowercased().contains(query) }
    }
}

private struct CategoryHeader: View {
    let template: VaultTemplate
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(BrandPalette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(BrandPalette.primary)
            Text(template.pluralTitle)
                .font(.system(.headline, design: .rounded))
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: Capsule())
        }
    }
}

private struct ImportedPayload: Identifiable {
    let value: String
    var id: String { value }
}

private struct CategoryCarousel: View {
    let records: [VaultEntryRecord]
    @State private var visibleRecordID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(records) { record in
                            NavigationLink(value: record.id) {
                                HeroCardTile(record: record)
                                    .frame(width: cardWidth(in: proxy.size.width))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $visibleRecordID)
                .onAppear {
                    visibleRecordID = visibleRecordID ?? records.first?.id
                }
                .onChange(of: records.map(\.id)) { _, ids in
                    if visibleRecordID.map({ ids.contains($0) }) != true {
                        visibleRecordID = ids.first
                    }
                }
            }

            if records.count > 1 {
                CarouselIndicator(count: records.count, currentIndex: currentIndex)
            }
        }
        .frame(height: records.count > 1 ? 154 : 138)
    }

    private func cardWidth(in availableWidth: CGFloat) -> CGFloat {
        max(280, availableWidth)
    }

    private var currentIndex: Int {
        guard
            let visibleRecordID,
            let index = records.firstIndex(where: { $0.id == visibleRecordID })
        else { return 0 }
        return index
    }
}

private struct CarouselIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? BrandPalette.primary : Color.secondary.opacity(0.28))
                    .frame(width: index == currentIndex ? 18 : 5, height: 5)
                    .animation(.snappy(duration: 0.18), value: currentIndex)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(currentIndex + 1) of \(count)")
    }
}

private struct HeroCardTile: View {
    let record: VaultEntryRecord

    var body: some View {
        let fields = (try? VaultCrypto.shared.decodeFields(record.encryptedFields)) ?? []
        let attachment = record.encryptedAttachment.flatMap { try? VaultCrypto.shared.open($0) }
        VaultHeroCard(template: record.template, title: record.title, fields: fields, attachment: attachment, compact: true)
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}
