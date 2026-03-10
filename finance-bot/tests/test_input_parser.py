from input_parser import detect_intent, normalize_amount, parse_input


def test_normalize_amount_variants():
    assert normalize_amount("85k") == 85_000
    assert normalize_amount("1tr2") == 1_200_000
    assert normalize_amount("1.2tr") == 1_200_000
    assert normalize_amount("1,200,000") == 1_200_000


def test_detect_intent():
    assert detect_intent("chi 45k cafe ví: tiền mặt") == "expense"
    assert detect_intent("thu 15tr lương ví: mbbank") == "income"
    assert detect_intent("chuyển 2tr ví: mbbank -> tiền mặt") == "transfer"


def test_parse_expense_with_synonym():
    result = parse_input("chi 45k cf ví: tiền mặt - họp khách")
    assert result.intent == "expense"
    assert result.amount_vnd == 45_000
    assert result.category == "Cà phê"
    assert result.wallet == "tiền mặt"
    assert result.note == "họp khách"
    assert result.ambiguous is False


def test_parse_transfer():
    result = parse_input("chuyển 1tr2 ví: mbbank -> tiền mặt - rút ATM")
    assert result.intent == "transfer"
    assert result.amount_vnd == 1_200_000
    assert result.wallet_from == "mbbank"
    assert result.wallet_to == "tiền mặt"
    assert result.note == "rút ATM"
    assert result.ambiguous is False


def test_parse_ambiguous_missing_wallet():
    result = parse_input("chi 30k ăn sáng")
    assert result.ambiguous is True
    assert any("Thiếu ví" in issue for issue in result.issues)
