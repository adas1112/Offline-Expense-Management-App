import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            selectedTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    TabBarClearance()
                }
            AppTabBar(selection: $router.tab)
                .background(.bar, ignoresSafeAreaEdges: .bottom)
        }
        .sheet(item: $router.createType) { type in
            NavigationStack {
                TransactionEditorView(mode: .create(type))
            }
        }
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch router.tab {
        case .dashboard:
            DashboardView()
        case .phones:
            PhoneDealListView()
        case .transactions:
            TransactionListView()
        case .budgets:
            BudgetListView()
        case .reports:
            ReportsView()
        case .settings:
            SettingsView()
        }
    }
}

/// Lists end exactly at the tab bar, so the last row sits underneath it.
/// This keeps a gap between the scroll content and the bar.
private struct TabBarClearance: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ClearanceController {
        ClearanceController()
    }

    func updateUIViewController(_ controller: ClearanceController, context: Context) {
        controller.apply()
    }

    final class ClearanceController: UIViewController {
        private let inset: CGFloat = 20
        private var didSchedule = false

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            apply()
            guard !didSchedule else { return }
            didSchedule = true
            DispatchQueue.main.async { [weak self] in
                self?.apply()
            }
        }

        func apply() {
            guard let root = view.window?.rootViewController else { return }
            for navigation in navigationControllers(from: root) where navigation.presentingViewController == nil && navigation.view.window != nil {
                if abs(navigation.additionalSafeAreaInsets.bottom - inset) > 0.5 {
                    navigation.additionalSafeAreaInsets.bottom = inset
                }
                padScrollViews(in: navigation.view)
            }
        }

        private func padScrollViews(in view: UIView) {
            if let scroll = view as? UIScrollView, scroll.contentInset.bottom < inset {
                scroll.contentInset.bottom = inset
                scroll.verticalScrollIndicatorInsets.bottom = inset
            }
            for subview in view.subviews {
                padScrollViews(in: subview)
            }
        }

        private func navigationControllers(from controller: UIViewController) -> [UINavigationController] {
            var found: [UINavigationController] = []
            if let navigation = controller as? UINavigationController {
                found.append(navigation)
            }
            for child in controller.children {
                found.append(contentsOf: navigationControllers(from: child))
            }
            return found
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
        .padding(.top, 8)
        .padding(.bottom, 4)
        .padding(.horizontal, 2)
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
