# Feature Specification: Lightweight user profiles (current-user badge, profile panel, no name prompt after songs)

**Feature Branch**: `004-user-profiles`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Add lightweight user profiles: current-user badge, profile panel, no name prompt after songs"

Approved design comes from the project advisor (carried in the orchestrator brief). It is
reproduced here as the contract; the FRs below are the testable form of it.

## Scoped change

- **Symptom**: after every song that lands in the per-map top 10, the player must pick or type
  a name again, and nothing on screen says which name the score belongs to.
- **Root cause**: the name is only known at submit time (`GameStateNewHighScore` shows
  `NameSelector` chips + `Keyboard_highscore`), and `BeepSaber_Game._submit_highscore()` is the
  only path that writes a score. There is no persistent notion of "who is playing".
- **Blast radius**: `HighscoreTable` (record shape, add/rename), end-of-song path
  (`_on_song_ended`, `GameStateMapComplete`), `EndScore` (one extra line + Switch button),
  main menu (Users button + badge), one new autoload, one new panel scene, `project.godot`
  autoload list. No changes to map browser, audio, or performance code.

## User Scenarios & Testing

### User Story 1 - Score is saved without asking (Priority: P1)

A player finishes a song that qualifies for the table. The score is written immediately under
the current profile; the end screen says `Saved as Alice` and offers `Switch`.

**Why this priority**: this is the annoyance being removed; it is the whole feature for a
single-player machine.

**Independent Test**: play any song to the end with `profiles.json` present; no keyboard and no
name chips appear, and the record shows up in the highscore panel under the current name.

**Acceptance Scenarios**:

1. **Given** a current profile "Alice", **When** a song ends with a top-10 score, **Then** the
   record is stored with `player_name == "Alice"` and `user_id == Alice.id`, and the end screen
   shows `Saved as Alice`.
2. **Given** the end screen shows `Saved as Alice`, **When** the player taps `Switch` and picks
   "Bob", **Then** the just-saved record now reads "Bob" (same score, same timestamp), Bob
   becomes the current profile, and the label reads `Saved as Bob`.
3. **Given** a score that does not make the top 10, **When** the song ends, **Then** nothing is
   written and no name prompt appears.

### User Story 2 - Who is playing is visible and switchable (Priority: P2)

The main menu shows a persistent current-user badge and a `Users` button next to `Settings`
that opens a profile panel: chips for every profile (current one highlighted), tap to switch,
`+ New` to create one, `Close` to return.

**Acceptance Scenarios**:

1. **Given** the main menu, **When** it opens, **Then** the badge reads `Playing as: <current>`.
2. **Given** the profile panel, **When** "Bob" is tapped, **Then** `profiles.json` has
   `current == Bob.id`, the badge updates, and the panel stays open showing Bob highlighted.
3. **Given** the profile panel, **When** `+ New` is pressed and "Carol" is typed, **Then** a
   profile Carol exists, is current, and is listed.

### User Story 3 - Existing installs keep their names (Priority: P1)

First launch after the update, with only `user://highscores.json` on disk.

**Acceptance Scenarios**:

1. **Given** records by "Bob" and "Alice" (Alice most recent), **When** the game starts for the
   first time after the update, **Then** profiles Bob and Alice exist, Alice is current, and
   every existing record is unchanged (same score, name, epoch_time).
2. **Given** no highscore file at all, **When** the game starts, **Then** one profile "Player"
   exists and is current.
3. **Given** a `profiles.json` that is corrupt or has `users: []`, **When** the game starts,
   **Then** it is rebuilt by the same bootstrap rules and the game still runs.

### Edge Cases

- Two profiles with the same typed name: the second `+ New` with an existing name returns the
  existing profile instead of duplicating it (case-insensitive on the name).
- The saved record was not good enough for the table: `Switch` is hidden, no rename is possible.
- `Switch` on a record that has since been bumped out of the top 10: renaming is a no-op that
  still switches the current profile.
- Old records have no `user_id`: they are matched by `player_name` and are never rewritten.

## Requirements

### Functional Requirements

- **FR-001**: A new autoload `ProfileManager` MUST persist `user://profiles.json` with exactly
  the shape `{"version":1,"current":"<id>","users":[{"id","name","created"}]}`, all writes via
  `FileAccess` under `user://`, no network.
- **FR-002**: On first run (no `profiles.json`) `ProfileManager` MUST bootstrap profiles from
  the distinct `player_name` values in `user://highscores.json`, and MUST make the most recently
  scored name current. With no names it MUST create one profile named "Player".
- **FR-003**: Bootstrap MUST NOT modify `highscores.json` in any way.
- **FR-004**: New highscore records MUST carry a `user_id` field; existing records MUST NOT be
  rewritten or back-filled.
- **FR-005**: `_on_song_ended` MUST save the score immediately under the current profile with
  no name prompt, and MUST NOT enter `GameStateNewHighScore`.
- **FR-006**: The end screen MUST show `Saved as <name>` for a stored score and offer a `Switch`
  control; with no stored score it MUST show neither.
- **FR-007**: `Switch` MUST open the profile chips without a confirmation modal; choosing a
  profile MUST move the just-saved record to that profile (remove the exact record, re-add it
  with the new name and `user_id`, same score and epoch_time) and make that profile current.
- **FR-008**: The main menu MUST show a persistent current-user badge that tracks
  `ProfileManager.current_name()`.
- **FR-009**: The main menu MUST offer a `Users` button next to `Settings` that opens the profile
  panel: one chip per profile with the current one highlighted, tapping a chip switches the
  current profile, `+ New` starts name entry, `Close` returns to the menu.
- **FR-010**: A corrupt or unparsable `profiles.json` MUST NOT crash the game; it is rebuilt by
  the FR-002 rules.
- **FR-011**: The project MUST still load headless with no SCRIPT ERROR / Parse Error.

### Key Entities

- **Profile**: `{id, name, created}` — id is stable, name is display and record name.
- **profiles.json**: `{version, current, users[]}` as in FR-001.
- **Highscore record**: `{score, player_name, epoch_time}` today; new records add `user_id`.

## Success Criteria

- **SC-001**: Finishing a song produces zero name prompts; a score is on disk before the end
  screen is faded in.
- **SC-002**: Switching to a different profile takes exactly two taps from the main menu
  (`Users`, chip) and two taps from the end screen (`Switch`, chip).
- **SC-003**: An existing install keeps all records byte-identical and its most recent name
  current — verified by comparing `highscores.json` before/after first launch.
- **SC-004**: `godot --headless --path . --quit` prints no SCRIPT ERROR / Parse Error.

## Assumptions

- Single machine, possibly several players in one household; no accounts, no network.
- Play counts stay global in this pass (explicitly out of scope from the approved design).
- The existing highscore keyboard is reused as the text entry for `+ New`.
- `NameSelector` (chips + keyboard prompt) is no longer shown by the end-of-song path; the chips
  widget is kept in the scene but the old `GameStateNewHighScore` flow is no longer entered.

## Out of scope

- Per-profile play counts, per-profile highscore tables, avatars, deletion/renaming of profiles.
- Exporting, installing, or device-side verification (no Quest in this session).
- Any change to map browser, audio engine, or performance settings.

## Open questions

- None blocking. Minor UX call: the end-screen `Switch` opens the same profile panel in front of
  the player rather than a chip row glued to the end score board; recorded as a deviation.

## Consultation Log

| Gate | Question | Verdict | Follow-up |
|------|----------|---------|-----------|
| G0+G1 PLAN CONSULT | spec + implementation plan review | pending | — |
