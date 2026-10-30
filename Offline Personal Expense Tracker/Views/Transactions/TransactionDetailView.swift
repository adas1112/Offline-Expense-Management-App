import SwiftData
import SwiftUI
import UIKit

struct TransactionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [AppSettings]
    var transaction: LedgerTransaction
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: transaction.transactionType.title)
                LabeledContent("Amount") {
                    Text(DisplayFormat.money(
                        transaction.amount,
                        currencyCode: transaction.currencyCode,
                        direction: direction
                    ))
                    .monospacedDigit()
                }
                LabeledContent("Title", value: transaction.title)
                LabeledContent("Date", value: dateText)
                if let category = transaction.category?.name {
                    LabeledContent("Category", value: category)
                }
                if let wallet = transaction.wallet?.name {
                    LabeledContent(transaction.transactionType == .transfer ? "From" : "Wallet", value: wallet)
                }
                if let destination = transaction.destinationWallet?.name {
                    LabeledContent("To", value: destination)
                }
            }
            Section {
                if !transaction.merchant.isEmpty {
                    LabeledContent("Merchant", value: transaction.merchant)
                }
                if let method = transaction.paymentMethod?.title {
                    LabeledContent("Payment method", value: method)
                }
                if !transaction.notes.isEmpty {
                    Text(transaction.notes)
                }
                if !transaction.tags.isEmpty {
                    Text(transaction.tags.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
            if let fileName = transaction.attachmentFileName, let url = AttachmentStore.url(for: fileName) {
                Section("Attachment") {
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .accessibilityLabel("Transaction attachment")
                    } else {
                        Label(url.lastPathComponent, systemImage: "doc")
                    }
                }
            }
            Section {
                NavigationLink("Edit") {
                    TransactionEditorView(mode: .edit(transaction))
                }
                Button("Delete transaction", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the transaction from this device.")
        }
    }

    private var direction: MoneyDirection {
        switch transaction.transactionType {
        case .income: .income
        case .expense: .expense
        case .transfer: .transfer
        }
    }

    private var dateText: String {
        let calendar = ReportingPeriod.calendar(firstWeekday: settingsRows.first?.firstWeekday ?? 1)
        return DisplayFormat.dateString(transaction.date, preference: settingsRows.first?.dateFormat ?? .medium, calendar: calendar)
    }

    private func delete() {
        AttachmentStore.delete(fileName: transaction.attachmentFileName)
        modelContext.delete(transaction)
        try? modelContext.save()
        Task { await BudgetNotificationService.sync(context: modelContext) }
        dismiss()
    }
}
