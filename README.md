# Frog Ball

A frog that rolls like a wheel, and one button.

Tap to jump. **Where the frog is in its roll when you tap decides what the jump
does** — feet at the bottom pops you straight up, feet swung forward launches
you along a flat, fast arc, feet up top and you whiff. **How long you hold
decides how hard** — a flick is a hop, a full press is a full jump. Roll down a
slope, time the press, clear the gap, land rolling, do it again. Get as far as
you can.

Nothing in the game explains any of that, and that is the point. This is a
prototype built to answer one question: **does the roll-timing jump read as
skill to someone who was told nothing?**

Built from
[godot-web-template](https://github.com/Great-Grand-Software/godot-web-template).
Godot 4.7, GDScript, single-threaded Web export.

---

## For an agent: fresh clone → first green PR

**Read this before you do anything else.**

**1. `scripts/bootstrap.sh`. Always, first.**

```bash
scripts/bootstrap.sh
export PATH="$HOME/.godot-toolchain/bin:$PATH"
```

Nothing works before it — there is no `godot`, no `gdlint`, no GUT on the
container. Idempotent; `--check` verifies without installing.

**2. Prove the untouched checkout is green before you change anything.**

```bash
scripts/check-constraints.sh   # every line PASS
gdlint .                       # "Success: no problems found"
godot --headless --import --path .          # once, on a fresh clone
godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
```

The import step is not optional on a clone that has never been opened: GUT's
`class_name`s are not registered until the project is imported once, and the
test run aborts with "Some GUT class_names have not been imported" instead of
failing a test.

The suite must report **62 tests passing across 6 scripts**. Do this even when
your task looks trivial — a failure you see *after* editing is ambiguous unless
you know the baseline was clean.

**3. Read `CLAUDE.md`.** Especially §2 (what you may not do) and §8 (what the
game is, and which two tuning dials are load-bearing).

**4. Re-run the three commands from step 2 before every push.** They are the
first three of the six CI checks, and they run in seconds locally against
minutes in CI.

### Files that need a code owner's approval

`.github/CODEOWNERS` gates the workflows, `scripts/bootstrap.sh`,
`scripts/check-constraints.sh`, `scripts/apply-repo-settings.sh`, `.claude/`,
`CLAUDE.md`, `.gdlintrc`, `project.godot` and `project.conf`. Touching one turns
your PR into someone else's decision. Do not edit them as a side effect of
unrelated work.

### What you cannot do — hand these to a human

- **Enabling Pages** (Settings → Pages → branch `gh-pages`, folder `/ (root)`).
- **Running `scripts/apply-repo-settings.sh apply`** — needs an admin token.
- **Resolving `@OWNER` in `.github/CODEOWNERS`** to a real username or team.
- **Creating repositories, changing visibility or permissions, adding secrets.**
- **Approving or merging a PR.** An agent cannot approve one.

### Hard rules

- **No threads.** Never enable `variant/thread_support`, never raise
  `worker_pool/max_threads`.
- **No C#/.NET.** It cannot export to Web in Godot 4 at all.
- **No 3D.**
- **No secrets, no paid services.**
- **No tutorial or hint UI.** See `CLAUDE.md` §2 — this one is specific to this
  game and it is not a style preference.
- **Never weaken a gate to make CI pass.** A red gate is information.

### When CI is red

Check for **"cancelled", not just "failed"**. Pushing twice quickly cancels the
first run, and a cancelled run reports no failures *and* no successes.

---

## Playing it

- **Tap / click / space** — jump. That is the entire input. Press fires it;
  keep holding for more power.
- Falling below the terrain ends the run; it restarts on its own after a beat.
- The only score is distance.

## Working on the feel

Every number lives in `resources/frog_tuning.tres` and
`resources/level_tuning.tres`. Edit them in the inspector, replay, repeat — do
not hardcode a value into a script to try something.

Then check you have not broken the skill gradient:

```bash
godot --headless --path . -s tools/tuning_probe.gd
```

It plays the real scene under fixed tap policies and prints how far each gets,
then sweeps the frog's radius with skilled play held fixed. Timed play must beat
untimed play by a wide margin. `CLAUDE.md` §8 has the baseline numbers and the
dials most likely to break them.

The frog's radius is deliberately **randomised every run** — it is the hardest
number in the game to guess, so each run is a data point rather than a
committed decision. Pin it in `frog_tuning.tres` once the spread has told you
where to sit.

## Layout

```
scripts/game/jump_solver.gd    ← the mechanic. Pure maths, no Node, fully tested.
scripts/game/terrain_plan.gd   ← the heightfield. Ring-buffered, so it cannot leak.
scripts/game/frog_body.gd      ← the RigidBody2D that consumes both.
scripts/ui/frog_ball_screen.gd ← the run: terrain nodes, camera, distance, restart.
resources/*.tres               ← every tunable number.
tools/tuning_probe.gd          ← headless skill-gradient probe. Not in CI.
```

## Daily loop

1. Branch **in this repo** — not a fork. Fork PRs get a read-only token, so the
   preview cannot deploy.
2. Push. CI runs six checks and builds a preview.
3. A bot comments the preview URL. **Open it and play.** CI proves the build is
   not broken; only a person can say whether it is *right*.
4. Get a review from another person.
5. Add the `tested` label. Auto-merge takes it from there.

## Gotchas worth knowing before you hit them

- **Pages must point at `gh-pages`,** not `main`. The dropdown defaults wrong,
  and the symptom looks like a broken build.
- **Pushing twice quickly cancels the first CI run.** Look for "cancelled".
- **A merged PR's preview is deleted.** Its build becomes the root URL.
