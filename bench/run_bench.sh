#!/bin/bash
# Benchmarks every installed whisper model x decoding strategy against a clip
# with a known transcript. Usage: bench/run_bench.sh <audio-file> [out.json]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIO="${1:?usage: run_bench.sh <audio-file> [out.json]}"
OUT="${2:-$ROOT/bench/results.json}"
BIN="$ROOT/.build/release/FreeSpeech"
TRUTH="$ROOT/bench/ground_truth.txt"
MODELS_DIR="$HOME/Library/Application Support/FreeSpeech/models"

[ -x "$BIN" ] || { echo "error: $BIN missing — run ./build.sh first" >&2; exit 1; }

VOCAB="Caden Warren, Claude Code, FreeSpeech."

echo "[" > "$OUT.tmp"
first=1
for f in "$MODELS_DIR"/ggml-*.bin; do
    model="$(basename "$f" .bin)"; model="${model#ggml-}"
    for beam in 1 5; do
    for hint in none vocab; do
        prompt_args=()
        [ "$hint" = "vocab" ] && prompt_args=(--prompt "$VOCAB")
        echo "==> $model beam=$beam hint=$hint" >&2
        if ! out="$("$BIN" --transcribe-file "$AUDIO" --model "$model" --beam-size "$beam" --runs 3 ${prompt_args[@]+"${prompt_args[@]}"} 2>/dev/null)"; then
            echo "    failed, skipping" >&2
            continue
        fi
        load_s="$(echo "$out" | awk -F': ' '/^model_load_s/{print $2}')"
        t_s="$(echo "$out" | awk -F': ' '/^transcribe_s/{print $2}')"
        audio_s="$(echo "$out" | awk -F': ' '/^audio_s/{print $2}')"
        transcript="$(echo "$out" | sed -n 's/^transcript: //p')"
        w="$(python3 "$ROOT/bench/wer.py" "$TRUTH" "$transcript")"
        size_mb="$(du -m "$f" | cut -f1)"
        [ "$first" -eq 1 ] || echo "," >> "$OUT.tmp"
        first=0
        python3 - "$model" "$beam" "$hint" "$load_s" "$t_s" "$audio_s" "$w" "$size_mb" "$transcript" >> "$OUT.tmp" <<'PY'
import json, sys
m, b, h, l, t, a, w, s, tr = sys.argv[1:10]
print(json.dumps({
    "model": m, "beam_size": int(b), "vocab_hint": h == "vocab",
    "model_load_s": float(l), "transcribe_s": float(t), "audio_s": float(a),
    "wer": float(w), "size_mb": int(s), "transcript": tr,
}, indent=2), end="")
PY
        echo "    wer=$w transcribe_s=$t_s" >&2
    done
    done
done
echo >> "$OUT.tmp"
echo "]" >> "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "results written to $OUT" >&2
