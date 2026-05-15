import Combine
import Foundation
import UserNotifications

final class ExpiryReminderService: ObservableObject {
    static let shared = ExpiryReminderService()

    private let enabledKey = "reminders.enabled"
    private let idPrefix = "kryptos.expiry."
    private let leadDays = [30, 7, 1]
    private let calendar = Calendar.current

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            await refreshAuthorizationStatus()
            return granted
        @unknown default:
            return false
        }
    }

    func sync(records: [VaultEntryRecord]) async {
        guard isEnabled else {
            await cancelAll()
            return
        }
        guard await requestAuthorization() else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let keepIDs = Set(records.flatMap(reminderIDs(for:)))
        let stale = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(idPrefix) && !keepIDs.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for record in records {
            await scheduleReminders(for: record, skipAuthorizationCheck: true)
        }
    }

    func scheduleReminders(for record: VaultEntryRecord, skipAuthorizationCheck: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: reminderIDs(for: record))

        guard isEnabled else { return }
        guard let expiry = expiryDate(for: record) else { return }
        if !skipAuthorizationCheck {
            guard await requestAuthorization() else { return }
        }

        for days in leadDays {
            guard
                let fireDay = calendar.date(byAdding: .day, value: -days, to: expiry),
                let fireDate = alertTime(for: fireDay),
                fireDate > .now
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(record.template.title) expiring soon"
            content.body = body(for: record, days: days)
            content.sound = .default
            content.userInfo = ["recordID": record.id.uuidString]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(for: record.id, days: days),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancelReminders(for recordID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: leadDays.map { identifier(for: recordID, days: $0) }
        )
    }

    func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func identifier(for recordID: UUID, days: Int) -> String {
        "\(idPrefix)\(recordID.uuidString).\(days)"
    }

    private func reminderIDs(for record: VaultEntryRecord) -> [String] {
        leadDays.map { identifier(for: record.id, days: $0) }
    }

    func expiryDate(forFields fields: [VaultField], template: VaultTemplate) -> Date? {
        let raw = fields.firstValue("Expiry", "Expires", "Expiration", "Expiration date", "Expiry date")
        return parseExpiry(raw, template: template)
    }

    private func expiryDate(for record: VaultEntryRecord) -> Date? {
        let fields = (try? VaultCrypto.shared.decodeFields(record.encryptedFields)) ?? []
        return expiryDate(forFields: fields, template: record.template)
    }

    private func parseExpiry(_ value: String, template: VaultTemplate) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let monthYear = parseMonthYear(trimmed) {
            return endOfMonth(monthYear)
        }

        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "dd/MM/yyyy",
            "MM/dd/yyyy",
            "dd-MM-yyyy",
            "dd MMM yyyy",
            "dd MMMM yyyy",
            "MMM dd, yyyy",
            "d MMM yyyy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    private func parseMonthYear(_ value: String) -> Date? {
        let digits = value.filter { $0.isNumber }
        let month: Int
        let year: Int
        switch digits.count {
        case 4:
            month = Int(digits.prefix(2)) ?? 0
            year = (Int(digits.suffix(2)) ?? 0) + 2000
        case 6:
            month = Int(digits.prefix(2)) ?? 0
            year = Int(digits.suffix(4)) ?? 0
        default:
            return nil
        }
        guard (1...12).contains(month), year >= 2000, year < 2100 else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components)
    }

    private func endOfMonth(_ date: Date) -> Date {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return date }
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = range.count
        return calendar.date(from: components) ?? date
    }

    private func alertTime(for date: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)
    }

    private func body(for record: VaultEntryRecord, days: Int) -> String {
        let label = record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? record.template.title
            : record.title
        if days == 1 { return "\(label) expires tomorrow." }
        return "\(label) expires in \(days) days."
    }
}
