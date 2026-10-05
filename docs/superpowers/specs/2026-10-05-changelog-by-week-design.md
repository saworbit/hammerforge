# Changelog by week

Approved 2026-10-05.

## Problem

`CHANGELOG.md` was 7,933 lines. The 0.3.2 section alone was 5,370 lines and
371 entries, with about 25 repeated `### Fixed` / `### Added` headings because
every merge appended its own block. Most entries are a paragraph about the
internals. Nothing below a release heading carries a date, so the file cannot
answer when a change went in, what order fixes landed in, or how much moved in
a given week. Test and CI changes sit beside the ones a mapper notices.

## Layout

`CHANGELOG.md`, top to bottom:

1. A short intro saying how to read the file.
2. **At a glance**: one row per release with its date, the dates it covers, and
   how many entries were Added, Changed, Removed, Fixed and Behind the scenes.
   Release rows are counted when a release is cut, by
   `tools/check_changelog.py --summary`. The Unreleased row carries no counts,
   since counts edited by every open PR would make any two of them conflict
   (the reason #933 stopped committing test counts).
3. One section per release, newest first: `## [Unreleased]` or
   `## [0.3.2] - 2026-09-19`, then a `**Highlights**` list of three to five
   plain bullets, a link to that release's full notes in `changelog/`, then one
   `### Week of 29 Sep 2026` section per week, newest first. Weeks start on a
   Monday. A week a release cut through appears under both releases.
4. Inside a week, `#### Added`, `#### Changed`, `#### Deprecated`,
   `#### Removed`, `#### Fixed`, `#### Security`, `#### Behind the scenes`, in
   that order, each at most once. Behind the scenes holds tests, CI, tooling,
   contributor docs and refactors with no visible effect.

## Entries

One source line each:

```
- **4 Oct** One key press in the viewport runs once; Ctrl+D used to make two duplicates. (issue [#927](…/issues/927), PR [#934](…/pull/934))
```

- The date is the day the change merged, in the merge commit's own timezone. It
  falls inside its week. Entries are newest first within a category.
- The text says what changed for the person using HammerForge, in plain words.
  Code names only where the change is about that name.
- The links end the line: `issue` when the entry fixes a tracked issue, `PR`
  when one merged it, `commit` when neither exists (all of 0.1 and 0.2).
- At most 200 visible characters, counting link labels and not URLs.

## History

Dates and PR numbers come from `git blame -M -w` on the old file: each entry
takes the oldest commit among its lines, which survives rewording and the move
from Unreleased into a release. The one-liners are drafted per release slice by
subagents and read by hand before they go in. Highlights are written by hand.
Exact duplicates merge; otherwise one old entry gives one new line.

## Archive

The old text moves word for word into `changelog/<version>.md`, and today's
Unreleased write-ups into `changelog/after-0.3.2.md`. `changelog/` sits at the
repository root, outside the docs site, and the release tree ships only what
`tools/build_release_tree.py` lists, so it never reaches users. From now on the
detail goes in the pull request description.

## Keeping it

`tools/check_changelog.py` checks the structure above: release order, Monday
week headings in descending order, category order with no repeats, entry date
inside its week, newest first, line length, a link on every line, a full-notes
link that resolves. `--selftest` proves it still catches each rule.
`--summary` prints the counts for the At a glance table. Both modes run in the
`static-checks` job and in `tools/run_local_checks.py`, whose `--check`
already requires every CI step and selftest to be accounted for.

CONTRIBUTING, the pull request template and DEVELOPMENT.md's release steps say
how to add an entry and what to do at release time.

## Rollout

One branch, `docs/changelog-by-week`, in its own worktree outside the Godot
project, and one pull request. A pull request open elsewhere that adds an
old-style entry will conflict on `CHANGELOG.md` once this merges; the check
says what the new line should look like.
