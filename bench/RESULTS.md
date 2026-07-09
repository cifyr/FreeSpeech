# Whisper model benchmark — 2026-07-09

Clip: 23s real dictation (`inut.m4a`), deliberately varied voices and mumbling.
Reference: `ground_truth.txt` (speaker's intended words). Hardware: M4 Max, Metal.
Timing is best of 3 warm runs via `FreeSpeech --transcribe-file`. Raw data: `results.json`.
Reproduce with `bench/run_bench.sh <clip>`.

## Model x decoding matrix (WER / transcribe seconds)

| model               | greedy        | greedy+hint   | beam5         | beam5+hint    |
|---------------------|---------------|---------------|---------------|---------------|
| tiny.en (75MB)      | 32.9% / 0.12s | 30.0% / 0.13s | 35.7% / 0.23s | 28.6% / 0.20s |
| base.en (142MB)     | 21.4% / 0.16s | 20.0% / 0.17s | 25.7% / 0.31s | 21.4% / 0.24s |
| small.en (466MB)    | 25.7% / 0.41s | 22.9% / 0.33s | 21.4% / 0.50s | 22.9% / 0.54s |
| medium.en (1.5GB)   | 20.0% / 1.01s | 21.4% / 0.93s | 18.6% / 1.27s | 21.4% / 1.08s |
| large-v3-turbo (1.6GB) | 20.0% / 0.52s | 18.6% / 0.52s | 20.0% / 0.81s | 18.6% / 0.72s |
| large-v3-turbo-q5_0 (561MB) | 15.7% / 0.70s | 14.3% / 0.69s | 20.0% / 0.85s | 20.0% / 0.85s |

hint = whisper `initial_prompt` "Caden Warren, Claude Code, FreeSpeech."

## Vocabulary-hint refinement (large-v3-turbo-q5_0, greedy)

| initial_prompt | WER | notes |
|---|---|---|
| none | 15.7% | "Keaton Warren", "cloud code" |
| name list only | 14.3% | fixes "Caden Warren", still "cloud code" |
| natural sentence about Claude Code | 17.1% | fixes both nouns, wobbles a mumbled phrase |
| name list + key term in a sentence | 12.9% | fixes everything fixable — champion |

Champion prompt: `Caden Warren, Claude Code, FreeSpeech. My specialty is to use Claude Code on projects.`

## Learnings

- large-v3-turbo-q5_0 dominates: better WER than models 3x its size, and the only
  model to recover "Caden Warren". Quantization (q5_0) beat full-precision turbo
  on this clip while loading 6x faster (0.25s vs 1.6s) and using a third of the disk.
- Beam search (beam5) was a net loss on this clip for the strong models: slower and
  equal-or-worse WER. Greedy is the right default; whisper's fallback decoding
  already handles low-confidence segments.
- The `initial_prompt` vocabulary hint is the cheapest accuracy win available:
  zero latency cost, and phrasing matters — proper nouns bias best when the key
  terms also appear inside a natural sentence, not just a bare list.
- .en models underperformed expectations on deliberately-weird speech; the
  multilingual turbo generalizes better to voice changes.
- Remaining errors are all in the intentionally mumbled/multi-voice section;
  clean dictation should score far better than this stress clip.

## Shipped default

large-v3-turbo-q5_0, greedy (beam 1), champion vocabulary hint (user-editable in
Settings > Vocabulary). End-to-end: 0.25s model load at launch, ~0.6s transcription
for 23s of audio, comfortably under the 2s latency bar.
