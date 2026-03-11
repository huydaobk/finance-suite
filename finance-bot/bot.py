from __future__ import annotations

import logging
import os
from dataclasses import asdict
from datetime import date
from typing import Dict, List, Optional, Tuple

import requests
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import Application, CallbackQueryHandler, CommandHandler, ContextTypes, MessageHandler, filters

from input_parser import ParseResult, format_vnd, parse_input, preview_line


logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
FINANCE_API_URL = os.environ.get("FINANCE_API_URL", "http://127.0.0.1:8088")
INGEST_SHARED_SECRET = os.environ.get("INGEST_SHARED_SECRET", "")

SPEC_TEXT = """Format mới:
1) Siêu nhanh:
- c 50k cafe
- t 3tr luong
- cv 500k Ngân hàng -> Tiền Mặt

2) Chuẩn đầy đủ:
- c 50k an_uong / Tiền Mặt ; cafe
- t 3tr luong / Ngân hàng ; lương tháng 3
- cv 500k Ngân hàng -> Tiền Mặt ; rút ATM

Quy ước:
- c = chi, t = thu, cv = chuyển ví
- Nếu thiếu ví ở chi/thu => mặc định Tiền Mặt
- Note ưu tiên phần sau dấu ';'
- Nếu thiếu category và bot không đoán chắc => bot sẽ hỏi lại
"""

INLINE_CALLBACK_PREFIX = "txv1"
CATEGORY_CHOICES = ["Ăn uống", "Di chuyển", "Mua sắm", "Khác"]
WALLET_CHOICES = ["Tiền Mặt", "Momo", "Ngân hàng"]
ACTION_SAVE = "save"
ACTION_EDIT = "edit"
ACTION_CANCEL = "cancel"
ACTION_PICK_CATEGORY = "pick_category"
ACTION_PICK_WALLET = "pick_wallet"
ACTION_NOOP = "noop"

PENDING_DRAFTS: Dict[int, Dict] = {}


def build_inline_callback(action: str, value: str) -> str:
    return f"{INLINE_CALLBACK_PREFIX}|{action}|{value}"


def parse_inline_callback(data: str) -> Tuple[Optional[str], Optional[str]]:
    parts = (data or "").split("|", 2)
    if len(parts) != 3:
        return None, None
    version, action, value = parts
    if version != INLINE_CALLBACK_PREFIX or not action:
        return None, None
    return action, value


def _serialize_result(result: ParseResult) -> Dict:
    return asdict(result)


def _deserialize_result(data: Dict) -> ParseResult:
    return ParseResult(**data)


def set_pending_draft(chat_id: int, result: ParseResult) -> None:
    PENDING_DRAFTS[chat_id] = _serialize_result(result)


def get_pending_draft(chat_id: int) -> Optional[ParseResult]:
    data = PENDING_DRAFTS.get(chat_id)
    if not data:
        return None
    return _deserialize_result(data)


def clear_pending_draft(chat_id: int) -> None:
    PENDING_DRAFTS.pop(chat_id, None)


def _chat_id(update: Update) -> int:
    return update.effective_chat.id


def _recompute_resolution(result: ParseResult) -> ParseResult:
    issues: List[str] = []
    if result.intent == "transfer":
        if not result.wallet_from or not result.wallet_to:
            issues.append("Thiếu ví nguồn/đích cho giao dịch chuyển")
    else:
        if not result.category:
            issues.append("Thiếu danh mục rõ ràng")
        if not result.wallet:
            issues.append("Thiếu ví")

    result.issues = issues
    result.ambiguous = bool(issues)
    result.resolution = "ASK" if issues else "OK"
    result.normalized_text = preview_line(result)
    return result


def build_inline_payload(result: ParseResult) -> Dict:
    return {
        "version": INLINE_CALLBACK_PREFIX,
        "resolution": result.resolution,
        "preview": preview_line(result),
        "missing": result.issues,
        "keyboard": {
            "inline_keyboard": [
                [{"text": item, "callback_data": build_inline_callback(ACTION_PICK_CATEGORY, item)} for item in CATEGORY_CHOICES],
                [{"text": item, "callback_data": build_inline_callback(ACTION_PICK_WALLET, item)} for item in WALLET_CHOICES],
                [
                    {"text": "✅ Confirm", "callback_data": build_inline_callback(ACTION_SAVE, "1")},
                    {"text": "✏️ Edit", "callback_data": build_inline_callback(ACTION_EDIT, "1")},
                    {"text": "❌ Cancel", "callback_data": build_inline_callback(ACTION_CANCEL, "1")},
                ],
            ]
        },
    }


def _pending_keyboard(result: ParseResult) -> InlineKeyboardMarkup:
    rows: List[List[InlineKeyboardButton]] = [
        [InlineKeyboardButton(item, callback_data=build_inline_callback(ACTION_PICK_CATEGORY, item)) for item in CATEGORY_CHOICES],
        [InlineKeyboardButton(item, callback_data=build_inline_callback(ACTION_PICK_WALLET, item)) for item in WALLET_CHOICES],
        [
            InlineKeyboardButton("✅ Confirm", callback_data=build_inline_callback(ACTION_SAVE, "1")),
            InlineKeyboardButton("✏️ Edit", callback_data=build_inline_callback(ACTION_EDIT, "1")),
            InlineKeyboardButton("❌ Cancel", callback_data=build_inline_callback(ACTION_CANCEL, "1")),
        ],
    ]
    return InlineKeyboardMarkup(rows)


def _intent_label_and_icon(intent: str) -> Tuple[str, str]:
    if intent == "income":
        return "Thu", "🟢"
    if intent == "transfer":
        return "Chuyển", "🔄"
    return "Chi", "🔴"


def _truncate_raw_text(raw_text: str, limit: int = 60) -> str:
    text = " ".join((raw_text or "").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def build_preview_message(result: ParseResult) -> str:
    label, icon = _intent_label_and_icon(result.intent)
    lines = [f"{icon} {label} {format_vnd(result.amount_vnd)}"]

    category = result.category or "(chưa chọn)"
    lines.append(f"Category: {category}")

    if result.intent == "transfer":
        wallet_line = f"{result.wallet_from or '(chưa chọn)'} -> {result.wallet_to or '(chưa chọn)'}"
    else:
        wallet_line = result.wallet or "(chưa chọn)"
    lines.append(f"Ví: {wallet_line}")

    if result.note:
        lines.append(f"Note: {result.note}")

    raw_text = _truncate_raw_text(result.raw_text)
    if raw_text:
        lines.append(f"Raw: {raw_text}")

    if result.issues:
        lines.append("👉 Chỉ cần bấm nút bên dưới để chọn cho đủ rồi Confirm.")
    else:
        lines.append("👉 Bấm Confirm để lưu.")
    return "\n".join(lines)


def build_confirm_message(result: ParseResult, api_result: Dict) -> str:
    label, _ = _intent_label_and_icon(result.intent)
    summary = f"✅ Đã ghi: {label} {format_vnd(result.amount_vnd)}"
    details: List[str] = []
    if result.intent == "transfer":
        details.append(f"{result.wallet_from or '?'} -> {result.wallet_to or '?'}")
    else:
        if result.category:
            details.append(result.category)
        if result.wallet:
            details.append(result.wallet)
    if result.note:
        details.append(result.note)
    if details:
        summary += " — " + " • ".join(details)

    meta_id = api_result.get("id")
    if meta_id:
        return f"{summary}\nID: {meta_id}"
    if result.tx_date:
        return f"{summary}\nNgày: {result.tx_date}"
    return summary


def ingest_payload(payload: Dict) -> Dict:
    resp = requests.post(
        f"{FINANCE_API_URL}/ingest/transactions",
        headers={"X-Ingest-Secret": INGEST_SHARED_SECRET, "Content-Type": "application/json"},
        json=payload,
        timeout=15,
    )
    resp.raise_for_status()
    return resp.json()


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Gửi giao dịch theo format mới hoặc /format để xem mẫu.")


async def format_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(SPEC_TEXT)


async def cancel_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    clear_pending_draft(_chat_id(update))
    await update.message.reply_text("Đã hủy giao dịch chờ lưu.")


async def text_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = (update.message.text or "").strip()
    if not text:
        return

    result = _recompute_resolution(parse_input(text))
    chat_id = _chat_id(update)
    set_pending_draft(chat_id, result)
    inline_spec = build_inline_payload(result)

    await update.message.reply_text(
        build_preview_message(result),
        reply_markup=_pending_keyboard(result),
    )
    log.info("inline_payload_spec=%s", inline_spec)


async def callback_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    action, value = parse_inline_callback(query.data or "")
    if not action:
        await query.edit_message_text("Callback không hợp lệ.")
        return

    chat_id = query.message.chat_id
    result = get_pending_draft(chat_id)
    if not result:
        await query.edit_message_text("Không còn giao dịch chờ xác nhận.")
        return

    if action == ACTION_CANCEL:
        clear_pending_draft(chat_id)
        await query.edit_message_text("Đã hủy.")
        return

    if action == ACTION_EDIT:
        await query.edit_message_text("Hãy gửi lại tin nhắn theo format mới.\n\n" + SPEC_TEXT)
        return

    if action == ACTION_PICK_CATEGORY:
        result.category = value
        result = _recompute_resolution(result)
        set_pending_draft(chat_id, result)
        await query.edit_message_text(build_preview_message(result), reply_markup=_pending_keyboard(result))
        return

    if action == ACTION_PICK_WALLET:
        if result.intent == "transfer":
            result.wallet_from = result.wallet_from or value
            if result.wallet_from and result.wallet_from != value and not result.wallet_to:
                result.wallet_to = value
        else:
            result.wallet = value
        result = _recompute_resolution(result)
        set_pending_draft(chat_id, result)
        await query.edit_message_text(build_preview_message(result), reply_markup=_pending_keyboard(result))
        return

    if action == ACTION_SAVE:
        result = _recompute_resolution(result)
        if result.ambiguous:
            set_pending_draft(chat_id, result)
            await query.edit_message_text(build_preview_message(result), reply_markup=_pending_keyboard(result))
            return
        payload = result.to_payload()
        if not payload.get("tx_date"):
            payload["tx_date"] = date.today().isoformat()
        api_result = ingest_payload(payload)
        clear_pending_draft(chat_id)
        await query.edit_message_text(build_confirm_message(result, api_result))
        return

    await query.edit_message_text("Hành động chưa hỗ trợ.")


def main():
    if not BOT_TOKEN:
        raise RuntimeError("BOT_TOKEN is required")
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("format", format_cmd))
    app.add_handler(CommandHandler("cancel", cancel_cmd))
    app.add_handler(CallbackQueryHandler(callback_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling(close_loop=False)


if __name__ == "__main__":
    main()
