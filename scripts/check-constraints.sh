#!/usr/bin/env bash
#
# Hard-constraint conformance
#
# Deterministic checks for the constraints in CLAUDE.md §2 and the guardrails
# in §4 that can be verified by inspection. No LLM, no API key, no network —
# so this runs identically on a contributor's machine and on a CI runner, and
# it cannot fail because a credential expired.
#
# Project-specific expectations come from project.conf, so this script is
# carried forward between games untouched.
#
# It deliberately checks only what can be checked WITHOUT false positives.
# Judgement calls — is this spawn loop really bounded, does this PR need a test
# — are left to the human reviewer, where they belong. A check that cries wolf
# gets ignored, and an ignored check is worse than no check.
#
# Usage:
#   scripts/check-constraints.sh
#
# Exits non-zero if any constraint is violated.

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f project.conf ]]; then
	echo "project.conf not found at the repo root — see the template README" >&2
	exit 1
fi
# shellcheck source=/dev/null
source ./project.conf

if [[ -t 1 ]]; then
	C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_BLD=$'\033[1m'; C_OFF=$'\033[0m'
else
	C_RED=""; C_GRN=""; C_BLD=""; C_OFF=""
fi

FAILURES=0

pass() { printf '  %sPASS%s  %s\n' "${C_GRN}" "${C_OFF}" "$*"; }
fail() {
	printf '  %sFAIL%s  %s\n' "${C_RED}" "${C_OFF}" "$1"
	shift
	for line in "$@"; do printf '          %s\n' "${line}"; done
	FAILURES=$((FAILURES + 1))
}
info() { printf '%s==>%s %s\n' "${C_BLD}" "${C_OFF}" "$*"; }

# Only files that are actually part of the project. addons/ is vendored (GUT)
# and build/ is generated, so neither is ours to police.
game_files() {
	git ls-files -- '*.gd' '*.tscn' 2>/dev/null | grep -v '^addons/' || true
}

info "checking hard constraints (CLAUDE.md §2, §4)"

# --- No C#/.NET -----------------------------------------------------------
# GDScript only. C# cannot export to Web in Godot 4 at all, so this is not a
# preference — a C# file means the build target is unreachable.
mapfile -t dotnet_files < <(git ls-files -- '*.cs' '*.csproj' '*.sln' '*.slnx' 2>/dev/null || true)
if ((${#dotnet_files[@]} == 0)); then
	pass "no C#/.NET sources"
else
	fail "C#/.NET sources present — Godot 4 cannot export these to Web" "${dotnet_files[@]}"
fi

# --- No 3D ----------------------------------------------------------------
# Matches CamelCase class names ending in 3D (Node3D, MeshInstance3D, ...).
# A bare mention of "3D" in prose does not match, because the pattern requires
# at least one leading capitalised letter.
three_d_hits="$(game_files | xargs -r grep -nE '\b[A-Z][A-Za-z]*3D\b' 2>/dev/null || true)"
if [[ -z "${three_d_hits}" ]]; then
	pass "no 3D nodes or types"
else
	mapfile -t hits <<<"${three_d_hits}"
	fail "3D types found — this project is 2D only" "${hits[@]}"
fi

# --- No multithreading ----------------------------------------------------
# Matches actual USE of a threading primitive, not the word appearing in a
# comment, so "single-threaded" in a docstring stays legal.
thread_hits="$(game_files | xargs -r grep -nE '(WorkerThreadPool\.|\bThread\.new\(|\bMutex\.new\(|\bSemaphore\.new\(|\bConditionVariable\.new\()' 2>/dev/null || true)"
if [[ -z "${thread_hits}" ]]; then
	pass "no threading primitives"
else
	mapfile -t hits <<<"${thread_hits}"
	fail "threading primitives used — the Web target is single-threaded" "${hits[@]}"
fi

# --- project.godot invariants --------------------------------------------
# These carry the constraints nothing else in CI re-derives: a PR could change
# the frame shape or re-enable threads and every other job would still pass.
check_setting() {
	local key="$1" want="$2" label="$3"
	local got
	got="$(grep -E "^${key}=" project.godot | head -n1 | cut -d= -f2- || true)"
	if [[ "${got}" == "${want}" ]]; then
		pass "${label} (${key}=${want})"
	else
		fail "${label}" "project.godot: expected ${key}=${want}, got ${key}=${got:-<missing>}"
	fi
}

check_setting "window/size/viewport_width"  "${VIEWPORT_WIDTH}"    "frame width"
check_setting "window/size/viewport_height" "${VIEWPORT_HEIGHT}"   "frame height"
check_setting "window/stretch/aspect"       "\"${STRETCH_ASPECT}\"" "letterboxed, never reflowed"
check_setting "worker_pool/max_threads"     "${MAX_WORKER_THREADS}" "engine worker pool disabled"
check_setting "renderer/rendering_method"   "\"${RENDERER}\""      "WebGL 2.0 compatible renderer"

# --- Autoload budget ------------------------------------------------------
autoload_count="$(awk '/^\[autoload\]/{f=1;next} /^\[/{f=0} f&&/^[A-Za-z_]+=/{c++} END{print c+0}' project.godot)"
if [[ "${autoload_count}" -le "${MAX_AUTOLOADS}" ]]; then
	pass "autoloads within budget (${autoload_count}/${MAX_AUTOLOADS})"
else
	fail "too many autoloads (${autoload_count}, max ${MAX_AUTOLOADS}) — see project.conf"
fi

# --- Entry scenes exist ---------------------------------------------------
# The smoke test boots exactly these. A typo here means CI silently tests
# nothing, which is the failure mode this whole file exists to prevent.
missing_scenes=()
for scene in ${ENTRY_SCENES}; do
	path="${scene#res://}"
	[[ -f "${path}" ]] || missing_scenes+=("${scene} (project.conf) does not exist")
done
if ((${#missing_scenes[@]} == 0)); then
	pass "every ENTRY_SCENES path exists"
else
	fail "ENTRY_SCENES points at a missing scene" "${missing_scenes[@]}"
fi

# --- Raster budget --------------------------------------------------------
# SVG line art is preferred; rasters are capped. Reads the PNG header directly
# so this needs no image library.
raster_problems=()
while IFS= read -r img; do
	[[ -n "${img}" ]] || continue
	dims="$(python3 - "${img}" <<'PY'
import struct, sys
p = sys.argv[1]
try:
    with open(p, 'rb') as fh:
        head = fh.read(24)
    if head[:8] == b'\x89PNG\r\n\x1a\n':
        w, h = struct.unpack('>II', head[16:24])
        print(f"{w} {h}")
except Exception:
    pass
PY
)"
	[[ -n "${dims}" ]] || continue
	read -r w h <<<"${dims}"
	if ((w > MAX_RASTER_PX || h > MAX_RASTER_PX)); then
		raster_problems+=("${img} is ${w}x${h}, over the ${MAX_RASTER_PX}x${MAX_RASTER_PX} cap")
	fi
done < <(git ls-files -- '*.png' 2>/dev/null | grep -v '^addons/' || true)

if ((${#raster_problems[@]} == 0)); then
	pass "rasters within the ${MAX_RASTER_PX}x${MAX_RASTER_PX} cap"
else
	fail "raster over budget — see project.conf" "${raster_problems[@]}"
fi

echo
if ((FAILURES)); then
	printf '%s%d constraint violation(s)%s\n' "${C_RED}" "${FAILURES}" "${C_OFF}"
	exit 1
fi
printf '%sall hard constraints hold%s\n' "${C_GRN}" "${C_OFF}"
