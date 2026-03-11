from input_parser import DEFAULT_WALLET, detect_intent, normalize_amount, normalize_wallet, parse_input


def test_normalize_amount_variants():
    assert normalize_amount("85k") == 85_000
    assert normalize_amount("1tr2") == 1_200_000
    assert normalize_amount("1.2tr") == 1_200_000
    assert normalize_amount("50.000") == 50_000
    assert normalize_amount("1,200,000") == 1_200_000
    assert normalize_amount("50000") == 50_000


def test_detect_intent_quick_tokens():
    assert detect_intent("c 45k cafe") == "expense"
    assert detect_intent("t 15tr luong") == "income"
    assert detect_intent("cv 2tr ngăn hàng -> tiền mặt") == "transfer"


def test_normalize_wallet_variants():
    assert normalize_wallet("tiền mặt") == "Tiền Mặt"
    assert normalize_wallet("MOMO") == "Momo"
    assert normalize_wallet("mbbank") == "Ngân hàng"
    assert normalize_wallet("ngan_hang") == "Ngân hàng"


def test_parse_quick_expense_infers_category_and_default_wallet():
    result = parse_input("c 50k cafe")
    assert result.intent == "expense"
    assert result.amount_vnd == 50_000
    assert result.category == "Cà phê"
    assert result.wallet == DEFAULT_WALLET
    assert result.note is None
    assert result.ambiguous is False
    assert result.resolution == "OK"


def test_parse_full_expense_prefers_semicolon_note():
    result = parse_input("c 50k an_uong / Tiền Mặt ; cafe sáng")
    assert result.intent == "expense"
    assert result.amount_vnd == 50_000
    assert result.category == "Ăn uống"
    assert result.wallet == "Tiền Mặt"
    assert result.note == "cafe sáng"
    assert result.ambiguous is False


def test_parse_income_full_format():
    result = parse_input("t 3tr luong / ngân_hàng ; lương tháng 3")
    assert result.intent == "income"
    assert result.amount_vnd == 3_000_000
    assert result.category == "Lương"
    assert result.wallet == "Ngân hàng"
    assert result.note == "lương tháng 3"
    assert result.ambiguous is False


def test_parse_transfer_quick_format():
    result = parse_input("cv 500k Ngân hàng -> Tiền Mặt")
    assert result.intent == "transfer"
    assert result.amount_vnd == 500_000
    assert result.wallet_from == "Ngân hàng"
    assert result.wallet_to == "Tiền Mặt"
    assert result.note is None
    assert result.ambiguous is False


def test_parse_transfer_with_note():
    result = parse_input("cv 1tr2 momo -> ngân_hàng ; nạp lại")
    assert result.intent == "transfer"
    assert result.amount_vnd == 1_200_000
    assert result.wallet_from == "Momo"
    assert result.wallet_to == "Ngân hàng"
    assert result.note == "nạp lại"
    assert result.ambiguous is False


def test_missing_category_returns_ask():
    result = parse_input("c 50k abcxyz")
    assert result.ambiguous is True
    assert result.resolution == "ASK"
    assert any("Thiếu danh mục" in issue for issue in result.issues)
    assert result.wallet == DEFAULT_WALLET
    assert result.note == "abcxyz"


def test_parse_expense_wallet_not_stored_as_note():
    result = parse_input("c 50k an_uong / momo")
    assert result.wallet == "Momo"
    assert result.note is None
    assert result.category == "Ăn uống"
    assert result.ambiguous is False


def test_parse_note_from_remaining_tail_when_category_certain():
    result = parse_input("c 50k cafe họp khách")
    assert result.category == "Cà phê"
    assert result.wallet == DEFAULT_WALLET
    assert result.note == "cafe họp khách"
    assert result.ambiguous is False


def test_parse_expense_plain_number_with_wallet():
    result = parse_input("c 50000 mua_sắm / ngân hàng ; shopee")
    assert result.amount_vnd == 50_000
    assert result.category == "Mua sắm"
    assert result.wallet == "Ngân hàng"
    assert result.note == "shopee"
    assert result.ambiguous is False


def test_parse_expense_dot_thousands():
    result = parse_input("c 50.000 di_chuyen / tien_mat ; grab")
    assert result.amount_vnd == 50_000
    assert result.category == "Di chuyển"
    assert result.wallet == "Tiền Mặt"
    assert result.note == "grab"


def test_parse_income_without_wallet_defaults_to_tien_mat():
    result = parse_input("t 200000 thuong ; thưởng nóng")
    assert result.amount_vnd == 200_000
    assert result.category == "Thưởng"
    assert result.wallet == "Tiền Mặt"
    assert result.note == "thưởng nóng"
    assert result.ambiguous is False


def test_transfer_missing_destination_is_ask():
    result = parse_input("cv 500k momo")
    assert result.intent == "transfer"
    assert result.ambiguous is True
    assert result.resolution == "ASK"
    assert any("Thiếu ví nguồn/đích" in issue for issue in result.issues)
