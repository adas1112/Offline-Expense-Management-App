import Foundation
import SwiftData

@MainActor
enum BackupApplier {
    static func makeDocument(context: ModelContext, exportedAt: Date = Date()) throws -> BackupDocument {
        let settings = try BootstrapService.ensureSettings(context: context)
        let categories = try context.fetch(FetchDescriptor<Category>())
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let phoneDeals = try context.fetch(FetchDescriptor<PhoneDeal>())
        return BackupDocument(
            format: BackupCodec.formatIdentifier,
            version: BackupCodec.version,
            exportedAt: exportedAt,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            settings: SettingsRecord(
                id: settings.id,
                baseCurrencyCode: settings.baseCurrencyCode,
                dateFormat: settings.dateFormatRaw,
                firstWeekday: settings.firstWeekday,
                appearance: settings.appearanceRaw,
                biometricLockEnabled: settings.biometricLockEnabled,
                budgetNotificationsEnabled: settings.budgetNotificationsEnabled,
                warningThreshold: Money.exportString(Decimal(settings.warningThreshold)),
                didSeedCategories: settings.didSeedCategories,
                demoDataInstalled: settings.demoDataInstalled
            ),
            categories: categories.map {
                CategoryRecord(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.kindRaw,
                    iconName: $0.iconName,
                    colorHex: $0.colorHex,
                    sortOrder: $0.sortOrder,
                    isArchived: $0.isArchived,
                    createdAt: $0.createdAt
                )
            },
            wallets: wallets.map {
                WalletRecord(
                    id: $0.id,
                    name: $0.name,
                    type: $0.typeRaw,
                    currencyCode: $0.currencyCode,
                    openingBalance: Money.exportString($0.openingBalance),
                    iconName: $0.iconName,
                    colorHex: $0.colorHex,
                    createdAt: $0.createdAt,
                    isArchived: $0.isArchived,
                    isDemo: $0.isDemo
                )
            },
            budgets: budgets.map {
                BudgetRecord(
                    id: $0.id,
                    name: $0.name,
                    amount: Money.exportString($0.amount),
                    currencyCode: $0.currencyCode,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    warningThreshold: Money.exportString(Decimal($0.warningThreshold)),
                    isOverall: $0.isOverall,
                    categoryID: $0.category?.id,
                    isPaused: $0.isPaused,
                    isArchived: $0.isArchived,
                    isDemo: $0.isDemo,
                    notifyAtWarning: $0.notifyAtWarning,
                    notifyAtExceeded: $0.notifyAtExceeded,
                    createdAt: $0.createdAt
                )
            },
            recurringRules: rules.map {
                RecurringRuleRecord(
                    id: $0.id,
                    frequency: $0.frequencyRaw,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isPaused: $0.isPaused,
                    pausedAt: $0.pausedAt,
                    templateTitle: $0.templateTitle,
                    templateAmount: Money.exportString($0.templateAmount),
                    templateType: $0.templateTypeRaw,
                    templateNotes: $0.templateNotes,
                    templateTags: $0.templateTags,
                    templateMerchant: $0.templateMerchant,
                    templatePaymentMethod: $0.templatePaymentMethodRaw,
                    currencyCode: $0.currencyCode,
                    emittedOccurrenceKeys: $0.emittedOccurrenceKeys,
                    isDemo: $0.isDemo,
                    createdAt: $0.createdAt,
                    categoryID: $0.category?.id,
                    walletID: $0.wallet?.id,
                    destinationWalletID: $0.destinationWallet?.id
                )
            },
            transactions: transactions.map { transaction in
                let attachment = transaction.attachmentFileName.flatMap { AttachmentStore.data(for: $0)?.base64EncodedString() }
                return TransactionRecord(
                    id: transaction.id,
                    type: transaction.typeRaw,
                    amount: Money.exportString(transaction.amount),
                    currencyCode: transaction.currencyCode,
                    title: transaction.title,
                    notes: transaction.notes,
                    date: transaction.date,
                    createdAt: transaction.createdAt,
                    updatedAt: transaction.updatedAt,
                    tags: transaction.tags,
                    paymentMethod: transaction.paymentMethodRaw,
                    merchant: transaction.merchant,
                    attachmentFileName: transaction.attachmentFileName,
                    attachmentBase64: attachment,
                    isDemo: transaction.isDemo,
                    occurrenceKey: transaction.occurrenceKey,
                    categoryID: transaction.category?.id,
                    walletID: transaction.wallet?.id,
                    destinationWalletID: transaction.destinationWallet?.id,
                    recurringRuleID: transaction.recurringRule?.id
                )
            },
            phoneDeals: phoneDeals.map { deal in
                PhoneDealRecord(
                    id: deal.id,
                    phoneName: deal.phoneName,
                    platform: deal.platformRaw,
                    platformDetail: deal.platformDetail,
                    quantity: deal.quantity,
                    orderReference: deal.orderReference,
                    purchaseAmount: Money.exportString(deal.purchaseAmount),
                    offerDiscount: Money.exportString(deal.offerDiscount),
                    purchaseDate: deal.purchaseDate,
                    currencyCode: deal.currencyCode,
                    notes: deal.notes,
                    purchaseWalletID: deal.purchaseWallet?.id,
                    purchaseTransactionID: deal.purchaseTransactionID,
                    isSold: deal.isSold,
                    dealerName: deal.dealerName,
                    quantitySold: deal.quantitySold,
                    saleAmount: Money.exportString(deal.saleAmount),
                    saleDate: deal.saleDate,
                    receiptWalletID: deal.receiptWallet?.id,
                    payments: deal.payments.map { payment in
                        DealerPaymentRecord(
                            id: payment.id,
                            amount: Money.exportString(payment.amount),
                            date: payment.date,
                            note: payment.note,
                            transactionID: payment.transactionID
                        )
                    },
                    createdAt: deal.createdAt
                )
            }
        )
    }

    static func replaceAll(with document: BackupDocument, in context: ModelContext) throws {
        try BackupCodec.validate(document)
        let dealerPayments = try context.fetch(FetchDescriptor<DealerPayment>())
        let phoneDeals = try context.fetch(FetchDescriptor<PhoneDeal>())
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let settingsRows = try context.fetch(FetchDescriptor<AppSettings>())
        for row in dealerPayments { context.delete(row) }
        for row in phoneDeals { context.delete(row) }
        for row in transactions { context.delete(row) }
        for row in rules { context.delete(row) }
        for row in budgets { context.delete(row) }
        for row in wallets { context.delete(row) }
        for row in categories { context.delete(row) }
        for row in settingsRows { context.delete(row) }

        var categoryMap: [UUID: Category] = [:]
        for record in document.categories {
            let category = Category(
                id: record.id,
                name: record.name,
                kind: CategoryKind(rawValue: record.kind) ?? .expense,
                iconName: record.iconName,
                colorHex: record.colorHex,
                sortOrder: record.sortOrder,
                isArchived: record.isArchived,
                createdAt: record.createdAt
            )
            context.insert(category)
            categoryMap[record.id] = category
        }
        var walletMap: [UUID: Wallet] = [:]
        for record in document.wallets {
            let wallet = Wallet(
                id: record.id,
                name: record.name,
                type: WalletType(rawValue: record.type) ?? .custom,
                currencyCode: record.currencyCode,
                openingBalance: BackupCodec.decimal(record.openingBalance) ?? 0,
                iconName: record.iconName,
                colorHex: record.colorHex,
                createdAt: record.createdAt,
                isArchived: record.isArchived,
                isDemo: record.isDemo
            )
            context.insert(wallet)
            walletMap[record.id] = wallet
        }
        let settingsRecord = document.settings
        let settings = AppSettings(
            id: settingsRecord.id,
            baseCurrencyCode: settingsRecord.baseCurrencyCode,
            dateFormat: DateFormatPreference(rawValue: settingsRecord.dateFormat) ?? .medium,
            firstWeekday: settingsRecord.firstWeekday,
            appearance: AppearancePreference(rawValue: settingsRecord.appearance) ?? .system,
            biometricLockEnabled: settingsRecord.biometricLockEnabled,
            budgetNotificationsEnabled: settingsRecord.budgetNotificationsEnabled,
            warningThreshold: Double(truncating: (BackupCodec.decimal(settingsRecord.warningThreshold) ?? 0.8) as NSDecimalNumber),
            didSeedCategories: settingsRecord.didSeedCategories,
            demoDataInstalled: settingsRecord.demoDataInstalled
        )
        context.insert(settings)

        var ruleMap: [UUID: RecurringRule] = [:]
        for record in document.recurringRules {
            let rule = RecurringRule(
                id: record.id,
                frequency: RecurrenceFrequency(rawValue: record.frequency) ?? .monthly,
                startDate: record.startDate,
                endDate: record.endDate,
                isPaused: record.isPaused,
                pausedAt: record.pausedAt,
                templateTitle: record.templateTitle,
                templateAmount: BackupCodec.decimal(record.templateAmount) ?? 0,
                templateType: TransactionType(rawValue: record.templateType) ?? .expense,
                templateNotes: record.templateNotes,
                templateTags: record.templateTags,
                templateMerchant: record.templateMerchant,
                templatePaymentMethod: record.templatePaymentMethod.flatMap(PaymentMethod.init(rawValue:)),
                currencyCode: record.currencyCode,
                emittedOccurrenceKeys: record.emittedOccurrenceKeys,
                isDemo: record.isDemo,
                createdAt: record.createdAt
            )
            rule.category = record.categoryID.flatMap { categoryMap[$0] }
            rule.wallet = record.walletID.flatMap { walletMap[$0] }
            rule.destinationWallet = record.destinationWalletID.flatMap { walletMap[$0] }
            context.insert(rule)
            ruleMap[record.id] = rule
        }
        for record in document.budgets {
            let budget = Budget(
                id: record.id,
                name: record.name,
                amount: BackupCodec.decimal(record.amount) ?? 0,
                currencyCode: record.currencyCode,
                startDate: record.startDate,
                endDate: record.endDate,
                warningThreshold: Double(truncating: (BackupCodec.decimal(record.warningThreshold) ?? 0.8) as NSDecimalNumber),
                isOverall: record.isOverall,
                isPaused: record.isPaused,
                isArchived: record.isArchived,
                isDemo: record.isDemo,
                notifyAtWarning: record.notifyAtWarning,
                notifyAtExceeded: record.notifyAtExceeded,
                createdAt: record.createdAt
            )
            budget.category = record.categoryID.flatMap { categoryMap[$0] }
            context.insert(budget)
        }
        AttachmentStore.deleteAll()
        for record in document.transactions {
            var fileName = record.attachmentFileName
            if let encoded = record.attachmentBase64, let data = Data(base64Encoded: encoded) {
                let ext = record.attachmentFileName.flatMap { URL(fileURLWithPath: $0).pathExtension } ?? "bin"
                fileName = try? AttachmentStore.save(data: data, fileExtension: ext.isEmpty ? "bin" : ext)
            } else {
                fileName = nil
            }
            let transaction = LedgerTransaction(
                id: record.id,
                type: TransactionType(rawValue: record.type) ?? .expense,
                amount: BackupCodec.decimal(record.amount) ?? 0,
                currencyCode: record.currencyCode,
                title: record.title,
                notes: record.notes,
                date: record.date,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                tags: record.tags,
                paymentMethod: record.paymentMethod.flatMap(PaymentMethod.init(rawValue:)),
                merchant: record.merchant,
                attachmentFileName: fileName,
                isDemo: record.isDemo,
                occurrenceKey: record.occurrenceKey
            )
            transaction.category = record.categoryID.flatMap { categoryMap[$0] }
            transaction.wallet = record.walletID.flatMap { walletMap[$0] }
            transaction.destinationWallet = record.destinationWalletID.flatMap { walletMap[$0] }
            transaction.recurringRule = record.recurringRuleID.flatMap { ruleMap[$0] }
            context.insert(transaction)
        }
        for record in document.phoneDeals {
            let deal = PhoneDeal(
                id: record.id,
                phoneName: record.phoneName,
                platform: ShopPlatform(rawValue: record.platform) ?? .other,
                platformDetail: record.platformDetail,
                quantity: record.quantity,
                orderReference: record.orderReference,
                purchaseAmount: BackupCodec.decimal(record.purchaseAmount) ?? 0,
                offerDiscount: BackupCodec.decimal(record.offerDiscount) ?? 0,
                purchaseDate: record.purchaseDate,
                currencyCode: record.currencyCode,
                notes: record.notes,
                purchaseTransactionID: record.purchaseTransactionID,
                isSold: record.isSold,
                dealerName: record.dealerName,
                quantitySold: record.quantitySold,
                saleAmount: BackupCodec.decimal(record.saleAmount) ?? 0,
                saleDate: record.saleDate,
                createdAt: record.createdAt
            )
            deal.purchaseWallet = record.purchaseWalletID.flatMap { walletMap[$0] }
            deal.receiptWallet = record.receiptWalletID.flatMap { walletMap[$0] }
            context.insert(deal)
            for paymentRecord in record.payments {
                let payment = DealerPayment(
                    id: paymentRecord.id,
                    amount: BackupCodec.decimal(paymentRecord.amount) ?? 0,
                    date: paymentRecord.date,
                    note: paymentRecord.note,
                    transactionID: paymentRecord.transactionID
                )
                payment.deal = deal
                context.insert(payment)
            }
        }
        try context.save()
        if settings.biometricLockEnabled {
            KeychainStore.setAppLockEnabled(true)
        }
    }
}
