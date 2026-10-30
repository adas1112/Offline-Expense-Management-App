import Foundation
import SwiftData

enum AppPersistence {
    static let schema = Schema([
        Wallet.self,
        Category.self,
        LedgerTransaction.self,
        Budget.self,
        RecurringRule.self,
        AppSettings.self,
        PhoneDeal.self,
        DealerPayment.self
    ])

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [configuration(inMemory: false)])
        } catch {
            AppLog.persistence("Store could not be opened. Recreating the local store.")
            destroyStore()
            do {
                return try ModelContainer(for: schema, configurations: [configuration(inMemory: false)])
            } catch {
                fatalError("Could not create the local finance store.")
            }
        }
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration(inMemory: true)])
    }

    static func configuration(inMemory: Bool) -> ModelConfiguration {
        ModelConfiguration(
            "FinanceStore",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
    }

    static func destroyStore() {
        let configuration = configuration(inMemory: false)
        let url = configuration.url
        let extras = ["", "-shm", "-wal"].map { url.path + $0 }
        for path in extras where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
