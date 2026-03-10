from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any, Dict, List, Optional


BASE_DIR = Path(__file__).resolve().parent
CATEGORY_FILE = BASE_DIR / "config" / "category_synonyms.json"


AMOUNT_TOKEN_RE = re.compile(r"^\s*([0-9][0-9\.,]*)(?:\s*(k|tr))?\s*$", re.IGNORECASE)
INLINE_AMOUNT_RE = re.compile(r"(?i)(\d[\d\.,]*\s*(?:tr\d+)?\s*(?:[kK]|tr)?)")


INTENT_KEYWORDS = {
    "expense": ["chi", "mua", "ăn", "uong", "uống", "trả", "tra"],
    "income": ["thu", "nhận", "nhan", "lương", "luong", "thưởng", "thuong"],
    "transfer": ["chuyển", "chuyen", "ck", "transfer"],
}

TRANSFER_ARROW_RE = re.compile(r"\s*(?:->|→|=>|to)\s*", re.IGNORECASE)
WALLET_SPLIT_RE = re.compile(r"\s*(?:->|→|=>|>)\s*")


@dataclass
class ParseResult:
    intent: str
    amount_vnd: Optional[int] = None
    category: Optional[str] = None
    wallet: Optional[str] = None
    wallet_from: Optional[str] = None
    wallet_to: Optional[str] = None
    note: Optional[str] = None
    tx_date: str = field(default_factory=lambda: date.today().isoformat())
    raw_text: str = ""
    ambiguous: bool = False
    issues: List[str] = field(default_factory=list)
    normalized_text: str = ""

    def to_payload(self) -> Dict[str, Any]:
        wallet = self.wallet
        if self.intent == "transfer" and self.wallet_from and self.wallet_to:
            wallet = f"{self.wallet_from} -> {self.wallet_to}"
        return {
            "type": self.intent,
            "amount_vnd": self.amount_vnd,
            "category": self.category,
            "wallet": wallet,
            "note": self.note,
            "tx_date": self.tx_date,
            "raw_text": self.raw_text,
        }


def slugify(text: str) -> str:
    text = unicodedata.normalize("NFD", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


class CategoryMapper:
    def __init__(self, config_path: Path = CATEGORY_FILE):
        with open(config_path, "r", encoding="utf-8") as f:
            self.data = json.load(f)
        self.lookup: Dict[str, str] = {}
        for canonical, synonyms in self.data.items():
            self.lookup[slugify(canonical)] = canonical
            for synonym in synonyms:
                self.lookup[slugify(synonym)] = canonical

    def map(self, text: Optional[str]) -> Optional[str]:
        if not text:
            return None
        return self.lookup.get(slugify(text), text.strip().title())


category_mapper = CategoryMapper()


def normalize_amount(raw: str) -> int:
    s = raw.strip().lower().replace(" ", "")
    if not s:
        raise ValueError("empty amount")

    s = s.replace("_", "")
    if re.fullmatch(r"\d{1,3}(?:[\.,]\d{3})+", s):
        return int(re.sub(r"[\.,]", "", s))

    if "tr" in s:
        left, right = s.split("tr", 1)
        if not left or not re.fullmatch(r"\d+(?:[\.,]\d+)?", left):
            raise ValueError(f"invalid tr amount: {raw}")
        left_is_decimal = "." in left or "," in left
        base = float(left.replace(",", ".")) * 1_000_000
        extra = 0
        if right:
            if right.endswith("k"):
                extra = int(float(right[:-1].replace(",", ".")) * 1_000)
            elif right.isdigit():
                if left_is_decimal:
                    raise ValueError(f"invalid mixed tr suffix: {raw}")
                extra = int(right) * (1_000_000 // (10 ** len(right)))
            else:
                raise ValueError(f"invalid tr suffix: {raw}")
        return int(round(base + extra))

    m = AMOUNT_TOKEN_RE.match(s)
    if not m:
        raise ValueError(f"invalid amount: {raw}")
    number, unit = m.groups()
    number = number.replace(",", ".")
    value = float(number)
    if unit == "k":
        return int(round(value * 1_000))
    if unit == "tr":
        return int(round(value * 1_000_000))
    return int(round(value))


def detect_intent(text: str) -> str:
    s = slugify(text)
    scores = {key: 0 for key in INTENT_KEYWORDS}
    words = set(s.split())
    for intent, keywords in INTENT_KEYWORDS.items():
        for kw in keywords:
            kw_slug = slugify(kw)
            if kw_slug in words:
                scores[intent] += 1
    if TRANSFER_ARROW_RE.search(text):
        scores["transfer"] += 2
    if s.startswith("thu ") or s == "thu":
        scores["income"] += 3
    if s.startswith("chi ") or s == "chi":
        scores["expense"] += 3
    if s.startswith("chuyen ") or s.startswith("ck ") or s == "chuyen" or s == "ck":
        scores["transfer"] += 3
    best = max(scores, key=scores.get)
    if scores[best] == 0:
        return "expense"
    return best


def extract_amount(text: str) -> Optional[int]:
    m = INLINE_AMOUNT_RE.search(text)
    if not m:
        return None
    token = re.sub(r"\s+", "", m.group(1))
    return normalize_amount(token)


def split_note(text: str) -> tuple[str, Optional[str]]:
    for sep in [" note ", " ghi chú ", " - ", " | "]:
        idx = text.lower().find(sep)
        if idx >= 0:
            left = text[:idx].strip()
            note = text[idx + len(sep):].strip(" :-|")
            return left, note or None
    return text.strip(), None


def parse_wallet_segment(text: str) -> tuple[Optional[str], Optional[str], Optional[str]]:
    m = re.search(r"(?i)\b(?:vi|ví)\s*[:=]\s*(.+)$", text)
    if not m:
        return None, None, text
    wallet_part = m.group(1).strip()
    remain = text[:m.start()].strip()
    parts = WALLET_SPLIT_RE.split(wallet_part)
    if len(parts) >= 2:
        return parts[0].strip(), parts[1].strip(), remain
    return wallet_part.strip(), None, remain


def parse_input(text: str) -> ParseResult:
    raw = text.strip()
    base_text, note = split_note(raw)
    wallet_from, wallet_to, remain = parse_wallet_segment(base_text)
    intent = detect_intent(remain)
    amount = extract_amount(remain)
    issues: List[str] = []

    head_removed = re.sub(r"(?i)^\s*(chi|thu|chuyen|chuyển|ck)\b\s*", "", remain).strip()
    amount_removed = INLINE_AMOUNT_RE.sub("", head_removed, count=1).strip(" ,;:")

    category = None
    if intent != "transfer" and amount_removed:
        tokens = [t for t in re.split(r"[,/]+", amount_removed) if t.strip()]
        if tokens:
            category = category_mapper.map(tokens[0].strip())
            if len(tokens) > 1 and not note:
                note = ", ".join(t.strip() for t in tokens[1:] if t.strip()) or note

    if intent == "transfer":
        if wallet_to is None and amount_removed:
            arrow_parts = TRANSFER_ARROW_RE.split(amount_removed, maxsplit=1)
            if len(arrow_parts) == 2:
                wallet_from = wallet_from or arrow_parts[0].strip()
                wallet_to = wallet_to or arrow_parts[1].strip()
        if not wallet_from or not wallet_to:
            issues.append("Thiếu ví nguồn/đích cho giao dịch chuyển")

    if amount is None:
        issues.append("Không nhận diện được số tiền")
    if intent != "transfer" and not category:
        issues.append("Thiếu danh mục")
    if intent != "transfer" and not wallet_from:
        issues.append("Thiếu ví")

    normalized_text = preview_line(ParseResult(
        intent=intent,
        amount_vnd=amount,
        category=category,
        wallet=wallet_from,
        wallet_from=wallet_from,
        wallet_to=wallet_to,
        note=note,
        raw_text=raw,
        issues=issues.copy(),
    ))

    return ParseResult(
        intent=intent,
        amount_vnd=amount,
        category=category,
        wallet=wallet_from,
        wallet_from=wallet_from,
        wallet_to=wallet_to,
        note=note,
        raw_text=raw,
        ambiguous=bool(issues),
        issues=issues,
        normalized_text=normalized_text,
    )


def format_vnd(amount: Optional[int]) -> str:
    if amount is None:
        return "?"
    return f"{amount:,}".replace(",", ".") + "đ"


def preview_line(result: ParseResult) -> str:
    if result.intent == "transfer":
        route = f"{result.wallet_from or '?'} → {result.wallet_to or '?'}"
        note = f" | note: {result.note}" if result.note else ""
        return f"Chuyển {format_vnd(result.amount_vnd)} | {route}{note}"
    label = "Chi" if result.intent == "expense" else "Thu"
    note = f" | note: {result.note}" if result.note else ""
    return f"{label} {format_vnd(result.amount_vnd)} | {result.category or '?'} | ví: {result.wallet or '?'}{note}"
