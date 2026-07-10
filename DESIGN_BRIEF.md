# /goal

Elevate the visual polish of FreeSpeech's four user-facing surfaces — the dictation HUD, the tabbed Settings window, the History window, and the Onboarding flow — so the app reads like a shipped, intentional Mac product rather than a functional prototype, while staying strictly inside the existing "Greenlight red" design system and the native Swift/AppKit/SwiftUI stack. Work on branch `design/polish` in this repo, keep every behavior and all 91 unit tests untouched and green, build with `./build.sh --skip-model`, commit with an explicit file list, and leave the result for the user to run and judge visually. Motivation: this is a reliability-first dictation tool the user lives in all day — when a design choice is unspecified, choose the quieter, more native-feeling option over the flashier one.

## Definition of done

- [ ] All four surfaces (HUD, Settings, History, Onboarding) visibly improved: consistent spacing rhythm, typographic hierarchy, and component styling across all of them
- [ ] Every color, radius, and type style comes from `DS` / the token set in `Sources/FreeSpeech/DesignSystem.swift` (extend the token set if needed — never inline one-off hex values in views)
- [ ] The HUD is still a single-line, non-activating panel that appears instantly on hotkey fire; its waveform still idles and reacts to amplitude; no second row ever appears
- [ ] No behavior changes: pipeline, settings persistence, hotkeys, windows' functions all identical; `./build.sh --skip-model` passes all 91 tests and produces `dist/FreeSpeech.app`
- [ ] Committed on `design/polish` with an explicit file list; NOT merged; NOT pushed

## Read first

1. `/Users/caden/ClaudeCode/idk/ETok/DESIGN.md` — the origin "Greenlight" design system this app's look is ported from (ink scale, one accent, mono label voice, radii, component specs). FreeSpeech is its **red variant**.
2. `Sources/FreeSpeech/DesignSystem.swift` — the current token set (`DS`) and `GhostButtonStyle`.
3. The four surfaces, in full, before changing anything:
   - `Sources/FreeSpeech/HUDController.swift` (AppKit `NSPanel` + custom `WaveformLineView`)
   - `Sources/FreeSpeech/SettingsWindow.swift` (SwiftUI, four chip-tabs, ~1000 lines)
   - `Sources/FreeSpeech/HistoryWindow.swift` (SwiftUI)
   - `Sources/FreeSpeech/OnboardingWindow.swift` (SwiftUI)

## Context: what exists

- **Design language:** dark-only "Greenlight" (from ETok) with the volt-lime accent swapped for red `#FF453A`. Ink surface scale (`ink0`–`ink3`), hairline `line` color, warm-white `paper` text, `muted`/`faint` secondary text, continuous-corner radii (control 14 / card 20 / sheet 28), uppercase mono micro-labels with 1.2 tracking as the "label voice". System SF + SF Mono only — no bundled fonts.
- **HUD:** 280x44 borderless non-activating panel, dark glass card, always-animating red waveform line; status text swaps into the same line; small "SYSTEM AUDIO" tag inline for that source; fade/slide in, auto-dismiss.
- **Settings:** four tabs as Greenlight chips (General / Audio / Text / Smarts), content is stacked cards, each card = section label + rows of chips/toggles/fields/selectable rows. Includes a shortcut recorder, mic priority list, model list, replacement-dictionary editor, per-app rules with a stock SwiftUI `Menu`, and an Updates card.
- **History:** search field + scrolling rows (timestamp/app/source micro-labels, transcript text, Copy/Insert buttons).
- **Onboarding:** multi-step setup window (permissions, hotkeys, practice dictation box, model-download banner).
- The app icon (`assets/logo.svg`, dark squircle + white waveform) is the established brand mark.

## Hard constraints / do not

- **Do NOT change behavior, wiring, or logic** — this is a visual pass only. No renamed settings keys, no changed callbacks, no new features.
- **Do NOT leave the design system:** dark-only, red accent `#FF453A` family only (no new accent hues), SF/SF Mono only, tokens live in `DesignSystem.swift`.
- **Do NOT break the HUD contract:** single line, non-activating (`.nonactivatingPanel`), never steals focus, appears the instant the hotkey fires (no expensive setup on show), always-moving waveform while listening.
- **No new dependencies, no asset catalogs of images, no emojis anywhere.** Comments explain *why* only.
- **Keep `FreeSpeechCore` untouched** (it is pure logic); all work lives in the `FreeSpeech` target's view files.
- Commit once at the end on `design/polish` with a specific file list. Do not merge, do not push.

## Task spec

Polish each surface, prioritized by visibility:

1. **HUD** — the most-seen pixels in the app. Consider: waveform bar shaping (peak rounding, symmetric envelope, smoother decay), the transition between waveform and status text (crossfade rather than swap), shadow/border tuning so it sits naturally over any wallpaper, and the "SYSTEM AUDIO" tag's balance on the line. Keep it calm — it must not distract while the user is thinking/speaking.
2. **Settings** — biggest surface, currently functional but visually flat. Consider: consistent vertical rhythm between cards and rows (a spacing scale, not ad-hoc paddings), clearer hierarchy between section labels / row titles / captions, unifying the three different toggle/chip/picker styles into one control language, restyling the stock `Picker`/`Menu` uses that clash with the dark cards, hover/pressed states on interactive rows, and the tab bar's selected state.
3. **History** — row density and scanability: stronger timestamp/app hierarchy, hover-reveal for Copy/Insert instead of always-visible buttons, empty-state styling.
4. **Onboarding** — first impression: step progression clarity, consistent card usage with Settings, the practice-dictation box as a moment of delight (it shows the HUD working), download-progress banner styling.
5. **Cross-cutting** — one shared header treatment across windows (the `FREESPEECH` micro-label + heavy title is a good start; make it a shared component), consistent window chrome (titlebar transparency, background), and any token-set gaps you hit (e.g. a hover surface color) added to `DS` once and reused.

## Verification / acceptance

- `./build.sh --skip-model` — all 91 tests pass, `dist/FreeSpeech.app` builds and signs.
- Launch the app (`open dist/FreeSpeech.app`); open Settings (menu bar > Settings), History (menu bar > History), and Onboarding (`defaults delete com.cadenwarren.freespeech hasCompletedOnboarding`, then relaunch — key verified in `Settings.swift`) to eyeball each surface.
- **Cannot be auto-verified — hand off to the human:** the actual aesthetic judgment, HUD feel during real dictation, and animation timing. State explicitly what changed per surface so the user knows what to look at.

## Settled decisions

- Greenlight-red is the design language; dark-only; no light mode.
- Native AppKit (HUD) + SwiftUI (windows); no rewrite of either into the other.
- The logo/squircle mark stays as-is.

## Still open — propose, don't block

- Exact animation curves/durations, hover treatments, and spacing-scale values: pick tasteful values, comment the rationale in `DesignSystem.swift`, and keep going — do not stop to ask.
- If a stock control genuinely cannot be styled acceptably (e.g. SwiftUI `Menu`), a custom Greenlight equivalent is acceptable as long as behavior is identical.
