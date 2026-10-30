import Foundation
import SwiftData
import UserNotifications

@MainActor
enum DataEraseService {
    static func eraseAll(in context: ModelContext) throws {
        let payments = try context.fetch(FetchDescriptor<DealerPayment>())
        let deals = try context.fetch(FetchDescriptor<PhoneDeal>())
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        for row in payments { context.delete(row) }
        for row in deals { context.delete(row) }
        for row in transactions { context.delete(row) }
        for row in rules { context.delete(row) }
        for row in budgets { context.delete(row) }
        for row in wallets { context.delete(row) }
        for row in categories { context.delete(row) }
        for row in settings { context.delete(row) }
        try context.save()
        AttachmentStore.deleteAll()
        KeychainStore.setAppLockEnabled(false)
        UNCenter.clearBudgetNotifications()
        try BootstrapService.bootstrap(context: context)
    }
}

enum UNCenter {
    static func clearBudgetNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("budget.") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
