# Feature Specification: README voice and public copy

**Feature Branch**: `022-readme-voice`

**Created**: 2026-11-06

**Status**: Done - copy revision pushed

**Input**: Player: "Can you revise the git readme language. 'The work since the fork point, in the
order a player notices it. Every \"now\" links to the evidence.' This style of writing where you
seem to be explaining to an audience for everything is not appropriate or rather I dislike it. Can
you talk to the advisor as a marketing specialist to revise the github page."

## Intent

Rewrite the public README (and the same narration where it leaked into the new docs pages) in a
direct product voice: statements about the game and what it does, not commentary about the page,
the reader, or the writing. The facts, numbers and links stay; the lecturing goes.

## Why

The v0.6 README explains its own structure and addresses an audience ("in the order a player
notices it", "Every 'now' links to the evidence", "What the trace shows that an average cannot").
It reads like a report about a project rather than a project page, and the owner dislikes the
voice. The page is public, so this is also the project's first impression.

## Requirements

- **FR-001**: `README.md` MUST remove narration of the page itself and second-person/audience
  explanation. Specifically banned patterns: telling the reader what the section/table does, why
  the page is ordered as it is, that links are evidence, "how to read" instructions, and
  rhetorical asides about averages/percentiles or about what "most projects" do.
- **FR-002**: The voice MUST be direct and product-led: the subject is the game, a feature or a
  measured result; short declarative sentences; present tense. Evidence and deeper reading are
  links at the end of a claim, not a narrated apparatus.
- **FR-003**: The facts MUST not change. Every number, claim, screenshot and destination link in
  the current README MUST survive the rewrite, and no new claim may be added. The headline numbers
  stay qualified by their test conditions.
- **FR-004**: The same audit MUST be applied to `docs/performance.md`, `docs/changelog.md` and
  `docs/v0.6-report.md` where they address the document rather than the subject. Historical pages
  (`PERF.md`, `docs/v0.3-report.md`) are out of scope.
- **FR-005**: An advisor G0 copy review MUST be run with the advisor briefed as a marketing/copy
  specialist, and a G4 final copy review before the push. Verdicts and concrete edits go in the
  Consultation Log.
- **FR-006**: The revision MUST be pushed to `origin/godot-4-port`; no new release, tag, APK or
  version change. The public README and rendered images must be verified after the push.
- **FR-007**: No game code, settings or behaviour may change.
- **FR-008**: The public copy MUST state the red-dot resolution: the reported red dot is the miss
  "x" drawn at the miss position in `points_label.gd`; it was 6 pt and was raised to 28 pt in
  v0.4.0 (`d449f71`). No current page may list it as unexplained, and the GitHub release notes
  MUST be corrected. Historical pages may keep the original report with a resolved note.

## Success criteria

- **SC-001**: A manual and scripted read of `README.md` finds no instance of the banned patterns
  from FR-001; the advisor's marketing review accepts the copy.
- **SC-002**: The README stays at or under ~90 lines, every relative link resolves and every image
  is present.
- **SC-003**: A line-by-line fact check shows every number and claim from the previous README is
  preserved (or deliberately tightened without changing meaning), with no additions.
- **SC-004**: The three new docs pages keep their facts and lose only document-facing narration.
- **SC-005**: `git ls-remote origin refs/heads/godot-4-port` equals local HEAD after the push; the
  rendered README on GitHub matches, and the images return HTTP 200.
- **SC-006**: A search of the README, the new docs pages, `docs/sharing.md` and the GitHub release
  body finds no unresolved red-dot claim; the changelog and the v0.6 report name the miss X.

## Publication evidence (2026-11-06)

- Commit `f0e530b` pushed to `origin/godot-4-port`; `git ls-remote` matches local HEAD.
- Rendered README fetched through the GitHub API starts with the new pitch ("Open-source rhythm
  game for Meta Quest 3..."); the cover, library, leaderboard and frame-time images still return
  HTTP 200.
- The v0.6.0 GitHub release body was edited: the "red dot is still unexplained" bullet is gone,
  everything else is unchanged. It remains the latest release with the same tag and assets.
- Red-dot record: the miss indicator is the red `x` in `points_label.gd`, 6 pt until `d449f71`
  raised it to 28 pt in v0.4.0. It is recorded in the v0.4 changelog and as a resolved note in the
  v0.3 report; it is not presented as open anywhere current.

## Out of scope

- New features, v0.6.1 work, BeastSaber, performance measurements.
- Rewriting release notes, issue templates or the repository description (they were reviewed in
  the previous slice; only fix a sentence if the same voice defect is egregious).
- Changing the project name, structure or navigation.

## Open questions

None. The user's objection is specific; the marketing review supplies the concrete rules.

## Consultation Log

| Gate | Asked | Verdict | Action taken |
|---|---|---|---|
| G4 | 022 README voice (uncommitted copy revision) | APPROVE after LOW edits: docs-table voice, name the reference map, show the post-fix Gloom number, © check; red dot out of the v0.6 report (changelog v0.4 only) | Docs table rewritten, ODDS&ENDS named, Gloom 2.14% after pooling (24% before), report red-dot sentence removed; pushed f0e530b; release body corrected |
| G0 | Marketing/copy review of the current README and docs; voice rules; scope | GO WITH CHANGES: defect is pages that talk about themselves; 8 voice rules (game as subject, no signposting, no rigour claims, no imagined critics, result-first, specifics over narrative headings, only actionable explanation, conditions in one clause); rewrite the top, keep the table with no intro, cut Performance prose to a caption, fix the docs list; don't list BeastSaber as working; keep upstream credit generous | README rewritten; docs cuts applied; red-dot resolution (FR-008) added from the owner's correction |
