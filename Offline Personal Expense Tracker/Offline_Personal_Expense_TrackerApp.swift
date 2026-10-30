import SwiftData
import SwiftUI

@main
struct Offline_Personal_Expense_TrackerApp: App {
    @State private var router = AppRouter()
    private let container: ModelContainer

    init() {
        container = AppPersistence.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
        }
        .modelContainer(container)
    }
}
