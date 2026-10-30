import Foundation
import SwiftData

@Model
final class AppSettings {
    var id: UUID
    var baseCurrencyCode: String
    var dateFormatRaw: String
    var firstWeekday: Int
    var appearanceRaw: String
    var biometricLockEnabled: Bool
    var budgetNotificationsEnabled: Bool
    var warningThreshold: Double
    var didSeedCategories: Bool
    var demoDataInstalled: Bool

    init(
        id: UUID = UUID(),
        baseCurrencyCode: String = "USD",
        dateFormat: DateFormatPreference = .medium,
        firstWeekday: Int = 1,
        appearance: AppearancePreference = .system,
        biometricLockEnabled: Bool = false,
        budgetNotificationsEnabled: Bool = false,
        warningThreshold: Double = 0.8,
        didSeedCategories: Bool = false,
        demoDataInstalled: Bool = false
    ) {
        self.id = id
        self.baseCurrencyCode = baseCurrencyCode.uppercased()
        self.dateFormatRaw = dateFormat.rawValue
        self.firstWeekday = firstWeekday
        self.appearanceRaw = appearance.rawValue
        self.biometricLockEnabled = biometricLockEnabled
        self.budgetNotificationsEnabled = budgetNotificationsEnabled
        self.warningThreshold = warningThreshold
        self.didSeedCategories = didSeedCategories
        self.demoDataInstalled = demoDataInstalled
    }

    var dateFormat: DateFormatPreference {
        get { DateFormatPreference(rawValue: dateFormatRaw) ?? .medium }
        set { dateFormatRaw = newValue.rawValue }
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }
}
