# /goal

Produce a concrete visual target for polishing FreeSpeech, a native macOS dictation menu-bar app: HTML mockups (as design components) of its four surfaces — dictation HUD, tabbed Settings window, History window, and Onboarding flow — plus a written token-and-component spec with exact values (spacing scale, type ramp, hover/pressed surfaces, radii, animation timings) that a Swift engineer will translate 1:1 into the app. Everything must stay inside the existing "Greenlight red" design system defined below. The bar: it should read like a shipped, intentional Mac product — calm and native, never flashy; when a choice is unspecified, pick the quieter option. You cannot see the repo; this document is self-contained and is the source of truth.

## Definition of done

- [ ] Four HTML mockups, pixel-faithful to the dimensions given, one per surface, every state shown (HUD: listening / listening-system-audio / transcribing / inserted / error; Settings: all four tabs; History: populated + empty + hover; Onboarding: all six steps or a representative three plus the step chrome)
- [ ] Every color/radius/type value in the mockups comes from the token set below or from new tokens you explicitly add to an "extended tokens" list — no one-off values hiding in the CSS
- [ ] A written spec section per surface: what changed vs. the current state described below, with exact values, so the Swift translation needs zero guessing
- [ ] Uses only system font stacks (`-apple-system`/`system-ui` and `ui-monospace`) — the app uses SF and SF Mono, no custom fonts

## Hard constraints / do not

- **Dark-only.** No light mode, ever.
- **One accent family:** red `#FF453A` (dim variant `#CA3A32`). No new accent hues. Red is for the live/active voice of the app (waveform, selection, live tags), not decoration.
- **Do not redesign the information architecture** — same controls, same grouping, same copy. This is a visual-polish pass: rhythm, hierarchy, states, motion.
- **The HUD is one line, always.** 280x44pt, never a second row, never grows. It floats over any wallpaper without stealing focus, so it needs to hold up on both dark and bright backgrounds.
- No emojis, no images/illustrations, no gradients that fight the flat ink language.

## The design system (current tokens — the red variant of ETok's "Greenlight")

Surfaces (ink scale):
- `ink0 #0A0A0C` app/window background
- `ink1 #131318` raised surface, cards
- `ink2 #1D1D24` inputs, chips
- `ink3 #26262F` pressed/selected surface
- `line #2A2A33` hairline borders and dividers
- `glass rgba(19,19,24,0.88)` the HUD's translucent card

Text:
- `paper #F5F5F0` primary
- `muted #8E8E99` secondary
- `faint #55555F` tertiary/captions

Accent:
- `accent #FF453A` (Apple dark-mode system red), `accentDim #CA3A32`

Radii (continuous corners): control 14, card 20, sheet 28. Chips are full capsules.

Type (SF / SF Mono only):
- Window title: 28pt heavy, paper
- Micro label voice: 11pt SF Mono medium, UPPERCASE, +1.2 tracking — used for section labels (muted), status text, tags
- Row title: 13pt semibold paper; caption: 11pt regular faint; body: 13pt regular

Components today: cards = ink1 fill, 1px line border, radius 20, 16pt padding; chips = ink2 capsule, 1px border (line, or accent at 60% when selected, text goes accent); ghost buttons = transparent, 1px line border, radius 14, 12pt semibold paper, ink3 when pressed; selectable rows = radio dot (accent when on) + title + caption, ink3 fill radius 14 when selected; tags = 10pt mono uppercase capsule, ink2 fill, colored text + 40% colored border.

## The four surfaces as they exist (mock these, improved)

1. **HUD — 280x44pt floating panel, bottom-center of screen.** Glass card (`glass` fill, 1px `line` border, radius 14, shadow). While listening: a 40-bar waveform line in `accent`, bars 24pt max height, rounded 1.5pt, gently rippling at idle (two overlapping sine waves) and riding speech amplitude; when capturing system audio instead of mic, a small `SYSTEM AUDIO` tag (accent, mono 11) sits left of the waveform on the same line. Other states replace the line's content with centered micro-label text: `TRANSCRIBING` / `POLISHING` (muted, with a pulsing 6pt accent dot), `INSERTED` (paper), errors like `NO SPEECH DETECTED` (accent). Improve: bar shaping/envelope so it feels organic not spiky, the waveform-to-text transition (crossfade), shadow/border so it sits well on any wallpaper, tag balance.

2. **Settings — 480x640pt window, ink0.** Header: `FREESPEECH` micro-label in accent over "Settings" 28pt heavy. Below it four tab chips: General / Audio / Text / Smarts. Content scrolls as stacked cards. General: activation-mode chips (Push to talk / Toggle), two hotkey rows (label + recorded-shortcut display box in mono + "Record" ghost button), sound-cues chip toggle, HUD-position chips (4), launch-at-login chip toggle, Updates card (version tag, status line, "Check for Updates" ghost button). Audio: microphone priority list (rows: circular up-chevron button, device name, `ACTIVE` / `SYSTEM DEFAULT` tag), model list (selectable rows with name + size caption + `RECOMMENDED` tag), language dropdown row. Text: post-processing selectable rows (Do nothing / Basic cleanup / Fix grammar / Fix sentence structure / Rewrite in a tone) + tone chips when tone selected, spoken-commands and filler-stripping chip toggles, keep-on-clipboard toggle, replacement dictionary (rows "heard as → replace with" in mono + x-delete; two text fields + Add), per-app rewrite rules (app name + mode tag + x) with an "Add rule for an open app…" dropdown. Smarts: vocabulary text field + on-screen-context toggle, learning card (toggle, "N active rules, M corrections observed", "Reset Learned Corrections" ghost button), history toggle. Improve: vertical rhythm (define a spacing scale), hierarchy between section label / row / caption, unify the three control styles (chips vs rows vs dropdowns — the stock dropdowns clash badly with the dark cards; design a Greenlight dropdown), hover/pressed states for every interactive element, selected-tab treatment.

3. **History — 520x560pt window, ink0.** Same header treatment ("History"), "Clear All" ghost button top-right, search field, then a scroll of entry cards: top line = time (`JUL 10, 13:42` faint mono) + app name (muted mono) + optional `SYSTEM AUDIO` tag + Copy/Insert text buttons right-aligned; below, up to 4 lines of transcript in 13pt paper. Empty state: centered muted "No dictations yet". Improve: row density and scanability, hover-reveal for Copy/Insert, empty state.

4. **Onboarding — fixed-size window, ink0, six steps:** welcome → permissions (mic + accessibility rows with `GRANTED` tags) → hotkeys (two picker groups: "Voice in — your microphone" / "Audio out — what your Mac plays", preset chips + record-custom) → practice (a real text box the user dictates into) → keywords (vocabulary field) → done. Chrome: `FREESPEECH SETUP` micro-label, `STEP n / 6` counter, back/next ghost buttons. Improve: step-progress visualization, consistent card usage with Settings, make the practice step feel like the product's hero moment.

## Deliverables

1. Four HTML mockups (design components), desktop-scaled, dark page background so the windows read in context. Interactive states can be shown side-by-side as variants rather than scripted.
2. "Extended tokens" list: every value you add (hover surface, spacing scale, motion durations/curves, type ramp adjustments) with name + value + where it's used.
3. Per-surface change spec: a terse list of exactly what to change from the current state above (values included), ordered by visual impact — this is what gets translated into Swift.

## Still open — propose, don't block

Animation curves/durations, hover treatments, the spacing scale itself, and the custom dropdown design: choose tasteful values, note the rationale in one line each, and keep going. Do not ask before deciding.
