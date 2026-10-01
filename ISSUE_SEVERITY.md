# Issue severity

Type labels say what the ticket is. Severity labels (`P0`–`P3`) say whether it blocks a tester or first-use release.

Every open issue must have **exactly one** of `P0`, `P1`, `P2`, `P3`.
Keep existing type labels. Do not close tickets to make the board look smaller.

## Rank

| Label | Meaning | Ship rule |
| --- | --- | --- |
| `P0` | Showstopper. Core path down, data loss, security, testers cannot start. | Must be zero. |
| `P1` | High. A major surface is wrong for testers. Workaround is painful or none. | Must be zero. |
| `P2` | Medium. Real defect or product gap. Workaround exists, or impact is one edge / one host. | May ship if each open P2 has a one-line accept note. Soft cap: five open P2s. |
| `P3` | Low. Docs, polish, hygiene, nice-to-haves. Testers are not blocked. | Ship with these open. |

If two ranks could apply, pick the **higher** one.

## Agent rules

1. Capture every real finding. File it. Do not swallow it because the board is large.
2. Dedup before filing. File at most three new issues in one session.
3. Always set type + exactly one P-label on create.
4. Never close an issue unless the human asked, or the change that landed actually fixes it (`Fixes #n`).
5. Do not farm P3s. One root cause is one ticket.
6. Do not auto-promote docs/hygiene to P0/P1.
7. Default session works only P0 then P1. P2/P3 only when the human names that session.
8. After a run, emit a short rubric score only: filed-with-P, no-unasked-closes, new-issues-capped, no-split-farming. No self-critique essay.
