from bot import (
    ACTION_PICK_CATEGORY,
    ACTION_PICK_WALLET,
    ACTION_SAVE,
    build_inline_callback,
    clear_pending_draft,
    get_pending_draft,
    parse_inline_callback,
    set_pending_draft,
)
from input_parser import parse_input


def test_parse_inline_callback_valid():
    action, value = parse_inline_callback("txv1|pick_category|Ăn uống")
    assert action == "pick_category"
    assert value == "Ăn uống"


def test_parse_inline_callback_invalid_prefix():
    action, value = parse_inline_callback("bad|save|1")
    assert action is None
    assert value is None


def test_build_inline_callback_roundtrip():
    data = build_inline_callback(ACTION_PICK_WALLET, "Momo")
    assert data == "txv1|pick_wallet|Momo"
    assert parse_inline_callback(data) == (ACTION_PICK_WALLET, "Momo")


def test_pending_state_one_per_chat_replaces_old_value():
    first = parse_input("c 50k cafe")
    second = parse_input("c 70k grab")

    set_pending_draft(123, first)
    set_pending_draft(123, second)

    loaded = get_pending_draft(123)
    assert loaded is not None
    assert loaded.amount_vnd == 70_000
    assert loaded.category == "Di chuyển"


def test_pending_state_isolated_per_chat():
    draft1 = parse_input("c 50k cafe")
    draft2 = parse_input("c 200k mua_sắm / momo ; shopee")

    set_pending_draft(1, draft1)
    set_pending_draft(2, draft2)

    assert get_pending_draft(1).category == "Cà phê"
    assert get_pending_draft(2).wallet == "Momo"


def test_clear_pending_state():
    set_pending_draft(999, parse_input("c 50k cafe"))
    clear_pending_draft(999)
    assert get_pending_draft(999) is None


def test_quick_input_missing_category_can_be_completed_in_state():
    draft = parse_input("c 50k abcxyz")
    assert draft.resolution == "ASK"

    draft.category = "Khác"
    draft.wallet = "Ngân hàng"
    draft.issues = []
    draft.ambiguous = False
    draft.resolution = "OK"

    set_pending_draft(321, draft)
    loaded = get_pending_draft(321)
    assert loaded is not None
    assert loaded.category == "Khác"
    assert loaded.wallet == "Ngân hàng"
    assert loaded.resolution == "OK"


def test_save_callback_format_stable():
    assert build_inline_callback(ACTION_SAVE, "1") == "txv1|save|1"
    assert parse_inline_callback("txv1|save|1") == (ACTION_SAVE, "1")
