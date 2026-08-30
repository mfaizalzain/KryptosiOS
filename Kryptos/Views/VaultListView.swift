import SwiftData
import SwiftUI

struct VaultListView: View {
    private final class DecryptedFieldCache {
        var store: [UUID: (updatedAt: Date, fields: [VaultField])] = [:]
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var billing: BillingService
    @Query(sort: \VaultEntryRecord.updatedAt, order: .reverse) private var allRecords: [VaultEntryRecord]

    @State private var searchText = ""
    @State private var selectedTemplate: VaultTemplate?
    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var showingQRScanner = false
    @State private var importedQRPayload: String?
    @State private var pendingDelete: VaultEntryRecord?
    @State private var fieldCache = DecryptedFieldCache()

    private var ownerId: String { auth.account?.id ?? "local" }
    private var records: [VaultEntryRecord] { allRecords.filter { $0.ownerId == ownerId } }
    private var reachedLimit: Bool { !billing.isPremium && records.count >= BillingService.freeEntryLimit }

    /// True when the user has narrowed the vault with either the search field
    /// or a category chip.
    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTemplate != nil
    }

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.space6) {
                header

                if records.isEmpty {
                    emptyState
                } else if filteredGroups.isEmpty {
                    noResultsState
                } else {
                    featuredSection
                    categorySections
                }
            }
            .padding(.horizontal, Theme.space4)
            .padding(.top, Theme.space3)
            .padding(.bottom, records.isEmpty ? Theme.space6 : 120)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .vaultBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { floatingActionBar }
        .navigationDestination(for: UUID.self) { id in
            if let record = allRecords.first(where: { $0.id == id }) {
                EntryDetailView(record: record)
            } else {
                ContentUnavailableView("Entry not found", systemImage: "questionmark.folder")
                    .vaultBackground()
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
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { delete(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently removes \(pendingDelete?.title.ifBlank("this entry") ?? "this entry") from your vault.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            HStack(spacing: 10) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Kryptos")
                        .font(Theme.titleMedium)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(records.count) \(records.count == 1 ? "item" : "items") · encrypted")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    if let photoURL = auth.account?.photoURL {
                        AsyncImage(url: photoURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(PressableButtonStyle(amount: 0.92))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Account settings")
            }

            Text("My Vault")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            searchField

            if !records.isEmpty {
                filterChips
            }
        }
        .padding(.top, Theme.space2)
    }

    private var searchField: some View {
        HStack(spacing: Theme.space3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(searchText.isEmpty ? Theme.textTertiary : Theme.accent)
            TextField("Search your vault", text: $searchText)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.space4)
        .frame(height: Theme.controlHeightCompact)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .stroke(searchText.isEmpty ? Theme.stroke : Theme.accent.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Category filter chips

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.space2) {
                FilterChip(
                    title: "All",
                    count: records.count,
                    selected: selectedTemplate == nil,
                    tint: Theme.accent
                ) {
                    withAnimation(Theme.snappy) { selectedTemplate = nil }
                }

                ForEach(VaultTemplate.allCases) { template in
                    let count = records.filter { $0.template == template }.count
                    if count > 0 {
                        FilterChip(
                            title: template.pluralTitle,
                            count: count,
                            selected: selectedTemplate == template,
                            tint: template.accentColor
                        ) {
                            withAnimation(Theme.snappy) {
                                // Tapping the active chip clears it, so the
                                // filter is never a one-way door.
                                selectedTemplate = selectedTemplate == template ? nil : template
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Featured carousel

    @ViewBuilder
    private var featuredSection: some View {
        if !isFiltering {
            let featured = featuredRecords
            if !featured.isEmpty {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    VaultSectionHeader(
                        title: hasExpiringSoon ? "Needs attention" : "Recently added",
                        subtitle: hasExpiringSoon ? "Expiring within 90 days" : nil,
                        symbol: hasExpiringSoon ? "exclamationmark.circle" : "clock.arrow.circlepath",
                        tint: hasExpiringSoon ? Theme.warning : Theme.accent
                    )
                    FeaturedCarousel(records: featured)
                }
            }
        }
    }

    private var hasExpiringSoon: Bool {
        !expiringSoonRecords.isEmpty
    }

    /// Entries with an expiry date inside the next 90 days (already-expired
    /// entries included, since those need attention most).
    private var expiringSoonRecords: [VaultEntryRecord] {
        let now = Date()
        guard let soon = Calendar.current.date(byAdding: .day, value: 90, to: now) else { return [] }
        return records.filter { record in
            guard let expiry = expiryDate(for: record) else { return false }
            return expiry < soon
        }
    }

    /// Anything expiring soon, topped up with the most recently updated entries
    /// so the carousel is never empty when the vault has content.
    private var featuredRecords: [VaultEntryRecord] {
        var seen = Set<UUID>()
        var featured: [VaultEntryRecord] = []

        for record in expiringSoonRecords where seen.insert(record.id).inserted {
            featured.append(record)
            if featured.count >= 5 { return featured }
        }
        for record in records where seen.insert(record.id).inserted {
            featured.append(record)
            if featured.count >= 5 { break }
        }
        return featured
    }

    private func expiryDate(for record: VaultEntryRecord) -> Date? {
        ExpiryReminderService.shared.expiryDate(forFields: decryptedFields(for: record), template: record.template)
    }

    // MARK: - Category sections

    private var categorySections: some View {
        let groups = filteredGroups
        return VStack(alignment: .leading, spacing: Theme.space6) {
            ForEach(groups, id: \.template) { group in
                VStack(alignment: .leading, spacing: Theme.space3) {
                    VaultSectionHeader(
                        title: group.template.pluralTitle,
                        subtitle: "\(group.records.count) \(group.records.count == 1 ? "entry" : "entries")",
                        symbol: group.template.symbol,
                        tint: group.template.accentColor
                    )
                    VStack(spacing: Theme.space3) {
                        ForEach(group.records) { record in
                            NavigationLink(value: record.id) {
                                EntryRowCard(record: record, fields: decryptedFields(for: record))
                            }
                            .buttonStyle(PressableButtonStyle(amount: 0.985))
                            .contextMenu {
                                Button {
                                    copyPrimaryValue(of: record)
                                } label: {
                                    Label("Copy main value", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    pendingDelete = record
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty & no-result states

    private var emptyState: some View {
        VStack(spacing: Theme.space5) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 128, height: 128)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accentGradient)
            }
            .accessibilityHidden(true)

            VStack(spacing: Theme.space2) {
                Text("Your vault is empty")
                    .font(Theme.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("Add your first document, card, or secret.\nEverything stays encrypted on this device.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.space3) {
                Button {
                    startNewEntry()
                } label: {
                    Label("Add an entry", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    showingQRScanner = true
                } label: {
                    Label("Scan a QR code", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, Theme.space6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.space6)
        .padding(.top, 80)
    }

    /// Shown in place of the sections when a filter matches nothing. The header
    /// stays on screen above it, so search and chips remain reachable.
    private var noResultsState: some View {
        VaultCard(padding: Theme.space6) {
            VStack(spacing: Theme.space4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)

                VStack(spacing: Theme.space2) {
                    Text("No matches")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(noResultsDescription)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    withAnimation(Theme.snappy) {
                        searchText = ""
                        selectedTemplate = nil
                    }
                } label: {
                    Label("Clear filters", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var noResultsDescription: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedTemplate, !query.isEmpty {
            return "Nothing in \(selectedTemplate.pluralTitle) matches “\(query)”."
        }
        if let selectedTemplate {
            return "Nothing in \(selectedTemplate.pluralTitle) yet."
        }
        return "Nothing in your vault matches “\(query)”."
    }

    // MARK: - Floating action bar

    private var floatingActionBar: some View {
        HStack(spacing: Theme.space3) {
            Spacer()

            // The scanner used to be reachable only from the empty state; once
            // the vault had a single entry it disappeared entirely.
            Button {
                showingQRScanner = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
            }
            .buttonStyle(PressableButtonStyle(amount: 0.94))
            .accessibilityLabel("Scan a QR code")

            Button {
                startNewEntry()
            } label: {
                Label(reachedLimit ? "Unlock Pro" : "Add Entry", systemImage: reachedLimit ? "crown.fill" : "plus")
                    .font(Theme.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.space5)
                    .frame(height: 56)
                    .background(Capsule().fill(Theme.accentGradient))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 16, y: 7)
            }
            .buttonStyle(PressableButtonStyle(amount: 0.96))
            .accessibilityHint(reachedLimit ? "Free vaults are limited to \(BillingService.freeEntryLimit) entries" : "")
        }
        .padding(.trailing, Theme.space5)
        .padding(.bottom, Theme.space3)
        .padding(.top, Theme.space6)
        .background(
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background.opacity(0.85), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    // MARK: - Actions

    private func startNewEntry() {
        if reachedLimit {
            showingSettings = true
        } else {
            showingEditor = true
        }
    }

    private func delete(_ record: VaultEntryRecord) {
        let id = record.id
        fieldCache.store[id] = nil
        modelContext.delete(record)
        try? modelContext.save()
        ExpiryReminderService.shared.cancelReminders(for: id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Copies the most useful field of an entry — the one its hero card leads
    /// with — without making the user open it first.
    private func copyPrimaryValue(of record: VaultEntryRecord) {
        let fields = decryptedFields(for: record)
        guard let field = fields.first(where: { !$0.value.isEmpty }) else { return }
        SecureClipboard.copy(value: field.value)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Derived data

    private var filteredGroups: [(template: VaultTemplate, records: [VaultEntryRecord])] {
        let filtered = records.filter(matchesSearch)
        return VaultTemplate.allCases.compactMap { template in
            if let selectedTemplate, template != selectedTemplate { return nil }
            let items = filtered.filter { $0.template == template }
            return items.isEmpty ? nil : (template, items)
        }
    }

    private func matchesSearch(_ record: VaultEntryRecord) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        if record.title.lowercased().contains(query) { return true }
        if record.template.pluralTitle.lowercased().contains(query) { return true }
        let fields = decryptedFields(for: record)
        return fields.contains { $0.name.lowercased().contains(query) || $0.value.lowercased().contains(query) }
    }

    private func decryptedFields(for record: VaultEntryRecord) -> [VaultField] {
        if let cached = fieldCache.store[record.id], cached.updatedAt == record.updatedAt {
            return cached.fields
        }
        if fieldCache.store.count > 200 {
            fieldCache.store.removeAll()
        }
        let fields = (try? VaultCrypto.shared.decodeFields(record.encryptedFields)) ?? []
        fieldCache.store[record.id] = (record.updatedAt, fields)
        return fields
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(selected ? Color.white.opacity(0.22) : tint.opacity(0.16), in: Capsule())
            }
            .foregroundStyle(selected ? .white : Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surface))
            )
            .overlay(
                Capsule().stroke(selected ? .clear : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle(amount: 0.94))
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Featured carousel

private struct FeaturedCarousel: View {
    let records: [VaultEntryRecord]
    @State private var visibleRecordID: UUID?

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(records) { record in
                            NavigationLink(value: record.id) {
                                HeroCardTile(record: record)
                                    .frame(width: cardWidth(in: proxy.size.width))
                            }
                            .buttonStyle(PressableButtonStyle(amount: 0.98))
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
        .frame(height: records.count > 1 ? 158 : 142)
    }

    private func cardWidth(in availableWidth: CGFloat) -> CGFloat {
        max(280, availableWidth * 0.82)
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
                    .fill(index == currentIndex ? Theme.accent : Theme.textTertiary.opacity(0.3))
                    .frame(width: index == currentIndex ? 18 : 5, height: 5)
                    .animation(.snappy(duration: 0.18), value: currentIndex)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card \(currentIndex + 1) of \(count)")
    }
}

private struct HeroCardTile: View {
    let record: VaultEntryRecord

    var body: some View {
        let fields = (try? VaultCrypto.shared.decodeFields(record.encryptedFields)) ?? []
        let attachment = record.encryptedAttachment.flatMap { try? VaultCrypto.shared.open($0) }
        VaultHeroCard(template: record.template, title: record.title, fields: fields, attachment: attachment, compact: true)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

// MARK: - Vertical entry row card

private struct EntryRowCard: View {
    let record: VaultEntryRecord
    let fields: [VaultField]

    /// Resolved once so the label and its tint can't disagree, and the date
    /// parser runs a single time per row.
    private var expiry: Date? {
        guard record.template.supportsExpiryBadge else { return nil }
        return ExpiryReminderService.shared.expiryDate(forFields: fields, template: record.template)
    }

    var body: some View {
        HStack(spacing: Theme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(record.template.accentColor.opacity(0.12))
                Image(systemName: record.template.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(record.template.accentColor)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.ifBlank(record.template.title))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(record.template.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    if let expiry, let status = ExpiryStatus(date: expiry) {
                        Circle()
                            .fill(status.tint)
                            .frame(width: 4, height: 4)
                        Text(status.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.tint)
                    }
                }
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space3)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ImportedPayload: Identifiable {
    let value: String
    var id: String { value }
}

// MARK: - Previews

#Preview("Vault Home (dark)", traits: .sizeThatFitsLayout) {
    VaultListView()
        .environmentObject(GoogleAuthService())
        .environmentObject(BillingService())
        .preferredColorScheme(.dark)
}
