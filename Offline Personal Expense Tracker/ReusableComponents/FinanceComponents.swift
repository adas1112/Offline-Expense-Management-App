import PDFKit
import SwiftUI
import UIKit

struct SectionCard<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct MetricColumn: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct QuickAction: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct BudgetProgress: View {
    var line: BudgetLine
    var currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(line.level?.title ?? "Paused")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }
            ProgressView(value: min(NSDecimalNumber(decimal: line.utilization).doubleValue, 1))
                .tint(tint)
                .accessibilityLabel("\(line.name), \(DisplayFormat.percent(line.utilization)) used")
        }
    }

    private var detail: String {
        let spent = DisplayFormat.money(line.spent, currencyCode: currencyCode)
        let limit = DisplayFormat.money(line.limit, currencyCode: currencyCode)
        return "\(spent) of \(limit)"
    }

    private var tint: Color {
        switch line.level {
        case .exceeded, .reached: Theme.expense
        case .warning: .orange
        case .withinBudget, .none: Theme.income
        }
    }
}

struct TransactionRow: View {
    var transaction: LedgerTransaction
    var currencyDisplay: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.iconName ?? transaction.transactionType.systemImage)
                .font(.body)
                .foregroundStyle(Color(hex: transaction.category?.colorHex ?? "1A6B4A"))
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(currencyDisplay)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let wallet = transaction.wallet?.name ?? "Wallet"
        if transaction.transactionType == .transfer {
            let destination = transaction.destinationWallet?.name ?? "Wallet"
            return "\(wallet) to \(destination)"
        }
        let category = transaction.category?.name ?? "Uncategorized"
        return "\(category) · \(wallet)"
    }

    private var amountColor: Color {
        switch transaction.transactionType {
        case .income: Theme.income
        case .expense: Theme.expense
        case .transfer: .primary
        }
    }
}

struct PeriodMenu: View {
    @Binding var preset: PeriodPreset

    var body: some View {
        Menu {
            ForEach(PeriodPreset.allCases) { item in
                Button(item.title) { preset = item }
            }
        } label: {
            Label(preset.title, systemImage: "calendar")
        }
        .accessibilityLabel("Reporting period, \(preset.title)")
    }
}

struct CustomRangeFields: View {
    @Binding var start: Date
    @Binding var end: Date

    var body: some View {
        DatePicker("Start", selection: $start, displayedComponents: .date)
        DatePicker("End", selection: $end, displayedComponents: .date)
    }
}

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
    let showsPDF: Bool
}

struct ExportPreviewSheet: View {
    var file: ExportedFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if file.showsPDF, let data = try? Data(contentsOf: file.url) {
                    PDFKitView(data: data)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(file.url.lastPathComponent)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("The file is saved in this app’s documents folder. You can also share it from here. Sharing does not require an internet connection.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: file.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share export")
                }
            }
        }
    }
}

struct PDFKitView: View {
    var data: Data

    var body: some View {
        PDFKitRepresentable(data: data)
    }
}

private struct PDFKitRepresentable: UIViewRepresentable {
    var data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(data: data)
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(data: data)
        }
    }
}

func chartDouble(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
}
