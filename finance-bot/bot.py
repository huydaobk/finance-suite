from __future__ import annotations

import json
import logging
import os
from dataclasses import asdict
from datetime import date
from typing import Dict

import requests
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import Application, CallbackQueryHandler, CommandHandler, ContextTypes, MessageHandler, filters

from input_parser import ParseResult, parse_input, preview_line


logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
FINANCE_API_URL = os.environ.get("FINANCE_API_URL", "http://127.0.0.1:8088")
INGEST_SHARED_SECRET = os.environ.get("INGEST_SHARED_SECRET", "")
PENDING_CONFIRMATIONS: Dict[str, Dict] = {}

SPEC_TEXT = """Format chuẩn:
1) Chi: chi 45k ăn uống ví: tiền mặt - bánh mì
2) Thu: thu 15tr lương ví: mbbank - lương tháng 3
3) Chuyển: chuyển 2tr ví: mbbank -> tiền mặt - rút tiền
4) Số tiền hỗ trợ: 85k, 1tr2, 1.2tr, 1,200,000
5) Ví ghi sau 'ví:'; chuyển thì dùng 'ví: nguồn -> đích'
6) Note ghi sau dấu '-' hoặc '|'
"""


def _chat_key(update: Update) -> str:
    chat_id = update.effective_chat.id
    user_id = update.effective_user.id if update.effective_user else 0
    return f"{chat_id}:{user_id}"


def _pending_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ Lưu", callback_data="save")],
        [InlineKeyboardButton("✏️ Sửa", callback_data="edit")],
        [InlineKeyboardButton("❌ Hủy", callback_data="cancel")],
    ])


def _serialize_result(result: ParseResult) -> Dict:
    return asdict(result)


def _deserialize_result(data: Dict) -> ParseResult:
    return ParseResult(**data)


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
    await update.message.reply_text("Gửi giao dịch theo format chuẩn hoặc /format để xem mẫu.")


async def format_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(SPEC_TEXT)


async def cancel_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    PENDING_CONFIRMATIONS.pop(_chat_key(update), None)
    await update.message.reply_text("Đã hủy giao dịch chờ lưu.")


async def text_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = (update.message.text or "").strip()
    if not text:
        return

    result = parse_input(text)
    key = _chat_key(update)
    PENDING_CONFIRMATIONS[key] = _serialize_result(result)

    if result.ambiguous:
        issue_text = "\n".join(f"- {item}" for item in result.issues)
        await update.message.reply_text(
            f"Em parse tạm như này:\n{preview_line(result)}\n\nCần bổ sung:\n{issue_text}\n\nSửa tin nhắn theo format chuẩn hoặc bấm Hủy.",
            reply_markup=_pending_keyboard(),
        )
        return

    await update.message.reply_text(
        f"Preview: {preview_line(result)}\nXác nhận trước khi lưu nhé.",
        reply_markup=_pending_keyboard(),
    )


async def callback_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    key = f"{query.message.chat_id}:{query.from_user.id}"
    pending = PENDING_CONFIRMATIONS.get(key)
    if not pending:
        await query.edit_message_text("Không còn giao dịch chờ xác nhận.")
        return

    action = query.data
    result = _deserialize_result(pending)

    if action == "cancel":
        PENDING_CONFIRMATIONS.pop(key, None)
        await query.edit_message_text("Đã hủy.")
        return

    if action == "edit":
        await query.edit_message_text(
            "Hãy gửi lại tin nhắn theo format chuẩn.\n\n" + SPEC_TEXT
        )
        return

    if action == "save":
        if result.ambiguous:
            await query.edit_message_text(
                "Giao dịch còn thiếu dữ liệu nên chưa lưu được. Hãy sửa rồi gửi lại."
            )
            return
        payload = result.to_payload()
        if not payload.get("tx_date"):
            payload["tx_date"] = date.today().isoformat()
        api_result = ingest_payload(payload)
        PENDING_CONFIRMATIONS.pop(key, None)
        await query.edit_message_text(
            f"Đã lưu: {preview_line(result)}\nID inbox: {api_result.get('id')}"
        )


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
