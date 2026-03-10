# Architecture — Finance Manager App (Offline-first + V1.5)

## 1) Tech stack (MVP)
- Flutter
- Local DB: SQLite + drift
- Local notifications
- OCR: ML Kit (on-device) or platform OCR (final pick in implementation)

## 2) High-level modules
- transactions
- categories
- wallets
- budgets
- bills
- alerts
- receipt_scan (OCR)
- export

## 3) Data model
See schema draft in earlier chat; implement in drift with migrations.
Key rules:
- amount: INTEGER (VND)
- month key: YYYY-MM

## 4) Alert engine
- Trigger-on-write (khi tạo giao dịch): overspend + chi lớn
- Daily scheduler 08:00: bill due/overdue
- Store alert_events with status new/seen/dismissed

## 5) V1.5 Telegram input
- Bot webhook → backend → writes transactions to shared store
- App consumes via sync (future)
