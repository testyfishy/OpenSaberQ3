# Feature Specification: scroll hitch fix and UI cleanup plan

**Feature Branch**: `016-scroll-ui-cleanup`

**Created**: 2026-11-05

**Status**: In progress - UI parts (1-4) complete and released as v0.4.0; part 8 slice 1 done; 5, 6, rest of 8 and 9 open

**Input**: "Do you wanna fix the scroll things? Also wanna plan out a specification for eloquent
coding and cleaning up the software part by part. For now let's start with the UI."

## Intent

Two things: find and remove the BeatSaver scroll hitching that survived the stick-only change, and
write the part-by-part cleanup specification the player asked for, beginning with the UI layer.

## Scoped change: BeatSaver scroll hitch

- **Symptom**: scrolling the BeatSaver list with the stick hitches; the settings list hitches less
  but does too. Scroll position is correct and the cursor no longer drags.
- **Reproduction**: open BeatSaver, scroll a full page of results with the right stick at 120 Hz.
- **Current knowledge**: `vr_slider._stick_scroll()` applies whole scroll steps and calls
  `_request_refresh()` for every changed frame; that reaches `BeatSaverPanel._canvas_input_update()`
  which calls `canvas._input_update()` (the OQ_UI2D ray/input pass). The canvas is a world-space
  texture, so the new scroll position also has to be re-rendered. Which of those dominates is
  **not known** - that is what this sheet measures first.
- **Blast radius**: `game/vr_slider.gd`, `game/ui/BeatSaverPanel/BeatSaverPanel.gd`,
  `game/settings_Panel.gd`, the OQ_UI2D canvas update path. No gameplay code.

## Requirements

- **FR-001**: The scroll path MUST be classified before/after the change: per frame, the scroll
  value delta, the viewport render mode at render time, and the redraw cost
  (`viewport_get_measured_render_time_cpu/gpu`), for a 60 s device scroll. The earlier "ray pass"
  assumption was wrong: `_input_update()` only requests a redraw.
- **FR-002**: The hitch MUST be removed or bounded: no stale frames (scroll value changed while the
  viewport rendered DISABLED), no zero-delta frames while the stick is engaged, and the device p99
  inside the idle baseline band recorded in the same session.
- **FR-006**: A bad scroll frame MUST be classified as a frame-time spike or a stale texture; the
  fix is judged on the stale-frame count first, frame time second.
- **FR-003**: The cleanup specification MUST exist as a part-by-part plan, ordered by risk, with a
  gate per part, starting with the UI. It MUST name the parts (UI panels, settings/schema, view
  state, audio, map loading, pooling, bench tooling), the order, and what proves each part
  behaviour-identical.
- **FR-004**: The first UI cleanup slice MUST be defined precisely enough to execute: the files it
  touches, the duplication or coupling it removes, and the exact evidence (UI screenshots, scroll
  probe, frame capture) that proves no behaviour changed.
- **FR-005**: Every cleanup part MUST keep the game playable between slices: no part may leave the
  tree in a state that needs the next part to run.

## Success criteria

- **SC-001**: A recorded 60 s device scroll shows the per-frame cost split (scroll step / input
  pass / redraw) before any fix.
- **SC-002**: After the fix, the scroll run's p99 is within the baseline band and no frame moves
  the list by more than one step.
- **SC-003**: The UI cleanup plan is committed with ordered parts and per-part gates.
- **SC-004**: The first UI slice passes desktop UI screenshots identical to the current build and
  the scroll probe.

## Out of scope

- Gameplay, map loading, pooling and bench tooling refactors (later parts of the plan, not this
  session's execution).
- Feature work beyond the scroll fix.

## Open questions

- Closed by G0: the hitch is a redraw-scheduling problem, not an input-pass or budget problem.
  Fix = live redraw window while the stick moves, one update on stop.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G0 | Scroll diagnosis approach and the UI-first cleanup plan | GO WITH CHANGES: `_input_update()` only requests a redraw; the 3-frame `update_once` coroutine races, so stale textures cause the judder. Instrument with viewport render-time + mode per frame; fix with an UPDATE_ALWAYS window while scrolling. Cleanup order: scroll fix, UI-1 refresh helper, UI-2 `%Name`, UI-3 settings schema, UI-4 BeatSaver split, then view state/audio/pooling/map loading/bench | Implemented in `vr_slider._set_live`; plan recorded in plan.md |
| G1 | UI-3: what is the smallest *real* schema, and how far to migrate in one pass | GO WITH CHANGES: one `const SCHEMA` (default + min/max/step; type from `typeof(default)`), read by load, setters and panel ranges; keep the typed properties and their setters because the audio ones do real work; derive `default_values` in the same order because reload() emits per key in it | Implemented: `SCHEMA` + `_derive_defaults` + `clamp_to_schema` in `Settings.gd`; panel ranges and option maxima read the schema; `verify_settings_schema` extended to freeze order, coverage, types, ranges, clamping and the `changed` contract |
| G4 | UI-3 settings `SCHEMA` final review (`e754f3a`) | CHANGES NEEDED: `cast_or_default`/`set_and_emit` read `SCHEMA` defaults, bypassing the Web platform patch in `default_values`; initialise `default_values` in its declaration to drop the `_ready` ordering dependency; prove the patch path in the schema harness | Fixed in `_default()` + declaration initialiser; harness now patches `saber_tail` to false, asserts a missing key loads false and that writing it stores nothing; all gates re-run green |
| G4 | UI-1..UI-3 together, before UI-4 (`0354122`) | RETHINK UI-1: the watchdog stops any scroll held longer than 0.5 s because `begin_live` only ran on the transition; `helper_UIArea` still calls `canvas._input_update()`, a second authority; fix owner tracking and restore modes. UI-2/UI-3 PASS. Do the line-ending renormalisation before UI-4 | `_set_live` heartbeats every moved frame; `_input_update` routes to `CanvasRefresh`; main menu folded in; `VERIFYCANVAS` added; device 3 s hold renders 289/290 moving frames; `.gitattributes` + renormalise commit `e5a2eb7` |
| G4 (follow-up) | UI-1..UI-3 after the RETHINK fixes (`0354122`..`0457148`) | PASS: watchdog heartbeat, single authority, owner tracking and the 3 s render-count probe verified; `end_live` DISABLED accepted as the intended on-demand steady state. UI-4 goes to G1 | UI-1..UI-3 closed; UI-4 constraints recorded (views refresh through CanvasRefresh, heartbeat on every moved frame, state screenshots, 3 s hold probe, resolve gate per scene) |
| G1 | UI-4 split: Query → DetailView → ResultsView → shell | GO WITH CHANGES: baseline shots + probe before touching code; pager stays in the shell; Covers stays a separate node; Query's timer injected (kept in the panel); keep `_query`/`_rows` compatible or update the smoke in the same commit; inject fixture bytes at the HTTP-completion handlers with stubbed covers; re-measure the line map | Step 0 shots/probe, then Query, DetailView, ResultsView and the shell tidy, each committed; all eight states byte-identical, device probe 0.996, panel 1048 → 928 lines |
| G4 | UI-4 split (`63a3c4f`..`6e6b0f7`) and UI-1..UI-4 as a whole | APPROVE: LOW items only - `CanvasRefresh.of()` on a Window must defer `add_child`, `render_frames` is SubViewport-only, check `_find_canvas` (still used, kept). Debt accepted: `_query` getter alias, code-built views | Deferred add_child + meta-first singleton + a Window case in `VERIFYCANVAS`; counter documented as SubViewport-only; `VERIFYCANVAS bad=0`, `VERIFYPANELBS bad=0` |
| G5 | UI-1..UI-4 vs this spec/plan | Matches spec: 8 byte-identical states after every step; hold probe 0.996 vs 0.997; no view references `BeatSaverApi`/`HTTPRequest`/`_input_update`; buildable commits throughout | Recorded in plan.md; parts 5-9 remain open |
