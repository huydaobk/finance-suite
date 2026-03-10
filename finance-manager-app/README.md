# finance-manager-app (monorepo)

Repo này chứa **tài liệu/spec** + **source code Flutter** trong cùng một Git repo.

## Cấu trúc thư mục

- `./` (repo root)
  - `SPEC.md`, `BACKLOG.md`, `WORKFLOW.md`, `UI_COPY_VI.md`, ... (tài liệu)
  - `finance_manager_app/` (**Flutter app**)

> Lưu ý: Git `.git/` nằm ở repo root. Flutter project nằm trong `finance_manager_app/`.

## Chạy app (Linux desktop)

```bash
cd /mnt/toshiba/projects/finance-manager-app/finance_manager_app
export PATH="$PATH:/opt/flutter/bin"

flutter pub get
# drift codegen
 dart run build_runner build --delete-conflicting-outputs

flutter analyze
flutter run -d linux
```

## Build release (Linux)

```bash
cd /mnt/toshiba/projects/finance-manager-app/finance_manager_app
export PATH="$PATH:/opt/flutter/bin"

flutter build linux --release
# Output:
# build/linux/x64/release/bundle/finance_manager_app
```

## Demo nhanh (Linux) — 1 click

```bash
cd /mnt/toshiba/projects/finance-manager-app
./run-demo.sh
```

## Checklist test nhanh (5 phút)

1) **Seed**: mở app lần đầu → đợi 1-2s để seed Ví + Danh mục.
2) **Budget**: vào `Cài đặt → Budgets` → tạo **Tổng chi tháng** (ví dụ 1.000.000₫).
3) **Add tx**: vào `Giao dịch` → thêm 2-3 giao dịch **Chi** để tổng chi > 1.000.000₫.
4) **Overspend alert**: vào `Cảnh báo` → thấy alert **Vượt ngân sách tháng**.
5) **Large expense alert**: thêm 1 giao dịch **Chi >= 2.500.000₫** → vào `Cảnh báo` thấy alert **Cảnh báo chi tiêu lớn**.

## Ghi chú

- Android build sẽ cần Android SDK/Android Studio (chưa setup trong repo này).
- Khi hỏi “tiến độ app finance”, ưu tiên nhìn:
  - `BACKLOG.md` (công việc)
  - `finance_manager_app/lib/` (code)
