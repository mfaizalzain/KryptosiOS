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
    @State private var fieldCache = DecryptedFieldCache()

    private var ownerId: String { auth.account?.id ?? "local" }
    private var records: [VaultEntryRecord] { allRecords.filter { $0.ownerId == ownerId } }
    private var reachedLimit: Bool { !billing.isPremium && records.count >= BillingService.freeEntryLimit }

    var body: some View {
        NavigationStack {
            content
        }
        .vaultBackground()
        .task { await ExpiryReminderService.shared.sync(records: records) }
        .onChange(of: records.map(\.updatedAt)) { _, _ in
            Task { await ExpiryReminderService.shared.sync(records: records) }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if records.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.space6) {
                        header
                        emptyState
                    }
                    .padding(.horizontal, Theme.space4)
                    .padding(.top, Theme.space3)
                }
                .scrollIndicators(.hidden)
            } else if filteredGroups.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .background(Theme.backgroundGradient.ignoresSafeArea())
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.space6) {
                        header
                        featuredSection
                        categorySections
                    }
                    .padding(.horizontal, Theme.space4)
                    .padding(.top, Theme.space3)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { floatingAddButton }
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

                VStack(alignment: .leading, spacing: 1) {
                    Text("Kryptos")
                        .font(Theme.titleMedium)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(records.count) \(records.count == 1 ? "item" : "items") · encrypted")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

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
                .accessibilityLabel("Account settings")
            }

            Text("My Vault")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            // Search pill
            HStack(spacing: Theme.space3) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(searchText.isEmpty ? Theme.textTertiary : Theme.accent)
                TextField("Search your vault", text: $searchText)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.space4)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .stroke(searchText.isEmpty ? Theme.stroke : Theme.accent.opacity(0.5), lineWidth: 1)
            )

            filterChips
        }
        .padding(.top, Theme.space2)
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
                    withAnimation(.snappy(duration: 0.25)) { selectedTemplate = nil }
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
                            withAnimation(.snappy(duration: 0.25)) { selectedTemplate = template }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Featured carousel (recent + expiring soon)

    @ViewBuilder
    private var featuredSection: some View {
        if selectedTemplate == nil && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let featured = featuredRecords
            if !featured.isEmpty {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    HStack {
                        Text("Featured")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    FeaturedCarousel(records: featured)
                }
            }
        }
    }

    /// The most recent entry plus anything expiring within 90 days (capped to 5).
    private var featuredRecords: [VaultEntryRecord] {
        var seen = Set<UUID>()
        var featured: [VaultEntryRecord] = []
        let now = Date()
        let soon = Calendar.current.date(byAdding: .day, value: 90, to: now) ?? now

        for record in records where seen.insert(record.id).inserted {
            if let expiry = expiryDate(for: record), expiry < soon {
                featured.append(record)
            }
            if featured.count >= 5 { break }
        }
        if let newest = records.first, !seen.contains(newest.id) {
            featured.append(newest)
        }
        return Array(featured.prefix(5))
    }

    private func expiryDate(for record: VaultEntryRecord) -> Date? {
        let fields = decryptedFields(for: record)
        return ExpiryReminderService.shared.expiryDate(forFields: fields, template: record.template)
    }

    // MARK: - Category sections

    private var categorySections: some View {
        let groups = filteredGroups
        return VStack(alignment: .leading, spacing: Theme.space6) {
            ForEach(groups, id: \.template) { group in
                VStack(alignment: .leading, spacing: Theme.space3) {
                    CategoryHeader(template: group.template, count: group.records.count)
                    VStack(spacing: Theme.space3) {
                        ForEach(group.records) { record in
                            NavigationLink(value: record.id) {
                                EntryRowCard(record: record, fields: decryptedFields(for: record))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

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
                    if reachedLimit {
                        showingSettings = true
                    } else {
                        showingEditor = true
                    }
                } label: {
                    Label("Add an entry", systemImage: "plus")
                        .font(Theme.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.accentGradient, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(.plain)

                Button {
                    showingQRScanner = true
                } label: {
                    Label("Scan a QR code", systemImage: "qrcode.viewfinder")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.space6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.space6)
        .padding(.top, 120)
    }

    // MARK: - Floating add button

    private var floatingAddButton: some View {
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
                    .font(Theme.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.space5)
                    .frame(height: 56)
                    .background(
                        Capsule().fill(Theme.accentGradient)
                    )
                    .shadow(color: Theme.accent.opacity(0.4), radius: 16, y: 7)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.trailing, Theme.space5)
            .padding(.bottom, Theme.space3)
        }
        .background(.clear)
    }

    // MARK: - Derived data

    private var filteredGroups: [(template: VaultTemplate, records: [VaultEntryRecord])] {
        let filtered = records.filter(matchesSearch)
        if let selectedTemplate {
            return VaultTemplate.allCases.compactMap { template in
                guard template == selectedTemplate else { return nil }
                let items = filtered.filter { $0.template == template }
                return items.isEmpty ? nil : (template, items)
            }
        }
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
        .buttonStyle(.plain)
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
        .accessibilityLabel("\(currentIndex + 1) of \(count)")
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

// MARK: - Category header

private struct CategoryHeader: View {
    let template: VaultTemplate
    let count: Int

    var body: some View {
        HStack(spacing: Theme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(template.accentColor.opacity(0.14))
                Image(systemName: template.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(template.accentColor)
            }
            .frame(width: 32, height: 32)

            Text(template.pluralTitle)
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Theme.textTertiary.opacity(0.14), in: Capsule())
        }
    }
}

// MARK: - Vertical entry row card

private struct EntryRowCard: View {
    let record: VaultEntryRecord
    let fields: [VaultField]

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

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.isEmpty ? record.template.title : record.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(record.template.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    if let expiry = expiryBadgeText {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 4, height: 4)
                        Text(expiry)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(badgeColor)
                    }
                }
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary.opacity(0.6))
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
    }

    private var expiryBadgeText: String? {
        guard record.template.supportsExpiryBadge,
              let date = ExpiryReminderService.shared.expiryDate(forFields: fields, template: record.template)
        else { return nil }
        if date < .now { return "Expired" }
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days <= 30 { return "Expires soon" }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    private var badgeColor: Color {
        guard let date = ExpiryReminderService.shared.expiryDate(forFields: fields, template: record.template) else { return .clear }
        if date < .now { return Theme.danger }
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        return days <= 30 ? Theme.warning : Theme.success
    }
}

// MARK: - Pressable button style

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
