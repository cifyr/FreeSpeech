# /goal

Extend the **existing** FreeSpeech macOS app (a working native-Swift local dictation tool already in this repo) with five new capabilities — a single-line reactive HUD, overlap-aware "continue don't duplicate" insertion, sentence-continuation casing, an on-by-default copy-to-clipboard option, and a separate-hotkey system-audio input mode — plus wiring the new app logo. When done, the app still builds with `./build.sh`, all existing unit tests plus new ones pass, and the five features work end-to-end on Apple Silicon (macOS 26), fully on-device. Work lives on branch `feat/freespeech-additions`, committed with an explicit file list, left for the user to build, grant permissions, and dictate with. Motivation: this is an already-good app — **do not rebuild it**; make surgical additions that match the existing architecture, naming, and "reliability over features" bar. When a choice is unspecified, pick the simpler, more robust option and match the surrounding code.

## Definition of done

- [ ] **Single-line HUD:** the HUD is one fixed line that always animates (gentle idle motion, reacts to amplitude on speech), then shows "transcribing"/"polishing"/"inserted"; status and errors ("No speech detected") replace the text **on that same line** — the panel never shows a waveform row *and* a separate label row at once
- [ ] **Overlap-aware insertion:** if the transcript repeats words already present just before the caret, the duplicated prefix is dropped and insertion continues from there (best-effort via AX; plain insert when the field is unreadable)
- [ ] **Sentence-continuation casing:** a mid-sentence continuation (caret not after `.`/`!`/`?`/newline, field non-empty) is not force-capitalized and gets correct leading spacing; a new sentence still capitalizes
- [ ] **Copy-to-clipboard option, default ON:** each transcript is left on the clipboard after insertion; when the setting is OFF, the prior clipboard is restored (current behavior)
- [ ] **System-audio input mode:** a second, independently-configurable hotkey captures computer output audio (e.g. the other party on a Zoom call) via ScreenCaptureKit, transcribes and inserts it through the same pipeline; the HUD clearly shows this distinct source; Screen Recording permission is requested lazily
- [ ] **Logo wired:** the generated `assets/logo.svg` is turned into an `.icns` and set as the app icon in `Resources/Info.plist` + `build.sh`
- [ ] New deterministic logic (overlap dedup, casing decision) lives in `FreeSpeechCore` with unit tests; `./build.sh` runs all tests green and produces `dist/FreeSpeech.app`
- [ ] Committed on `feat/freespeech-additions` with an explicit file list; **NOT** merged

## Read first

The existing source is the source of truth — read before changing anything:
- `Sources/FreeSpeech/AppDelegate.swift` — the orchestration/pipeline (hotkey → machine → record → transcribe → post-process → insert → learn)
- `Sources/FreeSpeech/HUDController.swift` — current HUD + `WaveformView` (the file you're reshaping into one line)
- `Sources/FreeSpeech/TextInserter.swift` — clipboard+Cmd+V insertion (where dedup/casing/clipboard-option hook in)
- `Sources/FreeSpeech/AudioRecorder.swift` + `AudioDevices.swift` — mic capture (mirror for system audio)
- `Sources/FreeSpeech/HotkeyManager.swift` — CGEvent hotkey tap (needs a second binding)
- `Sources/FreeSpeech/EditWatcher.swift` — already reads the focused field over AX; **reuse this AX pattern** for reading caret context at insert time
- `Sources/FreeSpeechCore/Settings.swift`, `DictationStateMachine.swift`, `PostProcessing.swift`, `TranscriptCleaner.swift` — the pure, testable core
- `build.sh` — how it builds/signs/downloads the model; `Package.swift` — targets and frameworks

## Context: what already exists (do not rebuild)

A complete, working native-Swift app. **Package:** two targets — `FreeSpeechCore` (pure Foundation, unit-tested) and `FreeSpeech` (AppKit executable) — plus `CWhisper` wrapping vendored `whisper.cpp` v1.9.1. **macOS 26** required (uses Apple `FoundationModels` for on-device rewrites). Builds via `./build.sh` (vendors + Metal-builds whisper, runs tests, assembles ad-hoc-signed `dist/FreeSpeech.app`, one-time model download).

Already implemented — **leave intact, extend only**:
- **Pipeline:** `HotkeyManager` (CGEvent tap) → `DictationStateMachine` (pure, guards double-triggers / mid-transcription presses) → `AudioRecorder` (RMS level callbacks, max-duration cap) → `WhisperCppEngine` (loaded once, kept warm on a serial queue, Metal) → post-processing → `TextInserter` → `EditWatcher`.
- **Activation:** push-to-talk (hold) + toggle; default **Right Option**; custom combos (e.g. Cmd+K), F13, Right Command presets; reconfigurable and persisted.
- **Transcription:** local whisper.cpp, Metal, warm model. Default model `large-v3-turbo-q5_0` (won `bench/`). Model swappable; `AppPaths.installedModels()` enumerates. Silence skip when peak < 0.005 → "No speech detected".
- **Vocabulary hint** fed to whisper, extended by learned terms.
- **Post-processing modes:** off / cleanup (deterministic `TranscriptCleaner`) / grammar / structure / tone — the last three via on-device `FoundationModels`; tones professional/friendly/casual/concise.
- **Edit-learning:** `EditWatcher` snapshots the focused field over AX after insert, re-reads after a 20s settle, LCS word-diffs, promotes rules after 2 sightings, applies them deterministically and feeds them back into the whisper hint. Persisted to `learning.json`. Toggleable.
- **Insertion:** clipboard + synthesized Cmd+V, waits for the held modifier to release so PTT doesn't corrupt the paste, **restores the prior clipboard after 0.7s**.
- **HUD:** non-activating `NSPanel`, dark-glass "Greenlight red" design, a `WaveformView` (36 red bars) **and** a separate mono micro-label row, pulsing dot; bottom-center; states recording/transcribing/processing/success/error.
- **Also:** menu bar (`StatusBarController`), settings window (`SettingsWindow`), design system (`DesignSystem.swift`), mic-priority device selection, mic+accessibility permissions with AX-grant polling, verbose file logging (`Log`), 60s max recording, unit tests for the Core.

## Hard constraints / do not

- **Do NOT rebuild.** Make additive, surgical changes that match existing patterns (`DictationStateMachine` actions, `DS` design tokens, `Log`, `AppPaths`, `Settings` keys). No framework swaps, no restructure.
- **Do NOT merge to main.** Commit once at the end on `feat/freespeech-additions` with a specific file list.
- **Keep `FreeSpeechCore` AppKit-free and unit-tested.** All new deterministic logic (overlap dedup, casing decision) goes there with tests; only glue lives in the `FreeSpeech` target.
- **Reliability beats features.** Every new path must fail closed: unreadable AX field → plain insert; system-audio capture denied/unavailable → surfaced error, mic path untouched; never leave a capture hot after an error.
- **Match house rules:** no emojis anywhere; comments explain *why* only; verbose logging at boundaries with inputs; specific error types with useful messages, never swallowed.
- **Clipboard is a setting, not a silent change:** default ON leaves the transcript; OFF preserves today's restore behavior. Never clobber the clipboard in the OFF case.
- **Archive, never `rm`** for whole-file removals (`.archive/<UTC-timestamp>/...`; `.archive/` already gitignored).
- **Preserve macOS 26 / FoundationModels** and the `./build.sh` flow — new capture code targets APIs available under the existing deployment target.

## Task spec (the delta to build)

1. **Single-line HUD** — reshape `HUDController` + `WaveformView` (`Sources/FreeSpeech/HUDController.swift`)
   - Collapse the card to **one line**: the animated waveform line *is* the HUD. It must **always be moving** — add a gentle idle animation when levels are ~0 (today `reset()` leaves it flat), and let real amplitude drive it during recording.
   - Status text ("Transcribing", "Polishing", "Inserted", "No speech detected", "Accessibility not granted") must render **on that same single line** — swap the line's content/animation in place. Do not stack the waveform row and label row simultaneously; the panel's footprint stays one line at all times.
   - Keep the non-activating panel, `DS` styling, bottom-center placement, and auto-dismiss timings. Keep it instant on hotkey fire.

2. **Overlap-aware insertion ("continue, don't duplicate")** — new Core logic + `TextInserter`
   - Add a pure function in `FreeSpeechCore` (e.g. `SmartInsertion`): given `textBeforeCaret` and `transcript`, return the transcript with any leading overlap removed. Compare the tail of `textBeforeCaret` against the head of the transcript, case-insensitive, whitespace-normalized, on word boundaries; cap the window (~last 8 words) to stay cheap and avoid mis-merges. Unit-test it.
   - In `TextInserter.insert`, before pasting, read the focused element's value and caret position over AX — **reuse the `EditWatcher.focusedElement()` / `value(of:)` pattern**, plus `kAXSelectedTextRangeAttribute` for the caret. If unreadable, skip straight to plain insert and log it.

3. **Sentence-continuation casing** — new Core logic, wired at insert time
   - Add a pure decision in `FreeSpeechCore`: given the character(s) immediately before the caret, decide capitalize-vs-continue and leading spacing. New sentence (empty field, or after `.`/`!`/`?`/newline) → capitalize first letter; mid-sentence → do not capitalize, ensure exactly one leading space. Unit-test it.
   - Reconcile with `TranscriptCleaner`, which currently unconditionally capitalizes the first letter: the caret-aware decision at insertion time must be able to override that down to lowercase for continuations. Keep the decision deterministic — **no LLM**.

4. **Copy-to-clipboard option (default ON)** — `Settings` + `TextInserter` + `AppDelegate`
   - Add a `Settings` bool `copyToClipboard` defaulting `true` (follow the existing `Key`/getter pattern) and a control in `SettingsWindow`.
   - Thread it into `TextInserter.insert(_:copyToClipboard:)`: when true, skip the delayed clipboard restore (leave the transcript); when false, keep today's restore. Applies to both mic and system-audio transcripts.

5. **System-audio input mode (separate hotkey)** — the biggest addition
   - Add a **second, independently-configurable hotkey** (new `Settings` keys, a second `HotkeyManager` binding or a source-tagged event) that starts capture from **system/computer audio output** instead of the mic — so during a Zoom/Meet call the other person's speech is transcribed and inserted. Route it through the **same** transcribe → smart-insert → (optional) learn pipeline.
   - Capture path: **ScreenCaptureKit audio** (`SCStream` audio-only, macOS 13+) so no virtual audio driver is needed; resample to whisper's 16 kHz mono like `AudioRecorder`. Needs **Screen Recording** permission — request it lazily the first time this mode is used, with clear copy; degrade gracefully if denied (surfaced error, mic path unaffected).
   - The HUD must visually distinguish this source ("Listening · system audio" vs the mic). Never run mic and system-audio capture at once — extend/guard the state machine so overlapping sessions are impossible.

6. **Wire the logo** (small)
   - Convert `assets/logo.svg` to a multi-resolution `.icns`, reference it via `CFBundleIconFile` in `Resources/Info.plist`, and copy it into the bundle in `build.sh`. Keep `assets/logo-mark.svg` / `logo-wordmark.svg` as source assets.

## Execution notes

- Order: (1) HUD and (4) clipboard are self-contained and low-risk — do them first. Then (2)+(3) share the insert-time AX read — build the Core functions with tests, then wire once. (5) system-audio is the largest; isolate the `SCStream` capture and verify it alone before wiring the hotkey/HUD/state.
- Reuse, don't reinvent: the AX focused-value read already exists in `EditWatcher`; factor it so both the watcher and the new insert-time context read share it.
- Keep the hot path fast — the AX context read at insert time must be bounded/timed out so it can never hang insertion.

## Verification / acceptance

- **Build + tests:** `./build.sh` runs `swift test` (existing + new Core tests) green and produces `dist/FreeSpeech.app`. Run new deterministic logic under unit tests (overlap dedup, casing decision) — those are fully testable without audio.
- **Single-line HUD:** trigger dictation; confirm one always-moving line, and that "No speech detected" (dictate silence) appears on that same line with no second row.
- **Overlap:** type "let's meet at" into a field, dictate "let's meet at three Friday" → result is "let's meet at three Friday", not duplicated.
- **Casing:** caret after "I think " (no terminator) + dictate "we should ship" → lowercase; caret after "Done. " + dictate "next up" → capitalized.
- **Clipboard both ways:** option ON → transcript is on the clipboard after dictation; OFF → prior clipboard restored.
- **System audio:** play speech from another app/call, fire the system-audio hotkey, confirm it transcribes the computer output (not the mic) and the HUD shows the distinct source (needs Screen Recording granted).
- **Offline/local:** still zero runtime network (model download remains the only, one-time, network access).
- **Cannot be auto-tested — flag for the human:** transcription accuracy, "feels reliable," hotkey ergonomics, and real Zoom capture require the user to run the app and speak/join a call. Hand these off explicitly.

## Settled decisions (already true in the repo)

- **Native Swift** app; `FreeSpeechCore` + `FreeSpeech` + `CWhisper`; **macOS 26**, FoundationModels for rewrites. Stack is not up for debate — extend it.
- **whisper.cpp** (Metal), default model `large-v3-turbo-q5_0`; models in `~/Library/Application Support/FreeSpeech/models`.
- **Insertion** = clipboard + Cmd+V; **default activation** = push-to-talk; **default hotkey** = Right Option.
- **Copy-to-clipboard defaults ON.** **Smart insertion is deterministic — no LLM.** **System audio via ScreenCaptureKit** (virtual-device is only a fallback).
- **No cloud, no accounts, no telemetry.**

## Feature menu — candidate extras (pick what you want; some already exist)

Not committed scope. Build the six items above first; then implement only what the user checks. Items already built are marked so you don't duplicate them.

**Already built (do not re-add):** push-to-talk + toggle, custom-combo hotkeys, model selection, mic-priority device pick, deterministic cleanup, on-device grammar/structure/tone rewrite, edit-learning corrections, vocabulary hint, max-recording cap, verbose logging.

**Insertion & text**
- [ ] "Undo last dictation" hotkey (remove exactly what was inserted)
- [ ] Spoken commands: "new line", "new paragraph", "scratch that"
- [ ] Filler-word stripping (um, uh) toggle
- [ ] Number/date normalization ("twenty twenty six" → "2026")
- [ ] Manual custom replacement dictionary in settings (complements auto edit-learning)

**Modes & activation**
- [ ] Per-app profiles (model/hotkey/post-processing per frontmost app)
- [ ] Hands-free voice activation (start on speech, stop on silence)
- [ ] "Command mode" hotkey: dictation as an instruction, not literal text (would use the existing FoundationModels engine)
- [ ] Language selector / multilingual model

**System-audio / meeting (extends item 5)**
- [ ] Speaker prefix ("Them: …") for system-audio transcripts
- [ ] Rolling live-caption window for a whole call vs one-shot insert
- [ ] Mix mic + system audio into one meeting transcript
- [ ] Save meeting transcript to a local timestamped file

**Output & history**
- [ ] Local transcript history window (searchable, on-device)
- [ ] Re-insert / re-copy past transcripts
- [ ] Export transcript to txt/md; optional append-to-file log

**Feedback & UX**
- [ ] Start/stop/complete sound cues (toggle)
- [ ] HUD position/size preference; per-display placement
- [ ] Live partial-transcript streaming in the HUD
- [ ] Launch-at-login toggle
- [ ] In-app model manager (download/switch/delete ggml models — today they're filesystem-only)

## Still open — propose, don't block

Pick the reasonable default, comment the rationale, keep going:

- **System-audio hotkey default** — a distinct combo separate from Right Option (mic). Propose one non-conflicting.
- **[VERIFY] ScreenCaptureKit one-shot grab** — SCK is built for continuous capture; confirm a short press-to-grab is clean, else buffer a rolling window and cut it on hotkey release. Fall back to documenting a loopback device if SCK proves awkward.
- **Overlap window & fuzziness** — propose last ~8 words, exact-token, case-insensitive, whitespace-normalized (no fuzzy) to avoid wrong merges.
- **Casing source of truth** — propose moving first-letter casing out of `TranscriptCleaner` into the insert-time caret decision so there's one authority; comment the choice.
- **`.icns` generation** — propose `sips`/`iconutil` from a PNG render of `assets/logo.svg` inside `build.sh`; if that adds fragile build steps, pre-generate the `.icns` and commit it.
