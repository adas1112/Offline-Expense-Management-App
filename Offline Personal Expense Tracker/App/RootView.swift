import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsRows: [AppSettings]
    @State private var ready = false
    @State private var unlocked = false
    @State private var lockRequired = false

    var body: some View {
        Group {
            if !ready {
                ProgressView("Preparing your ledger")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lockRequired && !unlocked {
                LockView {
                    unlocked = true
                }
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(preferredScheme)
        .task {
            await start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, lockRequired {
                unlocked = false
            }
            if phase == .active, ready {
                maintain()
            }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch settingsRows.first?.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func start() async {
        do {
            try BootstrapService.bootstrap(context: modelContext)
            try RecurringService.generateDue(in: modelContext, calendar: activeCalendar)
            try modelContext.save()
            await BudgetNotificationService.sync(context: modelContext)
        } catch {
            AppLog.persistence("Could not prepare the local database.")
        }
        let enabled = KeychainStore.isAppLockEnabled() || (settingsRows.first?.biometricLockEnabled ?? false)
        lockRequired = enabled
        if enabled {
            KeychainStore.setAppLockEnabled(true)
        }
        ready = true
    }

    private func maintain() {
        do {
            try RecurringService.generateDue(in: modelContext, calendar: activeCalendar)
            try modelContext.save()
        } catch {
            AppLog.persistence("Could not update repeating transactions.")
        }
        Task {
            await BudgetNotificationService.sync(context: modelContext)
        }
    }

    private var activeCalendar: Calendar {
        ReportingPeriod.calendar(firstWeekday: settingsRows.first?.firstWeekday ?? Calendar.current.firstWeekday)
    }
}

struct LockView: View {
    var onUnlock: () -> Void
    @State private var message: String?
    @State private var isAuthenticating = false

    private var availability: (title: String, symbol: String, available: Bool, message: String?) {
        BiometricAuthService.availability()
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: availability.symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Ledger locked")
                .font(.title2.weight(.semibold))
            Text("Unlock with \(availability.title) or your device passcode. Your finances stay on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock") {
                Task { await unlock() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task { await unlock() }
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let result = await BiometricAuthService.authenticate(reason: "Unlock your finance ledger")
        switch result {
        case .success:
            message = nil
            onUnlock()
        case .failure(.canceled):
            message = "Authentication was canceled."
        case .failure(.unavailable(let text)):
            message = text
        case .failure(.failed(let text)):
            message = text
        }
    }
}
