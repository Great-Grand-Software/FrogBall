## What changed

<!-- One or two sentences. What does this PR actually do? -->

## Why

<!-- The reason this change exists: the bug, the missing feature, the cleanup. -->

## How it was tested / verified

<!--
Be concrete. At minimum say which of these you ran and what happened:

- [ ] `scripts/bootstrap.sh` passes
- [ ] `gdlint .` clean
- [ ] GUT suite passes locally
- [ ] Project boots headless
- [ ] Web export completes
- [ ] Played the PR preview build in a browser (say what you did in it)

For gameplay changes, the PR preview URL is posted as a comment once CI
finishes — open it and actually play the change before marking this ready.
-->

## Constraint checklist

<!-- Engine and platform limits, not preferences. See CLAUDE.md §2. -->

- [ ] 2D only — no 3D nodes, meshes, physics, or lighting
- [ ] No threads — nothing assumes worker threads
- [ ] GDScript only — no C#/.NET
- [ ] Portrait 3:4 preserved — no responsive reflow, the frame stays fixed
- [ ] Fully monochrome — no colour introduced anywhere
- [ ] Single point of contact — one tap/click, no multi-touch or keyboard
- [ ] Memory-safe — node spawning bounded by a named constant, small assets
- [ ] No unbounded loops or spawn logic

## Design

<!--
Does this decide something the project had deliberately left open
(milestones, changing image themes, sound/animation, meta systems)?

- [ ] No — this does not touch an open slot
- [ ] Yes — and I have written down what I decided, in this PR

An open slot quietly filled is worse than one still open.
-->
