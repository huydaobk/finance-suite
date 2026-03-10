# Finance Manager App

A personal finance management Flutter application.

## Requirements

- Flutter SDK 3.0.0+
- Dart SDK 3.0.0+
- Android SDK (for Android builds)
- Xcode (for iOS builds, macOS only)

## Setup

1. Clone the repository
2. Navigate to the project directory:
   ```bash
   cd finance_manager_app
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```

## Generate Drift Database Code

Before building, generate the Drift database code:
```bash
dart run build_runner build --delete-conflicting-outputs
```

## Build & Run

### Debug Build
```bash
flutter run
```

### Release Build (Android)
```bash
flutter build apk --release
```

### Release Build (iOS)
```bash
flutter build ios --release
```

## Project Structure

```
lib/
├── core/
│   ├── db/              # Database layer (Drift)
│   ├── l10n/            # Localization
│   └── utils/           # Utilities
├── features/
│   ├── transactions/    # Transactions feature
│   ├── budgets/        # Budgets feature
│   ├── bills/           # Bills feature
│   ├── alerts/          # Alerts feature
│   ├── receipt_scan/    # Receipt scanning feature
│   └── settings/        # Settings feature
└── main.dart
```

## Features

- **Tổng quan (Overview)**: Dashboard with financial summary
- **Giao dịch (Transactions)**: Transaction management
- **Ngân sách (Budgets)**: Budget planning and tracking
- **Hóa đơn (Bills)**: Bill management and reminders
- **Cảnh báo (Alerts)**: Financial alerts and notifications
- **Quét hóa đơn (Receipt Scan)**: OCR receipt scanning
- **Cài đặt (Settings)**: App settings

## Localization

The app uses Vietnamese (vi) as the default locale. Add more locales in `lib/core/l10n/app_vi.arb` and update `l10n.yaml`.
