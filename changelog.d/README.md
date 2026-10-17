# Changelog fragments

Each file here holds a merged change's lines for `CHANGELOG.md`, waiting to be
compiled in. A pull request adds one of these and leaves the changelog alone,
so two open pull requests never conflict over it (#917).

The name is `<slug>.<kind>.md`. The slug is anything unique in lowercase
letters, digits and hyphens. The kind is `added`, `changed`, `deprecated`,
`removed`, `fixed`, `security` or `behind` (Behind the scenes).

Each line is one change, with the issues it closes at the end if there are any:

```
- One key press in the viewport runs once; Ctrl+D used to make two duplicates. (issue [#927](https://github.com/saworbit/hammerforge/issues/927))
```

No date and no pull request link. Compiling adds both, from the squash commit
that merged the file.

    python tools/changelog_fragments.py --check     what CI runs
    python tools/changelog_fragments.py --preview   [Unreleased] with them in
    python tools/changelog_fragments.py --compile   write them in, delete them

CONTRIBUTING.md, Changelog Entries, says when to compile.
