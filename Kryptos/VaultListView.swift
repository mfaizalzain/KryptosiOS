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

    private var ownerId: String { auth.account?.id ?? "local" }
    private var records: [VaultEntryRecord] { allRecords.filter { $0.ownerId == ownerId } }
    private var reachedLimit: Bool { !billing.isPremium && records.count >= BillingService.freeEntryLimit }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("Your vault is empty.", systemImage: "lock.doc", description: Text("Tap Add Entry to secure your first document."))
                } else if filteredGroups.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(filteredGroups, id: \.template) { group in
                                Section {
                                    VStack(spacing: 12) {
                                        ForEach(group.records) { record in
                                            NavigationLink(value: record.id) {
                                                HeroCardTile(record: record)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                } header: {
                                    CategoryHeader(template: group.template, count: group.records.count)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .padding(.bottom, 84)
                    }
                }
            }
            .navigationTitle("Kryptos")
            .searchable(text: $searchText, prompt: "Search your vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundStyle(.indigo)
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
                        Label(reachedLimit ? "Unlock Pro" : "Add Entry", systemImage: reachedLimit ? "crown" : "plus")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.trailing, 20)
                    .padding(.bottom, 10)
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
                .frame(width: 30, height: 30)
                .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(.indigo)
            Text(template.pluralTitle)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }
}

private struct HeroCardTile: View {
    let record: VaultEntryRecord

    var body: some View {
        let fields = (try? VaultCrypto.shared.decodeFields(record.encryptedFields)) ?? []
        VaultHeroCard(template: record.template, title: record.title, fields: fields, attachment: nil, compact: true)
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
