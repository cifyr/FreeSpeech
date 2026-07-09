#!/usr/bin/env python3
"""Word error rate between a reference file and a hypothesis string."""
import re
import sys

DIGITS = {
    "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
    "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
    "10": "ten",
}


def normalize(text: str) -> list[str]:
    text = text.lower()
    # Apostrophes vanish so "it's" == "its"; everything else non-alnum splits words.
    text = text.replace("'", "")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return [DIGITS.get(tok, tok) for tok in text.split()]


def wer(ref: list[str], hyp: list[str]) -> float:
    d = [[0] * (len(hyp) + 1) for _ in range(len(ref) + 1)]
    for i in range(len(ref) + 1):
        d[i][0] = i
    for j in range(len(hyp) + 1):
        d[0][j] = j
    for i in range(1, len(ref) + 1):
        for j in range(1, len(hyp) + 1):
            cost = 0 if ref[i - 1] == hyp[j - 1] else 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
    return d[len(ref)][len(hyp)] / max(1, len(ref))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: wer.py <reference-file> [hypothesis...]", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1]) as f:
        reference = normalize(f.read())
    hypothesis = normalize(" ".join(sys.argv[2:]) if len(sys.argv) > 2 else sys.stdin.read())
    print(f"{wer(reference, hypothesis):.4f}")
