# Telegram Bot Spec (V1.5)

## Defaults
- Default wallet: MoMo
- Default type: Expense (CHI) when not specified

## Input syntax
- Expense: `chi 120k an uong bun bo` / `c 120k cafe`
- Income: `thu 15tr luong` / `t 5tr thuong`
- Wallet override: append `/momo` `/cash` `/bank`

## Amount parser
- `k` => *1,000
- `tr` => *1,000,000
- `2tr5` => 2,500,000

## Bot responses
- Confirmation message with inline buttons: Undo (5 min), Change category, Change wallet

## Linking flow
- App generates 6-digit code (10 min expiry)
- User sends code to bot to link telegramChatId to userId/householdId
