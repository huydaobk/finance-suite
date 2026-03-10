# Finance Manager App (Tiếng Việt) — SPEC v1 (MVP + V1.5)

**Repo/Storage:** `/mnt/toshiba/projects/finance-manager-app/`

## 1) Mục tiêu
- App mobile iOS + Android theo dõi **thu/chi** cho cá nhân/gia đình nhỏ.
- Có **cảnh báo** (ngân sách, chi lớn, nhắc hóa đơn) giúp kiểm soát chi tiêu.
- Nhập liệu nhanh: **nhập tay** + **quét hóa đơn (OCR tổng tiền + ngày)**.
- V1.5: hỗ trợ **nhập thu/chi qua Telegram** và chia sẻ nhóm 2–5 người (ai cũng thấy hết).

## 2) Phạm vi MVP (offline-first)
### 2.1 Chức năng
- Giao dịch (thu/chi): thêm/sửa/xóa, danh sách, lọc theo tháng/ví/danh mục/người tạo.
- Danh mục + ví/tài khoản (seed sẵn tiếng Việt).
- Ngân sách tháng: tổng + theo danh mục (top).
- Cảnh báo:
  - Sắp vượt (>=80%) / Vượt (>=100%) ngân sách.
  - Chi lớn (>= 2.500.000đ).
  - Nhắc hóa đơn định kỳ lúc **08:00**.
- Local notifications.
- OCR hóa đơn: lấy **tổng tiền** và **ngày** để prefill form.
- Export CSV.

### 2.2 Phi chức năng
- Ngôn ngữ UI: **Tiếng Việt**.
- Tiền tệ: **VND** (integer, không float).
- Ổn định: không crash trong usage thực tế; thao tác thêm giao dịch nhanh (<10s).

## 3) V1.5 (cloud + Telegram)
- Household 2–5 người, ai cũng xem toàn bộ.
- Telegram bot:
  - Default ví: **MoMo**.
  - Nếu không ghi thu/chi → mặc định là **CHI**.
  - Parse: `chi 120k ăn uống bún bò`, `2tr5 mua sắm áo khoác /momo`.
  - Confirm + undo.

## 4) Tiêu chí nghiệm thu (Definition of Done)
- Thêm giao dịch + xem tổng quan tháng hoạt động trơn tru.
- Cảnh báo ngân sách không spam (80/100 mỗi tháng tối đa 1 lần).
- Nhắc hóa đơn đúng giờ.
- OCR dùng được với hóa đơn rõ nét (tổng tiền nhận đúng >=80%).

## 5) Open questions (để sau)
- Cloud stack chi tiết (Firebase vs self-host).
- Matching hóa đơn “đã thanh toán” (rule nâng cao).
