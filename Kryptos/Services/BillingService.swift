import Combine
import Foundation
import StoreKit

@MainActor
final class BillingService: ObservableObject {
    static let freeEntryLimit = 10
    static let productID = "kryptos_pro_upgrade"

    @Published private(set) var isPremium: Bool
    @Published var message: String?

    private let premiumKey = "billing.isPremium"

    init() {
        isPremium = UserDefaults.standard.bool(forKey: premiumKey)
        Task { await refreshEntitlements() }
    }

    func purchasePremium() async {
        do {
            guard let product = try await Product.products(for: [Self.productID]).first else {
                message = "Pro upgrade is not configured in App Store Connect yet."
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "The purchase could not be verified."
                    return
                }
                await transaction.finish()
                setPremium(true)
            case .userCancelled:
                break
            case .pending:
                message = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID {
                setPremium(true)
                return
            }
        }
    }

    func restorePurchases() async {
        message = "Restoring purchases…"
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPremium ? "Pro restored." : "No previous Pro purchase found on this Apple ID."
        } catch {
            message = error.localizedDescription
        }
    }

    private func setPremium(_ value: Bool) {
        isPremium = value
        UserDefaults.standard.set(value, forKey: premiumKey)
    }
}
