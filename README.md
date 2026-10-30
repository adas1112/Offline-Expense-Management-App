# Offline Personal Expense Tracker

A native iOS ledger for personal finances. It runs entirely on the device: there is no account, backend, or network API.

## Setup

1. Open `Offline Personal Expense Tracker.xcodeproj` in Xcode 26 or later.
2. Select the **Offline Personal Expense Tracker** scheme and an iPhone simulator or your device.
3. Build and run. The deployment target is **iOS 17.0**.

The first launch creates local settings and a set of income and expense categories. It does not add wallets or transactions until you do. Example data is optional and lives under Settings.

Unit tests are in the **FinanceTests** target. Run them with Product → Test, or:

```sh
xcodebuild -project "Offline Personal Expense Tracker.xcodeproj" \
  -scheme "Offline Personal Expense Tracker" \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  test
```

## Architecture

The app uses SwiftUI and MVVM. Financial rules live in services, not in view bodies.

| Area | Responsibility |
| --- | --- |
| `Models` | SwiftData records: wallets, categories, transactions, budgets, repeating rules, phone purchases, settings |
| `Services/LedgerCalculator.swift` | Income, expenses, transfers, wallet balances, and net worth |
| `Services/BudgetCalculator.swift` | Spending against a budget and warning thresholds |
| `Services/ReportBuilder.swift` | Chart and report values, using the calculator above |
| `Services/CSVExporter.swift` and `PDFExporter.swift` | On-device export |
| `Services/BackupService.swift` | Versioned backup format and validation |
| `Views` | Dashboard, Transactions, Budgets, Reports, and Settings |
| `FinanceTests` | Calculation, export, backup, and SwiftData tests |

The Swift module name is `OfflineFinance`.

## Accounting rules

Money is stored and summed as `Decimal`, then rounded with banker’s rounding to the currency’s minor units (for example 2 for USD, 0 for JPY, 3 for KWD).

For a reporting period, in the base currency:

- **Income** is the sum of income transactions.
- **Expenses** are the sum of expense transactions.
- **Net cash flow** is income minus expenses.
- **Transfers are not income or expenses**, and they do not change consolidated net worth.

Wallet balances:

- Asset wallets (cash, bank, savings, digital, custom): opening balance + money in − money out.
- Credit cards are liabilities. A positive balance is the amount owed. Purchases increase it. Refunds and payments decrease it.
- **Net worth** is asset balances minus credit-card balances.

Only wallets in the **base currency** are included in consolidated totals. The app does not download exchange rates, so it will not add amounts from different currencies together. Those wallets still show their own balances.

Current wallet balances include every stored transaction. Period reports include only transactions inside the selected dates. A budget counts expense transactions inside its own start and end dates, and ignores income and transfers.

Repeating transactions use an occurrence key, `ruleID#yyyy-MM-dd`. A key is recorded when an occurrence is created. Deleting that transaction does not create it again. Pausing a rule suppresses the dates that fall inside the paused gap when you resume it.

## Data storage

SwiftData stores the ledger in the app’s Application Support directory (`FinanceStore.store`). CloudKit is disabled. Attachments are copied into Application Support and written with iOS data protection until the first unlock after boot. The optional app-lock flag is kept in the Keychain and is not a PIN.

iOS file protection applies to the app container. This app does not claim end-to-end encryption.

Deleting the app can delete this data if you have not kept a backup.

## Backup format

Backups are UTF-8 JSON files named like `FinanceBackup-2026-10-29.json`.

- `format` must be `offline-finance-backup`
- `version` must be `1`
- Amounts are decimal strings, not binary floating-point numbers
- Dates are ISO-8601
- The file includes settings, categories, wallets, budgets, repeating rules, transactions, and phone purchases. Backups made before phone tracking simply have no phone list.
- Attachment bytes, when present, are Base64

Restore checks the format, version, identifiers, and relationships before it changes anything. Restoring **replaces** the on-device ledger. It does not merge, so importing the same file twice does not duplicate records. You must confirm the replacement first.

Create a backup from Settings. The file is written under the app’s Documents folder (`Backups` or `Exports`) and can be shared with the system share sheet, including the Files app. Creating the file does not need a network connection. Where you send it afterwards is your choice.

CSV exports use the columns Date, Type, Title, Category, Wallet, Amount, Currency, Payment method, Notes, and Tags. Commas, quotes, and line breaks are escaped. PDF reports are generated with UIGraphicsPDFRenderer and opened with PDFKit.

## Offline operation

The app does not use URL sessions, accounts, remote analytics, ads, or cloud sync. Reports, charts, search, filters, PDF and CSV files, backups, and reminders are computed on the device. Budget notifications are local notifications. Face ID or Touch ID app lock uses LocalAuthentication, with the device passcode as the fallback.

You can use the app in Airplane Mode. Consolidated totals stay in the base currency you choose in Settings.

## Phone resale

The Phones tab is for handsets bought on a card offer and sold to a dealer.

- Record the store (Amazon, Flipkart, JioMart, or another), the phone, how many you bought, and the amount you actually paid. An optional offer amount is only a note. Profit uses the amount paid.
- Choosing a credit card posts that purchase as a card expense, so the card balance is the amount still owed to the bank.
- When you sell, enter the dealer and the agreed price. You can sell fewer phones than you bought. The unsold share stays in stock at its share of the cost.
- Each payment the dealer sends is recorded separately. **Pending** is the sale price minus payments received. **Received** is money already paid. A deal is settled when pending reaches zero.
- Profit on a sold phone is the sale price minus the cost of the phones that were sold. Dealer payments are also posted as income in the wallet you choose, so the main ledger stays in step with the cash you actually receive.
