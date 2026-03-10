#!/usr/bin/env python3
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from input_parser import parse_input, preview_line

SAMPLES = [
    "chi 45k cf ví: tiền mặt - họp khách",
    "thu 15tr lương ví: mbbank - lương tháng 3",
    "chuyển 2tr ví: mbbank -> tiền mặt - rút ATM",
    "chi 30k ăn sáng",
]

for text in SAMPLES:
    result = parse_input(text)
    print("=" * 60)
    print("RAW:", text)
    print("PREVIEW:", preview_line(result))
    print("AMBIGUOUS:", result.ambiguous)
    print("ISSUES:", result.issues)
    print("PAYLOAD:", result.to_payload())
