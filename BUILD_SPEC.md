# /goal

Build **FreeSpeech**, a local, reliable macOS dictation app that clones the core of superwhisper: press a global hotkey, speak, and have your words transcribed **100% on-device** and inserted at the cursor in whatever app is focused. When done, a user on Apple Silicon can install the app, grant mic + accessibility permissions once, and dictate into any text field (Notes, browser, Slack, terminal, Cursor) with sub-2-second latency after they stop speaking, fully offline. The bar is **reliability over features**: the hotkey always fires, transcription never hangs, text always lands in the right place, and nothing leaves the machine. Output lives on branch `feat/freespeech-mvp` in this repo (`/Users/caden/ClaudeCode/idk/FreeSpeech`), builds with one documented command, passes the verification steps below, and is committed with an explicit file list for the user to run and dictate with. Motivation: the real superwhisper is sometimes flaky and cloud-dependent — the entire point here is **local + dependable**, so whenever a choice is unspecified, pick the simpler, more robust option over the flashier one.

## Definition of done

- [ ] Global hotkey starts/stops (or push-to-talk holds) recording from any app, reliably, even when FreeSpeech is not focused
- [ ] Audio is captured from the default input device and transcribed **entirely on-device** — zero network calls at runtime (verifiable with the network check below)
- [ ] Transcribed text is inserted at the cursor in the frontmost app and works in at least: Notes, a browser text field, Slack, and a terminal
- [ ] A floating **recording popup/HUD** appears on activation (like the original): shows a live waveform/level while recording and a "transcribing" state after, then dismisses itself — floats above all apps, never steals focus from the field being dictated into
- [ ] Menu bar item shows current state (idle / recording / transcribing) and exposes quit + model/hotkey settings
- [ ] End-to-end latency from stop-speaking to text-inserted is < 2s for a ~10s utterance on Apple Silicon with the default model
- [ ] First-run flow requests Microphone and Accessibility permissions with clear prompts; app degrades gracefully (visible error, no crash) if denied
- [ ] Whisper model file is downloaded/bundled once and loaded locally; app works with Wi-Fi off after setup
- [ ] Builds from a clean checkout with one documented command; README-free per house style, but a short "Run it" section in the spec/commit body explains launch
- [ ] Errors are surfaced (menu bar state + log) with actionable detail, never swallowed silently
- [ ] Committed on `feat/freespeech-mvp` with an explicit file list; **NOT** merged to main

## Hard constraints / do not

- **Local only.** No cloud STT, no telemetry, no analytics, no external API calls at runtime. Model download at setup time is the only permitted network access, and it must be gated/one-time.
- **Do not merge to main.** Commit once at the end on `feat/freespeech-mvp` with a specific file list.
- **Reliability beats features.** Do not add optional bells (AI reformatting, custom vocab, multi-language UI, cloud sync) until the core loop is rock-solid. Nail hotkey → record → transcribe → insert first.
- **No emojis** anywhere (output, code, commits, comments). Comments explain *why*, not *what*; keep them minimal.
- **Don't corrupt the user's clipboard.** If insertion uses clipboard+paste, save and restore the prior clipboard contents.
- **Verbose logging by default** (Caden's preference): log at boundaries — hotkey fired, recording start/stop, audio buffer size, model load, transcription start/result, insertion method + target app. Include inputs so a failure can be reconstructed.
- **Archive, never `rm`.** Any whole-file deletion goes to `.archive/<UTC-timestamp>/...`; add `.archive/` to `.gitignore`.
- **Ask before adding heavy dependencies or a new language toolchain** beyond the stack settled below.

## Task spec

Build the core dictation loop and the pieces that make it dependable:

1. **Global hotkey / activation**
   - Support both **push-to-talk** (hold the hotkey, release to transcribe) and **toggle** (press to start, press to stop). Default to push-to-talk.
   - Hotkey must work while any app is focused (system-level registration), and be reconfigurable in settings.
   - Debounce/guard against double-triggers and against starting a new recording while one is transcribing.

2. **Audio capture**
   - Capture from the default input device at the sample rate Whisper expects (16 kHz mono). Resample if the device differs.
   - Show a live "recording" indicator. Cap max recording length (e.g. 60s default, configurable) so a stuck session can't run forever.

3. **Local transcription**
   - Use a **local Whisper engine** (see settled decision) with Metal/GPU acceleration on Apple Silicon.
   - Load the model once and keep it warm to hit the latency target; don't reload per utterance.
   - Handle empty/near-silent audio (no crash, no garbage insertion).

4. **Text insertion**
   - Insert the transcript at the cursor of the frontmost app. Primary method: copy to clipboard + synthesize Cmd+V, then restore prior clipboard. This is the most universally reliable path across native and Electron apps.
   - Trim leading/trailing whitespace; apply basic capitalization/spacing cleanup only if it's deterministic (no LLM).

5. **Recording popup / HUD** (the signature superwhisper feel)
   - On activation, show a small **floating panel** (non-activating, borderless, rounded, always-on-top, spanning spaces) near the bottom-center of the screen — it must **not** steal keyboard focus from the field being dictated into.
   - While recording: live audio-level **waveform/meter**. After release/stop: a "transcribing…" state. On completion: brief confirmation, then auto-dismiss.
   - Show error states here too (e.g. "no speech detected", "accessibility not granted").
   - Keep it lightweight and instant — it appears the moment the hotkey fires, before any transcription work.

6. **Menu bar UI + state**
   - Menu bar icon reflects idle / recording / transcribing / error.
   - Menu exposes: toggle mode vs push-to-talk, hotkey config, model selection, and quit.
   - Persist settings locally (app support dir or UserDefaults-equivalent).

7. **Permissions & first-run**
   - Request Microphone and Accessibility on first run with clear copy explaining why each is needed.
   - If a permission is missing, show an actionable state ("Accessibility not granted — open System Settings") rather than failing silently.

8. **Reliability hardening**
   - Timeouts and recovery around: hotkey registration, audio device init, model load, transcription. A failure in any stage returns the app to a clean idle state with a logged, surfaced error.
   - Never leave the mic hot after an error.

## Execution notes

- Get the **happy path end-to-end first** (hotkey → record 5s → transcribe → paste into Notes), then harden. Don't build settings UI before the loop works.
- The two riskiest integration points are **global hotkey registration** and **cross-app text insertion** — prototype and manually verify both in isolation before wiring the full pipeline.
- Keep the Whisper engine behind a small interface so the model/engine can be swapped without touching the capture/insert code.

## Verification / acceptance

- **Build:** clean checkout builds with the single documented command; note it in the commit body.
- **Offline proof:** turn Wi-Fi off (or block the app), run a full dictation, confirm it still transcribes. Additionally confirm **zero network connections** during runtime (e.g. `nettop`/Little Snitch/`lsof -i` against the process while dictating).
- **Cross-app insertion:** manually dictate into Notes, a browser field, Slack, and a terminal; text lands correctly in each.
- **Latency:** time stop-speaking → text-appears for a ~10s utterance; confirm < 2s with the default model on Apple Silicon.
- **Permission-denied path:** revoke Accessibility, launch, confirm a clear surfaced error and no crash.
- **Clipboard integrity:** put known text on the clipboard, dictate, confirm the prior clipboard is restored after insertion.
- **Cannot be auto-tested — flag for the human:** actual speech-to-text accuracy, "feels reliable," and hotkey ergonomics require the user to dictate real speech. The agent must explicitly hand these off: "verified build/offline/insertion/latency mechanically; you must dictate real speech to judge accuracy and feel."

## Settled decisions

- **App name:** FreeSpeech. **Repo/branch:** this directory, `feat/freespeech-mvp`.
- **Platform:** macOS, Apple Silicon first. No Windows/Linux.
- **Transcription engine:** local **whisper.cpp** (ggml models, Metal-accelerated). It is the standard reliable on-device Whisper path and needs no Python runtime.
- **Default model:** an English model balancing speed/accuracy for real-time dictation (`small.en` or `base.en`); make it swappable in settings. Ship without bundling a huge model — fetch once at setup into the app support dir.
- **Insertion strategy:** clipboard + synthesized Cmd+V with prior-clipboard restore (universal reliability), not per-character accessibility typing.
- **Default activation:** push-to-talk, with toggle available.
- **Popup HUD is in scope for the MVP** (part of "works like the original"): a non-activating floating panel with a live waveform. This is another reason the native Swift `NSPanel`/`NSWindow` (`.nonactivatingPanel`, `.canJoinAllSpaces`) path is recommended — a focus-stealing window would break dictation into the target field.
- **No cloud, no accounts, no telemetry.**

## Still open — propose, don't block

For each, pick the reasonable default, add a one-line comment with the rationale, and keep going:

- **[DECISION — VERIFY] Implementation stack.** Recommended: a **native Swift / SwiftUI menu-bar (LSUIElement) app** that shells to / links `whisper.cpp`, because global hotkeys, Accessibility text insertion, low latency, and "no runtime deps" are dramatically more reliable natively than in Electron/Python — and reliability is the stated top priority. This diverges from Caden's usual Python/Node stack, so if a cross-platform or JS/Python-centric approach is strongly preferred, an **Electron/Node** shell around `whisper.cpp` is the fallback (heavier, slightly less reliable for system-level hotkeys/insertion). Default to Swift native unless told otherwise.
- **Hotkey default binding** (e.g. hold `Right Option` or `fn`) — pick a non-conflicting default, make it reconfigurable.
- **Whisper model download source & size** — pick a reputable ggml model host and the smallest model that hits the latency + accuracy bar; document the URL and let the user change it.
- **Max recording length default** (propose 60s) and **silence auto-stop** (propose optional, off by default for the MVP).
- **Settings persistence location** — propose `~/Library/Application Support/FreeSpeech/`.
