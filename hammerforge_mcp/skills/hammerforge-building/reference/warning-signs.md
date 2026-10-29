# Warning signs

Answers that mean the plan and the level disagree. Check for these before saying
a build is done.

- **A cut that misses.** `hf_measure` of a subtract brush and the wall it should
  cut gives a positive `gap`: it stands beside the wall and cuts nothing. A cut
  that goes through gives a negative gap.
- **A gap where pieces should meet.** A wall and the floor it stands on, or two
  walls that meet at a corner, should measure a `gap` of 0. A small positive gap
  is a crack the player sees light through; a negative one is an overlap.
- **A brush that moved.** An answer with `snapped` true that you did not plan
  for: the brush is not where your table says. Place it again with
  `"snap": false`, or change the plan to grid steps.
- **A spawn over nothing.** `hf_set_spawn` and `hf_validate` warn when the spawn
  has no floor under it, or when the cordons would leave it over nothing. The
  player falls at the start of every playtest.
- **A doorway the player cannot use.** `hf_validate` names doorways lower than
  the player or narrower than the capsule, and stairs whose risers are higher
  than the player steps.
- **Counts that do not add up.** `hf_get_status` counts every brush. If it holds
  more or fewer than the plan, a batch did not do what you meant; `hf_undo` and
  try again.
- **A refusal.** A refused change names the field it could not take in
  `error.details.param`. Fix that field and send it again, rather than changing
  something else.

- **An edit without an answer.** A timeout covers connecting, attaching, waiting
  to write and waiting for the reply, including a reconnect. Cancellation stops
  waiting; a sent edit may still finish. Retry it with the returned
  `operation_id` so it does not run twice. Undo, redo and bake always need that
  explicit id for a retry.
- **A different target.** `target_changed` means the editor moved to another
  scene or level. Call `hf_get_status` to attach to the new one. A reconnect keeps
  an in-flight edit aimed at its original target; it does not move that edit to
  the new scene.
- **Identical edits that overlap.** Give each intended edit its own
  `operation_id` and reuse that exact id for retries. A successful separate edit
  with the same arguments can clear an earlier edit's remembered automatic id;
  explicit ids avoid that ambiguity ([#2058](https://github.com/saworbit/hammerforge/issues/2058)).
