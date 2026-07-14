# /goal

On branch `feat/notch-windows-amphetamine`, FreeKit's ten open items below are implemented and
verified live in the built `/Applications/FreeKit.app`: every app-like module (Convert, Tap,
Notebook, Stats, AppCleaner, Shelf, HyperKey, Amphetamine) opens as its own independent window that
survives closing the Control Center hub; Tap and Convert open as small popups while the rest stay
normal-sized; the notch gains app shortcuts, a leftward-shifted clock, and a gear into Tools; Tap
actually clicks; the Tools back-arrow bug is reproduced live and fixed; Notebook gains real Apple
Notes sync without losing its current popup formatting; CapsLock is renamed HyperKey everywhere a
user can see it (without resetting anyone's saved settings); no slider anywhere drags the window;
and a new Amphetamine module keeps the Mac awake on a timer tier or indefinitely via a menu-bar
right-click, persisting the assertion even if FreeKit's window closes. `swift test` (via the
project's linker flags) and `./build.sh --skip-model` are green, every item below has a **live**
pass/fail recorded (not just "compiles"), and work is committed on the branch with an explicit file
list — NOT merged, NOT pushed — for the user to try and merge. Motivation: this is Caden's daily
driver on his own Mac, built and installed fresh for every change — when a detail below is
underspecified, favor "don't reset my existing settings / don't silently no-op" over cleverness.

## Definition of done

- [ ] Convert, Tap, Notebook, Stats, AppCleaner, Shelf, HyperKey, and Amphetamine each open in their
      own `NSWindow` (not the shared Control Center card-swap); closing the Control Center hub
      window leaves any open app window(s) on screen
- [ ] Tap and Convert windows are small popups (comparable to Notebook's existing ~680×440 panel);
      Notebook/Stats/AppCleaner/Shelf/HyperKey/Amphetamine keep their current larger sizes
- [ ] Notch (`BoringNotchModule.swift`) shows per-app shortcut icons and a gear icon next to the pin
      button; the clock has moved further left to make room; the gear opens Control Center's Tools
      section (`selectedSection == .tools`) via `ControlCenterPresenter`, same as the existing
      menu-bar-icon and Convert-gear entry points
- [ ] Tap (`AutoclickModule`) reproducibly performs its clicks when triggered live, with the
      Accessibility permission flow confirmed to actually gate/unblock it rather than silently no-op
- [ ] The Tools back-arrow bug is reproduced live via at least the menu-bar-icon → Tools path, the
      new notch-gear → Tools path, and Convert's own Tools-tab-proxy gear path; whichever path(s)
      show the back arrow rendering outside Tools' own window are fixed so back-arrow and Tools
      content always share one window
- [ ] Notebook can push a note to Apple Notes and pull one back, gated behind an Automation
      permission prompt if the Notes app isn't scriptable yet; the existing Notebook popup's layout,
      RTF formatting round-trip, and local-JSON storage are unchanged for notes the user doesn't
      explicitly sync
- [ ] Every user-facing "Caps Lock" string (`ModuleCatalog.swift` displayName/summary,
      `ModuleGuide.swift`, menu titles, README) reads "HyperKey"; the persisted catalog `id`
      (`"capslock"`) is left unchanged so existing users' saved toggle/hotkey settings survive the
      rename; source files/types are renamed for clarity (`CapsLockModule` → `HyperKeyModule`,
      `Modules/CapsLock/` → `Modules/HyperKey/`)
- [ ] Every `Slider(` in the app (grep broadly, including any custom slider wrapper, not just the
      three already carrying `.dsNoWindowDrag()`) is confirmed live to leave the window stationary
      while dragging; any slider found without the fix gets it
- [ ] Amphetamine module: `ModuleCatalog` entry flips from `.comingSoon` to `.available`; menu-bar
      icon supports (a) picking a timer tier that auto-ends the assertion, and (b) right-click →
      "Stay Awake" toggle that holds an `IOPMAssertionCreateWithName`-based assertion until the user
      right-clicks again to end it — verified to survive the FreeKit window closing; documented,
      not silently broken, limitation where lid-close sleep with no external display can't be
      prevented by a user-space assertion (see Still open below)
- [ ] `swift test` (with the vendored-lib linker flags — see Read first) and
      `./build.sh --skip-model` both pass; the app is reinstalled to `/Applications/FreeKit.app` at
      least once per major item for live verification
- [ ] No emojis anywhere; comments explain *why* only; committed on
      `feat/notch-windows-amphetamine` with an explicit file list; NOT merged; NOT pushed

## Read first

1. `/Users/caden/.claude/CLAUDE.md` — global working rules (branching, commits, archive-not-rm,
   logging, testing, no emojis). Load-bearing.
2. `CLAUDE.md` at this repo's root — module map, shared-vs-per-module code boundaries, and the
   **build/test command** (`./build.sh --skip-model`; never plain `swift build`/`swift test` — they
   don't link `vendor/whisper.cpp`). Also notes: never `tccutil reset`; check `pgrep FreeKit` before
   touching a running instance's UserDefaults/support files; multiple agent sessions may share this
   checkout, so prefer a dedicated branch/worktree for anything beyond a quick single commit.
3. `Sources/FreeSpeech/Modules/Shared/Module.swift` — the `AppModule` protocol and
   `ModuleRegistry`, including the `settingsPopupSize` property this task is partly replacing with
   real per-module windows.
4. `Sources/FreeSpeech/Modules/Shared/ControlCenterWindow.swift` — the current single shared
   Control Center window: `ControlCenterWindowController.show()` (~line 40), `ControlCenterPresenter`
   (~line 18), back-arrow button (~145-158), `resizeForPresentedModule` (~68-84), the Convert
   Tools-tab-proxy gear (~657-680), `Section.tools` (~98, ~109-123).
5. `Sources/FreeSpeech/Modules/Notebook/NotebookModule.swift`, `NotebookPanelController` (~266-341)
   — the **only** existing module with a real independent `NSWindow`; this is the pattern to
   generalize for item 1, not reinvent.
6. `Sources/FreeSpeechCore/Modules/AmphetaminePlan.swift` and its test file — the keep-awake
   decision logic (`Duration` presets, `Vectors`, `requiresRootPrivilege`, `shouldEndForBattery`,
   `countdownText`) already exists; this task wires it to real `IOPMAssertion` calls and UI, it does
   not redesign the plan.
7. `Sources/FreeSpeech/Modules/Clop/ClopModule.swift` — reference pattern for a menu-bar
   `NSStatusItem` with `NSMenuDelegate`/`menuNeedsUpdate` and a right-click path
   (`rightMouseDown`, ~line 982), to reuse for Amphetamine's right-click toggle.

## Context: what exists today (from a fresh read of the code, not assumptions)

- **No app opens its own window today** except Notebook's note-editing panel. Every other module
  (Convert, Tap/Autoclick, Stats, AppCleaner, Shelf, HyperKey) is a SwiftUI card swapped into the
  one `ControlCenterWindowController` singleton via `ControlCenterPresenter.present(moduleID:)`.
  Closing that one window currently closes everything — this is exactly the bug in item 1.
- **"Tap" is not a separate module** — it is Autoclick's user-facing name
  (`AutoclickModule.swift:6,442,354-381`). Don't go looking for a `TapModule`; edit
  `AutoclickModule`.
- **Item 5's "small popup" precedent already exists**: Notebook's `NotebookPanelController`
  (`styleMask [.titled,.closable,.resizable,.utilityWindow,.fullSizeContentView]`,
  `setContentSize(680×440)`, `isReleasedWhenClosed = false`). Current settings-popup sizes if useful
  for "normal size" comparisons: AppCleaner 820×650, Stats 640×720, Notebook settings 580×660, Shelf
  560×480, HyperKey/BoringNotch 600×680, Convert 640×760, Tap/Autoclick 640×720.
- **The back-arrow bug (item 6) does not reproduce from static reading** — `ControlCenterWindow.swift`
  renders the back button and the Tools content (`ModuleSettingsCard`) in the same `ZStack` in the
  same window today. Don't assume the code-reading finding is the full story: reproduce this live
  across all entry points listed in the Definition of Done before concluding it's fixed or already
  fine. It's plausible this bug only appears once item 1's independent-window changes are in place,
  or via Convert's Tools-tab proxy specifically (`convert.openSettingsOnToolTab()`, recent commit
  180e8a9 touched this).
- **Notebook has zero Apple Notes integration today** — storage is local JSON via
  `Sources/FreeSpeechCore/Modules/NotebookStore.swift` (`Note.rich: Data?` RTF blob +
  `plainText`). This is greenfield. The codebase's existing precedent for talking to another Mac
  app is `NSAppleScript` (used for Finder automation in `ConvertModule.swift:217`,
  `ClopModule.swift:213`) — Apple Notes has no EventKit-style framework, but is AppleScript-scriptable
  (`tell application "Notes"`), which fits this codebase's existing pattern better than
  ScriptingBridge or private frameworks.
- **HyperKey rename**: the *pure logic* is already named right —
  `Sources/FreeSpeechCore/Modules/HyperKey.swift` (`HyperKeyMapper`) and
  `Tests/FreeSpeechCoreTests/HyperKeyTests.swift` already say HyperKey. Only the app-facing layer
  still says Caps Lock: `Modules/CapsLock/CapsLockModule.swift` + its `README.md`,
  `ModuleGuide.swift:67` (onboarding copy "Reclaim Caps Lock"), `EventTapHub.swift` (comments),
  `Shell/AppDelegate.swift` (registration + comment), and
  `Sources/FreeSpeechCore/Modules/Shared/ModuleCatalog.swift:55-56` (`id: "capslock", displayName:
  "Caps Lock", summary: "Remap Caps Lock..."`). `Package.swift` excludes the module's README by
  literal path — update that path if the folder is renamed.
- **Slider fix precedent**: all three currently-grep-able `Slider(` call sites
  (`BoringNotchModule.swift:1496`, `ControlCenterWindow.swift:340`, `ShelfModule.swift:167`) already
  end with `.dsNoWindowDrag()`, defined in `Sources/FreeSpeech/Shell/DesignSystem.swift:311-320` — an
  `NSViewRepresentable` blocking `mouseDownCanMoveWindow` because every host window sets
  `isMovableByWindowBackground = true`. The reported bug means either a slider exists that this grep
  missed (custom wrapper, multi-line construction) or it's in a window/pane not yet built at the
  time of the last read. Find it live, don't assume it's already fixed.
- **Amphetamine is roadmap-only today**: `ModuleCatalog.swift:74-77` has
  `id: "amphetamine", status: .comingSoon, ownsMenuBarItem: true` and a real, tested plan
  (`AmphetaminePlan.swift`) — but zero `IOPMAssertion`/`caffeinate` calls exist anywhere in the repo.
  The `AppModule` conformer, IOKit calls, and menu-bar UI are all new code.

## Hard constraints / do not

- Do NOT `tccutil reset` anything, ever, for any permission debugging.
- Do NOT run `git reset --hard` / `git clean -f` / force-push; this checkout may be shared with
  other concurrent agent sessions per the repo's `CLAUDE.md` — prefer this dedicated branch and
  commit normally.
- Do NOT touch a running FreeKit.app's UserDefaults/support files without `pgrep FreeKit` first, and
  quit it cleanly before reinstalling a new build over it.
- Do NOT change the persisted `ModuleCatalog` `id` for the HyperKey rename ("capslock" stays as the
  storage key) — only display strings and source/type names change, so existing installs (including
  Caden's own) don't lose their saved hotkey/enabled state.
- Do NOT invent an "Amphetamine can prevent all sleep unconditionally" claim — macOS will still
  sleep on lid-close with no external display regardless of any user-space assertion; document this
  rather than paper over it.
- Do NOT use `swift build` / `swift test` directly — use `./build.sh --skip-model` (or the linked
  `swift test` invocation with the vendor lib linker flags, see the Clop prompt's precedent in this
  same `prompts/` folder if unsure of the exact flag list) so `CWhisper`/`whisper.cpp` link.
- No emojis anywhere, in code, commits, or comments. Comments explain *why*, never *what*.
- Stay on `feat/notch-windows-amphetamine` for all ten items — one branch, one final commit with an
  explicit file list, matching how this repo's other multi-item prompts (`clop-module-prompt.md`,
  `motion-polish-prompt.md`) were executed.

## Task spec

1. **Independent app windows.** Generalize `NotebookPanelController`'s pattern into a reusable
   per-module window controller (or extend `AppModule` with an `openWindow()` that owns its own
   `NSWindow` instead of routing through `ControlCenterPresenter.present`) for Convert, Tap
   (Autoclick), Stats, AppCleaner, Shelf, and HyperKey. Control Center remains the "Tools" hub for
   browsing/enabling modules; invoking an app's actual working UI opens its own window that outlives
   the hub being closed.
2. **Notch shortcuts + gear.** In `BoringNotchModule.swift`, add per-app shortcut icons and a gear
   icon next to the existing pin button (in the `expandedContent`/`.overlay(alignment: .bottom)`
   block around line 1104, or the `headerStrip` trailing `HStack` around line 984-1006 — pick
   whichever keeps the pin/gear/shortcuts visually grouped). Move the clock further left
   (`headerStrip`, ~968-1011) to make room. The gear opens Control Center's Tools section exactly
   the way `StatusBarController.swift:186`'s `openSettings()` and the existing Convert gear
   (`ControlCenterWindow.swift:657-680`) already do — reuse `ControlCenterPresenter`, don't build a
   second path.
3. *(folded into #2's gear, same mechanism)* — settings gear opens Tools, next to the pin icon.
4. **Fix Tap.** Reproduce live: trigger Tap with Accessibility permission granted and confirm actual
   `CGEvent` clicks land (`AutoclickModule.swift:335-336, 546-547, 562-563`). If it's the permission
   gate at line 205 silently no-op'ing, fix the gate to give clear feedback instead of doing nothing.
5. **Popup sizing.** Once items 1 applies, size Tap's and Convert's new independent windows small
   (comparable to Notebook's ~680×440); leave Notebook/Stats/AppCleaner/Shelf/HyperKey at their
   current larger sizes.
6. **Back-arrow window bug.** Reproduce live across every path that reaches Tools (menu-bar icon,
   new notch gear, Convert's Tools-tab-proxy gear). Fix whichever path puts the back arrow in a
   different window than the Tools content it should dismiss.
7. **Notebook + Apple Notes.** Add optional sync: push a note's content to Apple Notes and pull
   Apple Notes content back into the local `NotebookStore`, using `NSAppleScript` against the
   `Notes` app (this codebase's existing precedent for cross-app automation), gated behind an
   Automation permission prompt (follow the existing `PermissionCoach` pattern) if Notes isn't yet
   authorized. Preserve `NotebookPanelController`'s current popup layout and RTF formatting
   round-trip for notes the user isn't explicitly syncing — this is additive, not a rewrite.
8. **Rename CapsLock → HyperKey.** Rename `Modules/CapsLock/` → `Modules/HyperKey/`,
   `CapsLockModule` → `HyperKeyModule`, update every user-facing string ("Caps Lock" → "HyperKey" in
   `ModuleCatalog.swift` displayName/summary, `ModuleGuide.swift:67` onboarding copy, menu titles,
   the module's `README.md`), update `Package.swift`'s excluded-README path, but leave the catalog
   `id` ("capslock") unchanged.
9. **Slider window-drag bug.** Broaden the search past a plain `Slider(` grep (check for any custom
   slider wrapper component, and multi-line `Slider(...)` constructions) across the whole app,
   reproduce every settings surface's sliders live by dragging them, and apply
   `.dsNoWindowDrag()` (`Shell/DesignSystem.swift:311-320`) anywhere it's missing. Shelf
   (`ShelfModule.swift:167`) is the known-good reference.
10. **Amphetamine keep-awake module.** Flip `ModuleCatalog.swift:74-77`'s `amphetamine` entry from
    `.comingSoon` to `.available`. Build a real `AppModule` conformer wiring `AmphetaminePlan`'s
    existing `Duration`/`Vectors` types to actual `IOPMAssertionCreateWithName` calls: selecting a
    timer tier starts an assertion that auto-clears via `AmphetaminePlan.countdownText`/timer logic;
    right-clicking the menu-bar icon (follow `ClopModule`'s `NSMenuDelegate`/`rightMouseDown`
    pattern) toggles an indefinite "Stay Awake" assertion that only ends on a second right-click,
    and must be confirmed live to still be holding after FreeKit's Control Center window is closed.

## Execution notes

Dependency order matters more than parallelism here — several items touch the same shared files
(`Module.swift`, `ControlCenterWindow.swift`, `ModuleCatalog.swift`):

1. **First, sequentially**: item 1 (independent windows) → item 5 (popup sizing, trivial once 1
   lands) → item 6 (back-arrow, reproduce/fix against the new windowing). Item 4 (Tap fix) can be
   folded in here since Tap's window is being redone anyway.
2. **Then, in parallel** (independent files, safe to isolate in separate worktrees and merge back
   sequentially to avoid clobbering shared files): item 2+3 (notch shortcuts/gear — depends on #1's
   window-opening API existing), item 7 (Notebook + Apple Notes), item 8 (HyperKey rename), item 9
   (slider audit), item 10 (Amphetamine).
3. Rebuild (`./build.sh --skip-model`) and reinstall to `/Applications/FreeKit.app` after each
   logical group, not just once at the very end — live verification per the Definition of Done
   needs a real build at each stage, and catching a regression early is cheaper than untangling it
   after all ten items land.
4. If using subagents per group, brief each one with only the relevant slice of "Context: what
   exists today" above plus the shared "Hard constraints" — don't hand the whole file to a subagent
   fixing only the slider bug.

## Verification / acceptance

- `./build.sh --skip-model` green (includes `swift test`) after the sequential group and after each
  parallel-group merge.
- Live, on-device checks (this is a real menu-bar app — building doesn't prove the UI works):
  - Quit any running FreeKit.app (`pgrep FreeKit` first), install the fresh build, relaunch.
  - Open each of Convert/Tap/Notebook/Stats/AppCleaner/Shelf/HyperKey, confirm its window survives
    closing Control Center's hub window.
  - Confirm Tap's and Convert's windows are visibly smaller than the others.
  - Open the notch, confirm shortcuts + gear render next to the pin and the clock sits further left;
    click the gear, confirm it lands on Tools in the same window Control Center already uses.
  - Trigger Tap with Accessibility permission granted; confirm clicks actually land at the target
    point.
  - From each of the three back-arrow entry points, click into Tools then click back; confirm the
    arrow and the Tools content are always in the same window.
  - In Notebook, create a note, sync to Apple Notes, confirm it appears in Notes.app; edit in
    Notes.app, pull back into FreeKit, confirm content and (best-effort) formatting round-trip, and
    confirm the popup's existing layout is unchanged.
  - Confirm the UI says "HyperKey" everywhere it used to say "Caps Lock", and that an existing
    HyperKey/CapsLock hotkey binding from before the rename still works (proves the `id` didn't
    change).
  - Drag every settings slider in the app; confirm the window never moves.
  - Set an Amphetamine timer tier, confirm the Mac stays awake for that duration and then sleeps
    normally; right-click the menu-bar icon to enable indefinite stay-awake, close FreeKit's window,
    confirm the Mac is still awake later, then right-click again to confirm it can sleep again.
- Note in the final report which checks were done via live automation (AppleScript/System
  Events UI scripting + screenshots, since there is no native macOS Computer Use tool available in
  this environment — only a Chrome-browser automation tool, which doesn't apply to this native app)
  versus which the human should double check themselves (e.g. actually leaving the lid closed
  overnight to confirm sleep-prevention, which isn't practical to verify live in one session).

## Settled decisions

- Control Center stays the single hub for browsing/enabling modules; only the *working UI* of each
  app moves to its own window. This isn't a full rearchitecture away from `ControlCenterWindowController`.
- HyperKey rename keeps the `"capslock"` storage `id` — display/source names change, persisted
  settings keys do not, to avoid resetting any existing install's saved state.
- Apple Notes integration uses `NSAppleScript`, matching this codebase's existing cross-app
  automation precedent (Finder automation in Convert/Clop), not ScriptingBridge or a private
  framework.
- Amphetamine's indefinite mode uses `IOPMAssertionCreateWithName`-based assertions (no `sudo`/root
  requested by default); it is documented, not silently broken, that lid-close sleep with no
  external display attached cannot be prevented by any user-space assertion.

## Still open — propose, don't block

- Whether Amphetamine should also offer a root-requiring `pmset -a disablesleep 1`-style override
  for true lid-closed-no-external-display sleep prevention: default to **not** requesting elevated
  privileges in v1; document the limitation in the module's own UI copy, and leave a comment noting
  this as a possible v2 if the user asks for it later.
- Exact icon/spacing choices for the notch shortcuts row and the Amphetamine menu-bar icon states:
  pick something visually consistent with the existing DS icon/menu conventions used elsewhere
  (e.g. Clop's/Stats' status icon pattern), note the choice inline, and keep going.
- Fidelity of Apple Notes formatting round-trip (rich text ↔ Notes' HTML body) for anything beyond
  bold/italic/lists/plain text: best-effort is acceptable for v1; note any known gaps in the PR
  description rather than blocking on pixel-perfect round-tripping.
