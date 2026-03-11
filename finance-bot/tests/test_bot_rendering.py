from bot import build_confirm_message, build_preview_message
from input_parser import ParseResult, parse_input


def test_build_preview_message_expense_layout():
    result = parse_input("c 50k cafe / momo ; uống sáng với khách")

    assert build_preview_message(result) == (
        "🔴 Chi 50.000đ\n"
        "Category: Cà phê\n"
        "Ví: Momo\n"
        "Note: uống sáng với khách\n"
        "Raw: c 50k cafe / momo ; uống sáng với khách\n"
        "👉 Bấm Confirm để lưu."
    )



def test_build_preview_message_income_missing_category_is_short_and_guided():
    result = ParseResult(
        intent="income",
        amount_vnd=3_000_000,
        category=None,
        wallet="Ngân hàng",
        raw_text="t 3tr abcxyz",
        ambiguous=True,
        issues=["Thiếu danh mục rõ ràng"],
        resolution="ASK",
    )

    assert build_preview_message(result) == (
        "🟢 Thu 3.000.000đ\n"
        "Category: (chưa chọn)\n"
        "Ví: Ngân hàng\n"
        "Raw: t 3tr abcxyz\n"
        "👉 Chỉ cần bấm nút bên dưới để chọn cho đủ rồi Confirm."
    )



def test_build_preview_message_transfer_layout():
    result = parse_input("cv 500k Ngân hàng -> Tiền Mặt ; rút ATM")

    assert build_preview_message(result) == (
        "🔄 Chuyển 500.000đ\n"
        "Category: (chưa chọn)\n"
        "Ví: Ngân hàng -> Tiền Mặt\n"
        "Note: rút ATM\n"
        "Raw: cv 500k Ngân hàng -> Tiền Mặt ; rút ATM\n"
        "👉 Bấm Confirm để lưu."
    )



def test_build_preview_message_truncates_raw_text_to_about_60_chars():
    text = "c 150k an_uong / tien mat ; " + ("abcde " * 20)
    result = parse_input(text)
    message = build_preview_message(result)

    assert "Raw: c 150k an_uong / tien mat ; abcde abcde abcde abcde abcde a…" in message



def test_build_confirm_message_is_compact_two_lines():
    result = parse_input("c 50k cafe / momo ; uống sáng")

    assert build_confirm_message(result, {"id": "tx_123"}) == (
        "✅ Đã ghi: Chi 50.000đ — Cà phê • Momo • uống sáng\n"
        "ID: tx_123"
    )
