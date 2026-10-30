import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                .tag(AppTab.dashboard)
            PhoneDealListView()
                .tabItem { Label("Phones", systemImage: "iphone") }
                .tag(AppTab.phones)
            TransactionListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
                .tag(AppTab.transactions)
            BudgetListView()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }
                .tag(AppTab.budgets)
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar") }
                .tag(AppTab.reports)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selection: $router.tab)
        }
        .sheet(item: $router.createType) { type in
            NavigationStack {
                TransactionEditorView(mode: .create(type))
            }
        }
    }
}

private struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            item(.dashboard, "Dashboard", "square.grid.2x2")
            item(.phones, "Phones", "iphone")
            item(.transactions, "Transactions", "list.bullet")
            item(.budgets, "Budgets", "chart.pie")
            item(.reports, "Reports", "chart.bar")
            item(.settings, "Settings", "gearshape")
        }
        .padding(.top, 6)
        .padding(.horizontal, 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func item(_ tab: AppTab, _ title: String, _ systemImage: String) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
