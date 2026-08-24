# Frog Ball

Godot 4 / GDScript 2D game, shipped as a single-threaded Web export on GitHub
Pages, built and reviewed entirely through pull requests. Started from
[godot-web-template](https://github.com/Great-Grand-Software/godot-web-template).

> **New here, and an agent?** Read **"For an agent: fresh clone → first green
> PR"** at the top of `README.md` before you do anything else. It is the
> procedure — bootstrap, prove the baseline green, what you may not touch, and
> what you must hand to a human. This file is the rules that procedure enforces.

---

## 1. Run this first, always

Every session starts from an empty container with nothing installed.

```bash
scripts/bootstrap.sh
export PATH="$HOME/.godot-toolchain/bin:$PATH"
```

`scripts/bootstrap.sh` is the **single source of truth** for what a correctly
configured environment looks like. CI invokes this exact script, and reads the
Godot version out of it rather than repeating the pin, so there is one
definition rather than two that drift.

Idempotent — a second run is a no-op taking under a second.
`scripts/bootstrap.sh --check` verifies without installing and prints a
per-tool `PASS`/`FAIL` table.

Bumping a version means editing the constants at the top of that script and
nothing else.

---

## 2. Hard technical constraints (non-negotiable)

Engine and platform limits, not style preferences. A PR violating one of these
should be rejected regardless of how good the code is. The first four are true
of **every** Godot Web build; do not relax them.

| Constraint | Why |
|---|---|
| **No C#/.NET** | C# cannot export to Web in Godot 4 at all. |
| **No multithreading** | The Web target is single-threaded. Godot's threaded Web export needs COOP/COEP headers GitHub Pages cannot serve. Never enable `variant/thread_support`. |
| **No 3D** | 2D only — `Control`, `Node2D`, sprites, tilemaps. |
| **Bounded memory** | Browsers cap WebAssembly memory hard. See §4. |
| **Fixed frame** | 720×1280 portrait, in `project.conf`. Off-shape screens get the same frame centred and letterboxed, never a responsive reflow — that is `stretch/aspect="keep"`. Portrait is load-bearing: the run climbs, so the frame has to show the tier being aimed at above the frog. |
| **One thumb, one drag** | Press, drag, release. That is the entire input surface: no buttons, no tilt, no multi-touch, no keyboard requirement. Rolling is still automatic and momentum-driven — the player never drives the ball, they kick it. |
| **No tutorial, ever** | No hint text, no onboarding, no instructions, no "nice shot" feedback. The prototype's entire question is whether the timing reads with nothing explained; anything that explains it answers the question for the player. The height readout is a score, not a hint, and is the only text a run shows. |
| **Monochrome** | Off-white ink on near-black. Line art, no rasters. The body is a bare circle with one arrow — the arrow is the only thing on screen carrying information, and anything else drawn on the body competes with it. |

---

## 3. GDScript style conventions

Enforced by `gdlint` (config in `.gdlintrc`). CI fails on any violation.

- **Static typing everywhere.** Annotate every variable, parameter and return
  type. Use `:=` only when the type is obvious from the right-hand side.
- `snake_case` functions and variables; `PascalCase` classes and node names;
  `UPPER_SNAKE_CASE` constants; leading underscore for private members.
- Signal handlers are `_on_<source>_<signal>`. Signals are named for what
  happened, past tense: `landed`, `best_distance_changed`.
- Member order is enforced: `class_name → extends → docstring → signals →
  enums → consts → exports → public vars → private vars → @onready vars →
  methods`. `@onready` comes **after** plain variables; this trips people up.
- Every script opens with a `##` docstring. Comment the *why*, especially for
  constraint-driven decisions.
- Reach into a scene with unique names (`%Frog`), never brittle paths. Wire
  signals in `_ready()` in code, so the connection shows up in the diff rather
  than being buried in a `.tscn`.

---

## 4. Performance and resource guardrails

Concrete, checkable rules, so review can point at a number rather than argue
about whether something "looks reasonable".

- **Never instantiate a collection whose size is driven by data without a hard
  cap.** Any loop that creates nodes must be bounded by a **named constant**,
  never by a data-derived length alone.
- Ceiling: **64 simultaneous nodes** under one gameplay host node. Past that,
  pool and reuse. Terrain obeys this structurally: `TerrainPlan` is a
  fixed-size ring buffer and the collision pool is sized from the same
  constant, so an endless climb cannot grow the scene. `MAX_SEGMENTS` must
  exceed the tiers visible at once **plus** those generated ahead — size it too
  small and the ring recycles the ledge the frog is standing on, which reads as
  the frog freezing in mid-air rather than as a memory bug.
- **Prefer one `_draw()` over many nodes** for repeated visual elements. The
  terrain draws every segment in one pass, and the body draws its circle and
  arrow in one more.
- Every spawned node needs an owner responsible for freeing it.
- **No unbounded loops.** `TerrainPlan.advance_to()` is capped per call by
  `MAX_SPANS_PER_ADVANCE` for exactly this reason.
- No allocation inside `_process()` / `_physics_process()` — no `load()`, no
  `instantiate()`, no new `Array`/`Dictionary` per frame. The frog reuses one
  `JumpOutcome`, the terrain reuses one quad buffer, and the distance label
  only rebuilds its string when the number actually changes. Prefer a finite
  `Tween`; it self-terminates, where a `_process()` loop with a bad exit
  condition hangs a CI runner.
- **Prefer SVG line art.** Rasters are capped by `MAX_RASTER_PX` in
  `project.conf`, and only that big with a stated reason.
- No `preload()` of an asset set. Bulk content loads lazily by path.

**Two different limits, often confused.** Disk size of the build (what is
served to the browser; GitHub's limits are 100 MB per file and 1 GB per site,
enforced by the `web-export` job) is unrelated to memory while playing (the
WebAssembly heap, far tighter on mobile). Do not reason about one using the
other's numbers.

**This game has no end state.** A player can roll until they get bored, so
**the risk is a leak** — a build that leaks a little per segment or per restart
reviews fine and is dead after an hour. `tests/unit/test_frog_ball_screen.gd`
asserts node count stays flat across 500 terrain advances and 30 restarts.
Keep that test passing; do not weaken it.

---

## 5. Testing

```bash
scripts/check-constraints.sh
gdlint .
godot --headless --import --path .          # once, on a fresh clone
godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
godot --headless --path . --quit-after 120 res://scenes/game.tscn
godot --headless --path . --export-release "Web" build/web/index.html
```

- Tests live in `tests/unit/`, named `test_*.gd`, extending `GutTest`.
- **Test the guardrails, not just the happy path.** That the segment cap holds
  matters more than that a jump jumps.
- Pure logic must stay testable without instantiating a scene. `JumpSolver` and
  `TerrainPlan` have no Node in them for exactly this reason — keep it that way.
- Integration tests that need real physics pin `run_seed`. A random course
  makes a flaky test, and a flaky test gets deleted.

There is also `tools/tuning_probe.gd`, which is **not** part of CI:

```bash
godot --headless --path . -s tools/tuning_probe.gd
```

It plays the real scene under fixed tap policies and prints how far each gets.
Use it after any tuning change — see §8.

---

## 6. Pull requests

Use `.github/pull_request_template.md`. Every PR states what changed, why, and
how it was tested — concretely. For gameplay changes, open the PR preview build
in a browser and say what you actually did in it.

Required CI checks, all six must pass: `constraints`, `lint`, `unit-tests`,
`smoke-test`, `web-export`, `web-smoke`. None needs a credential — this
repository has no secrets.

`constraints` is the deterministic half of review: it asserts the §2 limits and
the §4 rules that can be checked without judgement. Run it yourself with
`scripts/check-constraints.sh`. Everything needing judgement is the reviewer's
job.

**Every PR needs a review from another person.** You cannot approve your own,
and an agent cannot approve one at all. Auto-merge switches on only when a
human adds the `tested` label, meaning they played the preview.

Files in `.github/CODEOWNERS` additionally require the owner's approval — the
workflows, the bootstrap and settings scripts, the constraint checker,
`.gdlintrc`, `project.godot` and `project.conf`. The last three are listed
because they define what the gates *mean*.

---

## 7. Layout

```
.
├── project.conf                 ← the only per-project config
├── CLAUDE.md                    ← this file
├── project.godot                ← frame, renderer, threads off
├── export_presets.cfg           ← Web preset; thread_support MUST stay false
├── .claude/                     ← SessionStart hook: git identity + bootstrap
├── scripts/
│   ├── bootstrap.sh             ← run first; single source of truth
│   ├── check-constraints.sh     ← the `constraints` gate; run it locally
│   ├── apply-repo-settings.sh   ← branch protection, derived from the remote
│   ├── autoload/                ← GameState, the only autoload
│   ├── game/                    ← the game: pure logic, plus the one body
│   │                              that consumes it
│   │   ├── frog_tuning.gd       ← every jump/roll dial
│   │   ├── level_tuning.gd      ← every terrain dial
│   │   ├── jump_solver.gd       ← THE mechanic, pure, no Node
│   │   ├── jump_outcome.gd      ← what one tap produced
│   │   ├── terrain_plan.gd      ← the heightfield, pure, ring-buffered
│   │   └── frog_body.gd         ← RigidBody2D; the only impure file here
│   └── ui/                      ← screens
├── resources/                   ← the tuning .tres files you actually edit
├── scenes/                      ← main_menu.tscn (boot) + game.tscn
├── tools/tuning_probe.gd        ← headless skill-gradient probe; not in CI
├── tests/unit/                  ← GUT suite
├── addons/gut/                  ← installed by bootstrap, git-ignored
└── .github/workflows/           ← the six checks, previews, deploy
```

## 8. The game

You are a ball that rolls like a wheel. Rolling happens on its own; you never
drive it. **You drag a thumb, and the ball gets kicked the opposite way.**

The arrow on the ball points wherever your thumb went — drag down and the arrow
plants downward, shoving the ball up. Drag left, it goes right. Drag length is
power: a short pull is a nudge, a long one is a launch. Direction and strength
are independent, and both are visible on the arrow before you let go.

**A kick works anywhere.** Grounded, mid-air, scraping a wall — nothing in the
kick path asks about the ground. This is the whole point of the current design:
players asked for control while in motion, and they have it.

**Which means the difficulty lives entirely in two dials.** `kick_cooldown_sec`
and `air_kicks_allowed` are the only things standing between this and a flight
simulator. With a short cooldown and unlimited air kicks the ball simply flies
and no level can threaten it. They ship permissive, matching the brief, and are
the first thing to tighten once anyone plays it.

### Two level modes, both shipping

`LevelTuning.mode` picks one, and both exist because they ask different things
of the same kick:

- **CLIMB** — up a walled shaft, score is height. Vertical aim under pressure,
  in a column narrow enough that a bad sideways kick puts you into a wall.
- **ROLL** — rightward over ramps and gaps, score is distance. Carrying speed,
  and using the kick to rescue a landing you misjudged.

Neither was deleted when the other was built. The playtest wants to compare.

### The numbers that are locked together

Getting one of these wrong breaks the game rather than making it feel bad:

- In CLIMB, `rise` must exceed the ball's **diameter plus `ledge_thickness`**.
  The gap the ball passes through is the rise minus the slab hanging under the
  tier above. Too tight and the ball scrapes the ceiling, which presents as
  kicks that barely leave the ground.
- Ledge width is bounded from ABOVE. A ledge directly overhead is a ceiling, so
  the shaft must keep a corridor at least a ball wide open beside every tier.
  Widening ledges to make landing easier makes the climb *impossible* instead.
- `max_roll_speed` must stay small relative to the shaft width, because
  horizontal velocity carries through a launch.
- `MAX_SEGMENTS` must exceed the tiers visible at once **plus** those generated
  ahead, or the ring recycles the ledge the ball is standing on — which reads
  as the ball freezing in mid-air rather than as a memory bug.

### Changing the feel

**Every number is in `resources/frog_tuning.tres` and
`resources/level_tuning.tres`.** Edit them in the inspector and replay. Do not
hardcode a value into a script to try something — the whole point of this build
is that the feel is iterable without touching code.

Radius is still randomised per run (`randomize_radius`, `radius_min`,
`radius_max`). It no longer gates whether the mechanic is usable, now that aim
comes from the thumb rather than the body's spin, but it still decides how big
a target the ball is and what gaps it fits through.

**After any tuning change, run the probe** (§5). It plays both modes under
fixed aim policies — flailing in random directions, always kicking straight up,
kicking only when falling, and kicking against whatever is going wrong. The
question it answers is whether deliberate input beats flailing. If `random`
catches the deliberate policies, the mechanic is not being tested no matter how
good the run feels, and the cooldown and air budget are the levers.

Watch also for every policy collapsing together at a low number: that is not
difficulty, it means the ball is being stopped by geometry — see the coupled
numbers above.
