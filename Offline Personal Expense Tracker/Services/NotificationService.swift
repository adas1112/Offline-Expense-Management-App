import Foundation
import SwiftData
import UserNotifications

@MainActor
enum BudgetNotificationService {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func sync(context: ModelContext) async {
        let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("budget.") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard settings?.budgetNotificationsEnabled == true else { return }
        let allowed = await authorizationStatus()
        guard allowed == .authorized || allowed == .provisional || allowed == .ephemeral else { return }

        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let transactions = LedgerSnapshot.transactions(from: (try? context.fetch(FetchDescriptor<LedgerTransaction>())) ?? [])
        for budget in budgets {
            guard !budget.isPaused, !budget.isArchived else { continue }
            guard budget.notifyAtWarning || budget.notifyAtExceeded else { continue }
            let line = BudgetCalculator.line(
                for: budget.financeValue(),
                transactions: transactions,
                categoryName: budget.category?.name
            )
            let periodKey = "\(budget.startDate.timeIntervalSince1970)-\(budget.endDate.timeIntervalSince1970)"
            if budget.notifyAtExceeded, line.level == .exceeded || line.level == .reached {
                if budget.exceededNotifiedKey != periodKey {
                    schedule(
                        id: "budget.\(budget.id.uuidString).exceeded",
                        title: "Budget reached",
                        body: "\(budget.name) has reached its limit."
                    )
                    budget.exceededNotifiedKey = periodKey
                }
            } else if budget.notifyAtWarning, line.level == .warning {
                if budget.warningNotifiedKey != periodKey {
                    schedule(
                        id: "budget.\(budget.id.uuidString).warning",
                        title: "Budget warning",
                        body: "\(budget.name) has passed its warning threshold."
                    )
                    budget.warningNotifiedKey = periodKey
                }
            }
            if line.level == .withinBudget {
                budget.warningNotifiedKey = nil
                budget.exceededNotifiedKey = nil
            }
        }
        try? context.save()
    }

    private static func schedule(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
