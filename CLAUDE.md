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
| **Fixed frame** | 1280×720 landscape, in `project.conf`. Off-shape screens get the same frame centred and letterboxed, never a responsive reflow — that is `stretch/aspect="keep"`. Landscape is load-bearing: the player has to see the run-up, the launch and the landing at once. |
| **One button, and nothing else** | Tap, click, or space. Press and release both matter — press fires the jump, holding feeds in power — but it is still ONE button. No tilt, no drag, no swipe, no multi-touch, no keyboard requirement. Rolling is automatic and momentum-driven; there is no input that steers speed or direction, and adding one changes what the prototype is testing. |
| **No tutorial, ever** | No hint text, no onboarding, no arrows, no "nice timing" feedback, no on-screen indication of where the jump window is. The prototype's entire question is whether the timing reads with nothing explained; anything that explains it answers the question for the player. The distance readout is a score, not a hint, and is the only text a run shows. |
| **Monochrome** | Off-white ink on near-black. Line art, no rasters. |

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
  constant, so an endless run cannot grow the scene.
- **Prefer one `_draw()` over many nodes** for repeated visual elements. The
  terrain draws every segment in one pass, and the frog draws its whole body,
  face and feet in one more.
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

You are a frog that rolls like a wheel. Rolling happens on its own — down
slopes, off landings, out of its own momentum — and you never steer it. The
only thing you can do is tap, and **where the frog is in its roll when you tap
is the whole game.** Picture a clock fixed to the world, not to the frog: 12 is
up, 3 is the way you are going, 6 is the ground, 9 is behind you. The frog's
feet ride round that clock as it spins. Tap with the feet at 6 and you hop
straight up, keeping the speed you had. Tap later, with the feet swung toward
3, and you launch forward on an arc with real extra power — around 4:30 that is
a 45° launch and roughly double the ground covered. Tap in the top half and you
whiff. The point of the prototype is to find out whether a player with no
instructions discovers that gradient within a few seconds of failing at it.

**How long you hold is the second half of the input.** The press fires the jump
immediately, at its weakest, in the direction the clock was showing at that
instant. Keep holding and the rest of the power feeds in over `max_hold_sec`. A
flick is a hop; a full press is a full jump. The clock decides *where*, the
finger decides *how hard*, and the two are independent on purpose.

The jump has to fire on the PRESS, not the release. A jump that resolved on
release would read the clock at a moment the frog had already spun past — at
cruise the body turns roughly 70° during a full hold, which is most of the
window. Resolving on release was tried and measured: it flattened the skill
gradient to nothing, because a fully-charged jump could not be aimed.

**The backward half is deliberately not a mirror.** Tapping toward 9 o'clock
only reverses a frog that was barely moving; a frog with speed just gets shoved
near-vertical instead, because forward momentum blends against the backward
angle and past `backward_dominance_speed` cancels it outright. This is meant to
be hard to pull off on purpose, not a reverse button.

### Changing the feel

**Every number is in `resources/frog_tuning.tres` and
`resources/level_tuning.tres`.** Edit them in the inspector and replay. Do not
hardcode a value into a script to try something — the whole point of this build
is that the feel is iterable without touching code.

The two dials that matter most, and are easiest to get wrong:

- **Radius is randomised per run** (`randomize_radius`, `radius_min`,
  `radius_max`), because it is the dial nobody can guess: it trades spin rate
  against readability and only play settles it. Every run is a data point. Pin
  it with `randomize_radius = false` once the range has told you where to sit.
  Radius is not cosmetic — rolling without slipping ties spin to speed, so a
  small frog spins fast; at radius 32 the frog turned three times a second and
  the 4:30 sweet spot passed in under one physics frame, which made the
  mechanic untappable. Shrinking the frog makes the game harder to *perceive*,
  not harder to *play*.
- **`max_hold_sec` must stay short.** The rest of the jump feeds in over that
  window, and a low forward arc can land before a slow ramp finishes — which
  silently eats the boost and flattens the gradient. 0.32 did exactly that;
  0.15 does not.
- **`start_phase_deg`** puts the frog on 4:30 standing still, so a player's
  very first press — made before they know there is a window — is a good
  forward launch rather than a coin flip.
- **`drive_direction`** is a property of the run, not of the frog. It must not
  follow the direction of travel: tying the self-drive to travel means one
  mistimed opening tap reverses the frog and then accelerates it backward for
  ever — a dead run the player never chose and cannot recover from.

**After any tuning change, run the probe** (§5) and check the gradient still
looks like this. Timed play should beat no play by a wide margin, and tapping
at the very edge of the window should be punished:

```
policy   | median m | note
---------|----------|------------------------------------------------
never    |     20.4 | baseline: no input at all
random   |     26.2 | mashing
neutral  |     26.1 | pressing at 6 o'clock, untimed
boost    |     65.3 | pressing near 4:30 — should win by a lot
late     |     26.2 | pressing at the 3 o'clock edge — should be punished
```

If `boost` stops beating `never` by a wide margin, the change broke the game
rather than tuning it.

The probe also sweeps radius with the skilled policy held fixed. Five seeds per
row is noisy, so read the shape rather than any single number — but the shape
says small frogs lose (they outspin the player) and the usable band starts
around 52:

```
radius |  40  |  52  |  64  |  76  |  88  | 104  | 124
median | 30.8 | 70.0 | 57.7 | 59.2 | 38.8 | 38.8 | 68.9
```

124 scoring well is not a recommendation: a frog that big rolls over terrain
that was supposed to need a jump, which is a different game.
