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
