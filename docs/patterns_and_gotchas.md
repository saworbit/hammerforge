---
description: "Patterns and gotchas worth knowing before touching HammerForge's brush geometry, node teardown, undo, test fixtures, or CI."
---

# Patterns and Gotchas

## Testing

- `-gtest` does not narrow a GUT run on its own. `gut_config.gd` applies `dirs`
  and then `tests` one after the other, so with `.gutconfig.json` in play
  `-gtest` *adds* to the 222 scripts already collected from `res://tests/`.
  `-gconfig=` disables the config file and is what makes `-gtest` mean what it
  says. CI's shard command depends on it, and dropping it fails nothing: every
  shard just runs the whole suite, green and four times slower.
