# Changelog by week Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `CHANGELOG.md` as dated one-line entries grouped by release and week, archive the old text word for word, and add a CI check that keeps the format.

**Architecture:** A throwaway migration script (scratchpad, not committed) dates every old entry from `git blame` and the first-parent history, subagents draft the one-liners, and the script assembles the new file. The committed part is the archive under `changelog/`, the new `CHANGELOG.md`, `tools/check_changelog.py` with `--selftest` and `--summary`, its CI and `run_local_checks.py` wiring, and the contributor docs.

**Tech Stack:** Python 3.12 (ruff-linted, `tools/*.py`), GitHub Actions, Markdown.

Spec: `docs/superpowers/specs/2026-10-05-changelog-by-week-design.md`.

## Global Constraints

- Release heading: `## [Unreleased]` or `## [X.Y.Z] - YYYY-MM-DD`, newest first.
- Week heading: `### Week of D Mon YYYY`, a Monday, newest first within a release.
- Category heading: `#### Added|Changed|Deprecated|Removed|Fixed|Security|Behind the scenes`, in that order, each at most once per week.
- Entry: one source line, `- **D Mon** <text> (<refs>)`, refs are `issue`/`issues`, `PR`, `commit` followed by links to `https://github.com/saworbit/hammerforge/...`.
- At most 200 visible characters per entry (links count by label).
- An entry's date is inside its week, inside its release's window (after the previous release's date, on or before its own), and entries are newest first within a category.
- Every relative link in the file resolves.
- `## At a glance` table: released rows must equal what `--summary` computes.
- No attribution to Claude anywhere; commits and the PR are Shane's.

---

### Task 1: Archive the old text

**Files:**
- Create: `changelog/0.1.0.md`, `changelog/0.1.1.md`, `changelog/0.2.0.md`, `changelog/0.3.0.md`, `changelog/0.3.2.md`, `changelog/after-0.3.2.md`

- [ ] Split `CHANGELOG.md` at each `## [` heading. Write each section verbatim under a two-paragraph header naming the release and linking back to `../CHANGELOG.md`.
- [ ] Verify: concatenating the archived sections (without headers) reproduces lines 6..end of the old file byte for byte.
- [ ] Commit: `Keep the old changelog text, word for word, under changelog/`

### Task 2: The format check

**Files:**
- Create: `tools/check_changelog.py`
- Modify: `.github/workflows/ci.yml` (static-checks job), `tools/run_local_checks.py` (`CHECKS`)

**Interfaces:**
- `check(text: str, root: Path) -> list[str]`: one problem per line, empty when clean.
- `parse(text) -> list[Release]`; `Release(name, date, line, weeks)`, `Week(monday, line, categories)`, `Category(name, line, entries)`, `Entry(day, text, line)`.
- `summary_rows(releases) -> list[str]`: the At a glance rows.
- CLI: no args checks `CHANGELOG.md`; `--selftest`; `--summary`.

- [ ] Write `CASES` first: a clean fixture, then one broken copy per rule (bad release order, release date out of order, week not a Monday, weeks out of order, category out of order, repeated category, unknown category, empty category, entry outside its week, entry outside its release window, entries out of order, wrapped entry, entry over 200 visible chars, entry with no repo link, a broken relative link, a stale glance row, an entry before any week).
- [ ] Run `python tools/check_changelog.py --selftest`; every rule case fails until the rule exists.
- [ ] Implement the rules; selftest passes; `ruff check tools/` and `ruff format --check tools/` pass.
- [ ] Add the two CI steps beside the other guards and the two `Check(...)` entries; `python tools/run_local_checks.py --check` passes.
- [ ] Commit: `Check the changelog's shape in CI`

### Task 3: Date and draft every entry

- [ ] Scratch script: blame `CHANGELOG.md` at HEAD with `-M -w`, map each entry's oldest commit to the first-parent commit that brought it into `main`, take that commit's local date and PR number.
- [ ] Split entries into slices; subagents return `{id, category, text, issues}` per entry, following the style rules in the prompt.
- [ ] Validate: every id answered, issues are numbers that appear in the old text, text under the length budget. Read every line.

### Task 4: Assemble the new CHANGELOG.md

- [ ] Script builds the file: intro, At a glance from `--summary`, per release Highlights (hand-written) and full-notes link, weeks, categories, entries.
- [ ] `python tools/check_changelog.py` passes.
- [ ] Render through `gh api markdown` and read it.
- [ ] Commit: `Rewrite the changelog as one dated line per change, grouped by week`

### Task 5: Contributor docs

**Files:**
- Modify: `CONTRIBUTING.md`, `.github/pull_request_template.md`, `DEVELOPMENT.md`

- [ ] CONTRIBUTING: how to add an entry (this week's heading, category, one line, refs; detail in the PR description).
- [ ] PR template line points at the format.
- [ ] DEVELOPMENT.md release steps: rename `[Unreleased]`, write Highlights, paste `--summary` rows.
- [ ] `python tools/run_local_checks.py` passes. Commit.

### Task 6: Land it

- [ ] Rebase on `origin/main`; fold any entries merged since into the new format and the archive.
- [ ] Push, open the PR as Shane, wait for CI with `tools/wait_for_ci.py` in the background, squash-merge when green.
