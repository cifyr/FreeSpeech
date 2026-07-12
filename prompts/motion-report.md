# Motion pass — what to look at, per surface

Branch `design/motion`. A view-layer-only motion + micro-polish pass. No behavior,
wiring, copy, settings keys, or callbacks changed; `FreeSpeechCore` untouched; all
234 tests green; `./build.sh --skip-model` signs and installs.

Everything below is driven by one shared grammar in `DesignSystem.swift` — no view
inlines a curve or duration. One decelerate curve (easeOut) for all directional
motion; the live pulse is the only symmetric ease-in-out. **Reduce Motion** is gated
in one place, so with System Settings > Accessibility > Display > Reduce Motion on,
every surface below collapses to instant/opacity-only — no half-played animation.

## Foundation
- **Motion grammar** (`DesignSystem.swift`): `DS.animInstant/Base/Slow/Crossfade`,
  `DS.animAppear(index:)` (capped stagger), `DS.animExpand()` (critically damped, no
  overshoot), `DS.animPulse()` (breathing). Modifiers: `.dsPress`, `.dsHoverHighlight`,
  `.dsValueTransition`, `.dsContentCrossfade`, `.dsLivePulse`; transitions
  `.dsAppear` / `.dsCrossfade`; AppKit mirror `DSMotionAppKit`. `PanelFade` now routes
  through it. Existing button styles were re-pointed at the gated tokens.

## Surfaces
- **HUD** (`HUDController.swift`): appear = fade + small upward slide; dismiss mirrors
  it with a gentle downward sink; waveform↔status text crossfade; a low breathing idle
  ripple on the waveform that fades out as speech rises; POLISHING/TRANSCRIBING dot
  breathes on the pulse idiom. No new timers; single 30fps timer still invalidates on
  hide; contract intact (280x44, non-activating, instant first paint).
- **Settings** (`SettingsWindow.swift`): cards enter with a capped stagger on open and
  every tab switch; replacement-dictionary / per-app rows slide+fade on add/remove;
  unified press feedback and reduce-motion-aware hover/selection on rows.
- **History** (`HistoryWindow.swift`): staggered row appear; search filter fades rows
  in/out; hover-reveal Copy/Insert; a brief COPIED/INSERTED flash; empty-state fade.
- **Onboarding** (`OnboardingWindow.swift`): directional step slide (forward from the
  right, back from the left) + crossfade; progress fill + STEP counter animate; GRANTED
  tag pops; the practice box's focus ring breathes (the hero beat).
- **Control Center** (`ControlCenterWindow.swift`): card-grid stagger on open and tab
  switch; pane crossfade; each running module's icon breathes; enable color crossfade;
  gear/chevron press + eased hover.
- **Module chrome** (`ModuleSettingsWindow.swift`, `HotkeyRecorderButton.swift`): shared
  settings cards fade+rise in; toggle-row hover; number-field focus border eases; the
  hotkey recorder's keycap breathes while capturing and settles instantly on stop.
- **Clop** (`ClopModule.swift`, `ClopToast.swift`, `ClopDropZone.swift`): menu-bar icon
  crossfades watching/paused/working (gated, only on real state change — no flicker on
  progress ticks); toast readout crossfades saved-bytes on reuse; drop-zone target
  highlight eased.
- **Stats** (`StatsModule.swift`): live settings readouts do a native numeric count roll
  on refresh (the module is otherwise AppKit NSMenu — deliberately left alone).
- **BoringNotch** (`BoringNotchModule.swift`): expand/collapse now consumes
  `DS.animExpand()` (physical, zero overshoot) instead of an inlined spring; collapsed↔
  expanded content crossfades.
- **Shelf** (`ShelfPanel.swift`): parked items enter with a capped stagger and animate
  in/out; row hover eased; delete reveals via press + opacity; drag-target highlight on
  the grammar. (Panel entrance already used the shared `dsFadeIn`.)
- **Autoclick** (`AutoclickModule.swift`): the menu-bar status icon breathes while a run
  is live — removed on stop/hide so it never animates offscreen or pegs a core.
- **AppCleaner** (`AppCleanerModule.swift`): scan/detail view crossfades to the
  removal-complete confirmation; app rows gain press + eased selection highlight.
- **Notebook** (`NotebookModule.swift`): note rows enter/leave on list change; row hover
  eased; delete button reveals via press + opacity.
- **CapsLock / Coach** (`CapsLockModule.swift`, `PermissionCoach.swift`): CapsLock
  "hold acts as" readout crossfades; the permission coach panel fades in via the grammar,
  fades out through the reduce-motion-gated AppKit helper, and the GRANTED swap crossfades.
  (`SpeechModule` is a pure controller with no motion surface — left untouched.)

## Human judgment needed (cannot be auto-verified)
The actual feel and timing during real dictation and real module use — whether any
motion distracts, the HUD's calm while thinking/speaking, and the Onboarding step slide
at 520pt. Toggle Reduce Motion on and confirm each surface reads as instant.
