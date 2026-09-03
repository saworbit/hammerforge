# Security Policy

HammerForge is a Godot editor plugin. Most of it runs inside the Godot editor
with the same privileges as the editor itself, and a smaller runtime piece
(`HFIORuntime`) ships inside exported games. That shapes what counts as a
security issue here.

## Supported Versions

| Version | Supported |
|---|---|
| `main` | Yes |
| Anything older | No |

There are no tagged releases yet. Fixes land on `main`; please reproduce
against the latest `main` before reporting.

## Reporting a Vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting:
[**Report a vulnerability**](https://github.com/saworbit/hammerforge/security/advisories/new)

That opens a private thread visible only to you and the maintainer. If you
can't use it, contact [@saworbit](https://github.com/saworbit) on GitHub and
ask for a private channel — don't include details in a public message.

Helpful things to include, as far as you have them:

- What an attacker gains, and what they need to start (a crafted level file? a
  malicious addon? editor access?)
- Steps to reproduce, ideally from a fresh scene
- The Godot version and OS
- A minimal proof-of-concept file, if the issue involves parsing

## What Is In Scope

- **Level file parsing** — `.hflevel`, Quake `.map` import, and glTF paths.
  These read untrusted files. Anything that turns a crafted level file into
  code execution, arbitrary file read, or arbitrary file write is in scope.
- **File writes outside the intended destination** — save, autosave, bake
  output, and playtest export writing anywhere the user didn't ask for.
- **Secret handling** — MCP tokens, editor configuration, or anything under
  `user://` leaking into the repository, logs, exported builds, or diagnostics.
- **`HFIORuntime`** — the runtime component that ships in exported games, since
  it evaluates entity I/O connections at runtime.
- **Supply-chain issues in what this repo ships**, including the vendored
  `addons/godot_mcp` snapshot.

## What Is Not In Scope

Please file these as **normal issues** instead — they're still worth reporting,
just not privately:

- Crashes, freezes, or geometry corruption with no path to code execution or
  data disclosure
- Data loss from ordinary bugs (use a bug report; these get triaged seriously)
- Vulnerabilities in Godot itself — report those to
  [godotengine/godot](https://github.com/godotengine/godot/security)
- Upstream vulnerabilities in GUT (`addons/gut/`) — report those upstream,
  though a heads-up here is welcome so the vendored copy can be bumped
- Anything that requires the attacker to already have write access to your
  project directory or your editor configuration

## What to Expect

This is a solo hobby project in early alpha, so please calibrate accordingly:

- **Acknowledgement:** best effort within a week
- **Assessment and fix:** depends entirely on severity and my available time —
  I'll tell you honestly rather than let a report go quiet
- **Disclosure:** coordinated. I'll agree a timeline with you and credit you in
  the advisory and changelog unless you'd rather stay anonymous
- **Bounty:** none — there's no money in this project

Thanks for taking the time to report responsibly.
