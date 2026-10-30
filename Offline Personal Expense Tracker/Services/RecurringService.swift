import Foundation
import SwiftData

@MainActor
enum RecurringService {
    static func generateDue(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) throws {
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let existingKeys = Set(transactions.compactMap(\.occurrenceKey))
        let dayStart = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let through = calendar.date(byAdding: .second, value: -1, to: nextDay) ?? now
        for rule in rules where !rule.isPaused {
            guard let wallet = rule.wallet, !wallet.isArchived else { continue }
            if rule.templateType == .transfer {
                guard let destination = rule.destinationWallet, !destination.isArchived else { continue }
            }
            var emitted = Set(rule.emittedOccurrenceKeys).union(existingKeys)
            let plan = RecurrencePlan(
                id: rule.id,
                frequency: rule.frequency,
                start: rule.startDate,
                end: rule.endDate,
                isPaused: false,
                emittedKeys: emitted
            )
            let dates = RecurringScheduler.occurrenceDates(plan: plan, through: through, calendar: calendar)
            for date in dates {
                let key = RecurringScheduler.occurrenceKey(ruleID: rule.id, date: date, calendar: calendar)
                guard !emitted.contains(key) else { continue }
                let transaction = LedgerTransaction(
                    type: rule.templateType,
                    amount: rule.templateAmount,
                    currencyCode: rule.currencyCode,
                    title: rule.templateTitle,
                    notes: rule.templateNotes,
                    date: date,
                    tags: rule.templateTags,
                    paymentMethod: rule.templatePaymentMethod,
                    merchant: rule.templateMerchant,
                    isDemo: rule.isDemo,
                    occurrenceKey: key
                )
                transaction.category = rule.category
                transaction.wallet = rule.wallet
                transaction.destinationWallet = rule.destinationWallet
                transaction.recurringRule = rule
                context.insert(transaction)
                emitted.insert(key)
                if !rule.emittedOccurrenceKeys.contains(key) {
                    rule.emittedOccurrenceKeys.append(key)
                }
            }
        }
    }

    static func pause(_ rule: RecurringRule, now: Date = Date()) {
        rule.isPaused = true
        rule.pausedAt = now
    }

    static func resume(_ rule: RecurringRule, now: Date = Date(), calendar: Calendar = .current) {
        let pausedAt = rule.pausedAt ?? now
        let plan = RecurrencePlan(
            id: rule.id,
            frequency: rule.frequency,
            start: rule.startDate,
            end: rule.endDate,
            isPaused: false,
            emittedKeys: []
        )
        let suppressed = RecurringScheduler.keysToSuppress(
            plan: plan,
            pausedAt: pausedAt,
            through: now,
            calendar: calendar
        )
        for key in suppressed where !rule.emittedOccurrenceKeys.contains(key) {
            rule.emittedOccurrenceKeys.append(key)
        }
        rule.isPaused = false
        rule.pausedAt = nil
    }
}
