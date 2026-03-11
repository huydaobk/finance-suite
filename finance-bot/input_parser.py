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

DEFAULT_WALLET = "Tiền Mặt"
CANONICAL_WALLETS = {
    "tien mat": "Tiền Mặt",
    "tienmat": "Tiền Mặt",
    "cash": "Tiền Mặt",
    "tm": "Tiền Mặt",
    "momo": "Momo",
    "ngan hang": "Ngân hàng",
    "nganhang": "Ngân hàng",
    "bank": "Ngân hàng",
    "mbbank": "Ngân hàng",
    "vcb": "Ngân hàng",
    "vietcombank": "Ngân hàng",
    "acb": "Ngân hàng",
    "tpbank": "Ngân hàng",
    "bidv": "Ngân hàng",
    "techcombank": "Ngân hàng",
}

QUICK_INTENT_MAP = {
    "c": "expense",
    "chi": "expense",
    "t": "income",
    "thu": "income",
    "cv": "transfer",
    "chuyen": "transfer",
    "chuyển": "transfer",
}

TRANSFER_ARROW_RE = re.compile(r"\s*(?:->|→|=>|to)\s*", re.IGNORECASE)
INLINE_AMOUNT_RE = re.compile(r"(?i)\b\d[\d\.,]*(?:tr\d+|tr|k)?\b")
FULL_PATTERN = re.compile(
    r"^(?P<head>c|chi|t|thu|cv|chuyen|chuyển)\s+"
    r"(?P<amount>\S+)"
    r"(?:\s+(?P<tail>.*))?$",
    re.IGNORECASE,
)
INTENT_KEYWORDS = {
    "expense": ["chi", "mua", "ăn", "uong", "uống", "trả", "tra"],
    "income": ["thu", "nhận", "nhan", "lương", "luong", "thưởng", "thuong"],
    "transfer": ["chuyển", "chuyen", "ck", "transfer"],
}


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
    resolution: str = "OK"
    suggested_categories: List[str] = field(default_factory=list)

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
    text = text.replace("đ", "d").replace("Đ", "D")
    text = text.lower().strip()
    text = text.replace("_", " ")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


class CategoryMapper:
    def __init__(self, config_path: Path = CATEGORY_FILE):
        with open(config_path, "r", encoding="utf-8") as f:
            self.data = json.load(f)
        self.lookup: Dict[str, str] = {}
        self.keyword_lookup: Dict[str, str] = {}
        for canonical, synonyms in self.data.items():
            all_forms = [canonical, *synonyms]
            for form in all_forms:
                key = slugify(form)
                self.lookup[key] = canonical
                self.keyword_lookup[key] = canonical

    def map(self, text: Optional[str]) -> Optional[str]:
        if not text:
            return None
        return self.lookup.get(slugify(text))

    def infer(self, text: Optional[str]) -> tuple[Optional[str], bool, List[str]]:
        if not text:
            return None, False, []
        normalized = slugify(text)
        if not normalized:
            return None, False, []
        direct = self.lookup.get(normalized)
        if direct:
            return direct, True, [direct]

        hits: List[str] = []
        padded = f" {normalized} "
        for keyword, canonical in self.keyword_lookup.items():
            if f" {keyword} " in padded:
                hits.append(canonical)

        ordered_hits: List[str] = []
        seen = set()
        for item in hits:
            if item not in seen:
                seen.add(item)
                ordered_hits.append(item)

        if len(ordered_hits) == 1:
            return ordered_hits[0], True, ordered_hits
        return None, False, ordered_hits[:4]


category_mapper = CategoryMapper()


def normalize_wallet(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    key = slugify(raw)
    return CANONICAL_WALLETS.get(key)


def normalize_amount(raw: str) -> int:
    s = raw.strip().lower().replace(" ", "").replace("_", "")
    s = s.replace("đ", "d")
    if not s:
        raise ValueError("empty amount")

    if "tr" not in s and re.fullmatch(r"\d{1,3}(?:[\.,]\d{3})+", s):
        return int(re.sub(r"[\.,]", "", s))

    if "tr" in s:
        left, right = s.split("tr", 1)
        if not left or not re.fullmatch(r"\d+(?:[\.,]\d+)?", left):
            raise ValueError(f"invalid tr amount: {raw}")
        if "." in left and "," not in left:
            left_value = float(left)
        elif "," in left and "." not in left:
            left_value = float(left.replace(",", "."))
        else:
            left_value = float(left.replace(",", "."))
        base = left_value * 1_000_000
        extra = 0
        if right:
            if right.endswith("k"):
                extra = int(float(right[:-1].replace(",", ".")) * 1_000)
            elif right.isdigit():
                extra = int(right) * (1_000_000 // (10 ** len(right)))
            else:
                raise ValueError(f"invalid tr suffix: {raw}")
        return int(round(base + extra))

    match = re.fullmatch(r"(\d+(?:[\.,]\d+)?)(k)?", s)
    if not match:
        raise ValueError(f"invalid amount: {raw}")
    number, unit = match.groups()
    value = float(number.replace(",", "."))
    if unit == "k":
        return int(round(value * 1_000))
    if "." in number or "," in number:
        return int(round(value * 1_000_000))
    return int(round(value))


def detect_intent(text: str) -> str:
    raw = text.strip()
    m = FULL_PATTERN.match(raw)
    if m:
        head = slugify(m.group("head"))
        if head in QUICK_INTENT_MAP:
            return QUICK_INTENT_MAP[head]

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


def split_main_and_note(text: str) -> tuple[str, Optional[str]]:
    for sep in [";", "|", " - "]:
        if sep in text:
            left, right = text.split(sep, 1)
            return left.strip(), (right.strip() or None)
    return text.strip(), None


def extract_amount_token(text: str) -> tuple[Optional[int], str]:
    match = INLINE_AMOUNT_RE.search(text)
    if not match:
        return None, text.strip()
    amount = normalize_amount(match.group(0))
    remain = (text[:match.start()] + " " + text[match.end():]).strip()
    remain = re.sub(r"\s+", " ", remain)
    return amount, remain


def parse_wallets(intent: str, tail: str) -> tuple[Optional[str], Optional[str], str]:
    cleaned = tail.strip()
    if intent == "transfer":
        parts = TRANSFER_ARROW_RE.split(cleaned, maxsplit=1)
        if len(parts) == 2:
            left = parts[0].strip(" /")
            right = parts[1].strip(" /")
            return normalize_wallet(left), normalize_wallet(right), ""
        return None, None, cleaned

    if not cleaned:
        return DEFAULT_WALLET, None, ""

    parts = [part.strip() for part in cleaned.split("/", 1)]
    if len(parts) == 2:
        left, wallet_raw = parts
        wallet = normalize_wallet(wallet_raw)
        return wallet or DEFAULT_WALLET, None, left
    return DEFAULT_WALLET, None, cleaned


def parse_category_and_note(intent: str, tail: str) -> tuple[Optional[str], Optional[str], List[str], str]:
    if intent == "transfer":
        return None, None, [], "OK"
    inferred, certain, suggestions = category_mapper.infer(tail)
    if certain:
        note = None
        normalized_tail = slugify(tail)
        category_forms = {slugify(inferred)}
        for synonym in category_mapper.data.get(inferred, []):
            category_forms.add(slugify(synonym))
        if normalized_tail not in category_forms:
            note = tail.strip() or None
        return inferred, note, suggestions, "OK"
    return None, tail.strip() or None, suggestions, "ASK"


def parse_input(text: str) -> ParseResult:
    raw = text.strip()
    if not raw:
        result = ParseResult(intent="expense", raw_text=text, ambiguous=True)
        result.issues.append("Tin nhắn rỗng")
        result.resolution = "ASK"
        result.normalized_text = preview_line(result)
        return result

    match = FULL_PATTERN.match(raw)
    if match:
        head = slugify(match.group("head"))
        intent = QUICK_INTENT_MAP.get(head, detect_intent(raw))
        amount_raw = match.group("amount")
        tail = (match.group("tail") or "").strip()
    else:
        intent = detect_intent(raw)
        amount_raw = None
        tail = raw

    issues: List[str] = []
    suggestions: List[str] = []
    note: Optional[str] = None

    main_part, note_part = split_main_and_note(tail)

    amount_vnd: Optional[int] = None
    if amount_raw:
        try:
            amount_vnd = normalize_amount(amount_raw)
        except ValueError:
            issues.append("Không nhận diện được số tiền")
    else:
        try:
            amount_vnd, main_part = extract_amount_token(main_part)
        except ValueError:
            issues.append("Không nhận diện được số tiền")
    if amount_vnd is None and "Không nhận diện được số tiền" not in issues:
        issues.append("Không nhận diện được số tiền")

    wallet = None
    wallet_from = None
    wallet_to = None
    if intent == "transfer":
        wallet_from, wallet_to, remain = parse_wallets(intent, main_part)
        if not wallet_from or not wallet_to:
            issues.append("Thiếu ví nguồn/đích cho giao dịch chuyển")
        if note_part:
            note = note_part
    else:
        wallet, _, remain = parse_wallets(intent, main_part)
        category, remain_note, suggestions, resolution = parse_category_and_note(intent, remain)
        if note_part:
            note = note_part
        else:
            note = remain_note
        if not category:
            issues.append("Thiếu danh mục rõ ràng")
        if wallet is None:
            wallet = DEFAULT_WALLET
    
    category = None
    resolution = "OK"
    if intent != "transfer":
        category, remain_note, suggestions, resolution = parse_category_and_note(intent, remain)
        if note_part:
            note = note_part
        elif remain_note:
            note = remain_note
        if not category:
            issues.append("Thiếu danh mục rõ ràng")
            resolution = "ASK"
    else:
        resolution = "ASK" if issues else "OK"

    if note:
        note = note.strip() or None

    result = ParseResult(
        intent=intent,
        amount_vnd=amount_vnd,
        category=category,
        wallet=wallet,
        wallet_from=wallet_from,
        wallet_to=wallet_to,
        note=note,
        raw_text=raw,
        ambiguous=bool(issues),
        issues=issues,
        resolution=resolution if not issues or resolution == "ASK" else "ASK",
        suggested_categories=suggestions,
    )
    result.normalized_text = preview_line(result)
    return result


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
