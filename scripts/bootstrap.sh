#!/usr/bin/env bash
#
# Phase 0 environment bootstrap
#
# THE single source of truth for "what does a correctly configured environment
# look like". Both CI runners and Claude Code cloud sessions invoke this exact
# script, so the two definitions cannot drift apart.
#
# Run this FIRST, always, in any session on this repo.
#
# Usage:
#   scripts/bootstrap.sh            # install anything missing, then verify
#   scripts/bootstrap.sh --check    # verify only, install nothing (CI guard)
#   scripts/bootstrap.sh --help
#
# Idempotent: safe to run repeatedly, and safe on a machine that already has
# some or all of the toolchain present.

set -Eeuo pipefail

# --------------------------------------------------------------------------
# Pinned versions. CI verifies against these exact strings.
# --------------------------------------------------------------------------
readonly GODOT_VERSION="4.7.1"
readonly GODOT_RELEASE="stable"
readonly GDTOOLKIT_VERSION="4.5.0"
readonly GUT_VERSION="9.7.1"

readonly GODOT_TAG="${GODOT_VERSION}-${GODOT_RELEASE}"
readonly GODOT_TEMPLATE_DIR_NAME="${GODOT_VERSION}.${GODOT_RELEASE}"

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TOOLCHAIN_DIR="${GODOT_TOOLCHAIN_DIR:-${HOME}/.godot-toolchain}"
readonly BIN_DIR="${TOOLCHAIN_DIR}/bin"
readonly VENV_DIR="${TOOLCHAIN_DIR}/venv"
readonly GODOT_BIN="${BIN_DIR}/godot"
readonly TEMPLATES_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_TEMPLATE_DIR_NAME}"
readonly GUT_DIR="${REPO_ROOT}/addons/gut"

CHECK_ONLY=0
FAILURES=0
declare -a SUMMARY=()

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------
if [[ -t 1 ]]; then
	C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
	C_BLD=$'\033[1m'; C_OFF=$'\033[0m'
else
	C_RED=""; C_GRN=""; C_YEL=""; C_BLD=""; C_OFF=""
fi

log()  { printf '%s==>%s %s\n' "${C_BLD}" "${C_OFF}" "$*"; }
warn() { printf '%s[warn]%s %s\n' "${C_YEL}" "${C_OFF}" "$*" >&2; }
die()  { printf '%s[fatal]%s %s\n' "${C_RED}" "${C_OFF}" "$*" >&2; exit 1; }

record_pass() { SUMMARY+=("PASS|$1|$2"); }
record_fail() { SUMMARY+=("FAIL|$1|$2"); FAILURES=$((FAILURES + 1)); }

usage() {
	sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--check) CHECK_ONLY=1; shift ;;
		--help|-h) usage ;;
		*) die "unknown argument: $1 (try --help)" ;;
	esac
done

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------
require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

log "bootstrap (godot ${GODOT_TAG}, gdtoolkit ${GDTOOLKIT_VERSION}, gut ${GUT_VERSION})"
log "repo root:     ${REPO_ROOT}"
log "toolchain dir: ${TOOLCHAIN_DIR}"

for c in curl unzip git python3; do require_cmd "$c"; done
mkdir -p "${BIN_DIR}"

# Download helper: retries with backoff, fails loudly on a truncated file.
fetch() {
	local url="$1" dest="$2" attempt=1 delay=2
	while (( attempt <= 4 )); do
		if curl -fsSL --retry 0 --max-time 600 -o "${dest}.part" "${url}"; then
			mv "${dest}.part" "${dest}"
			return 0
		fi
		rm -f "${dest}.part"
		warn "download failed (attempt ${attempt}/4): ${url}"
		(( attempt == 4 )) && return 1
		sleep "${delay}"
		delay=$((delay * 2))
		attempt=$((attempt + 1))
	done
	return 1
}

# --------------------------------------------------------------------------
# 1. Godot engine (headless-capable standard Linux build)
# --------------------------------------------------------------------------
godot_version_ok() {
	local bin="$1"
	[[ -x "${bin}" ]] || return 1
	"${bin}" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.${GODOT_RELEASE}" || return 1
}

install_godot() {
	local zip="${TOOLCHAIN_DIR}/godot-${GODOT_TAG}.zip"
	local url="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_linux.x86_64.zip"
	log "installing Godot ${GODOT_TAG}"
	fetch "${url}" "${zip}" || die "could not download Godot from ${url}"
	rm -rf "${TOOLCHAIN_DIR}/godot-unpack"
	mkdir -p "${TOOLCHAIN_DIR}/godot-unpack"
	unzip -q -o "${zip}" -d "${TOOLCHAIN_DIR}/godot-unpack"
	local extracted
	extracted="$(find "${TOOLCHAIN_DIR}/godot-unpack" -maxdepth 2 -type f -name 'Godot_v*_linux.x86_64' | head -1)"
	[[ -n "${extracted}" ]] || die "Godot binary not found inside ${zip}"
	install -m 0755 "${extracted}" "${GODOT_BIN}"
	rm -rf "${TOOLCHAIN_DIR}/godot-unpack" "${zip}"
}

if godot_version_ok "${GODOT_BIN}"; then
	record_pass "godot engine" "${GODOT_TAG} (already installed)"
elif [[ "${CHECK_ONLY}" == "1" ]]; then
	record_fail "godot engine" "missing or wrong version at ${GODOT_BIN}; expected ${GODOT_TAG}"
else
	install_godot
	if godot_version_ok "${GODOT_BIN}"; then
		record_pass "godot engine" "${GODOT_TAG} (installed)"
	else
		record_fail "godot engine" "install completed but version check failed"
	fi
fi

# --------------------------------------------------------------------------
# 2. Export templates (needed for the single-threaded Web export)
# --------------------------------------------------------------------------
# The Web export needs web_nothreads_debug.zip / web_nothreads_release.zip.
# Their presence is what we assert: a templates dir that lacks them would let
# a Web export dry-run fail late and confusingly instead of failing here.
readonly WEB_TEMPLATE_DEBUG="${TEMPLATES_DIR}/web_nothreads_debug.zip"
readonly WEB_TEMPLATE_RELEASE="${TEMPLATES_DIR}/web_nothreads_release.zip"

templates_ok() {
	[[ -f "${WEB_TEMPLATE_DEBUG}" && -f "${WEB_TEMPLATE_RELEASE}" ]]
}

install_templates() {
	local tpz="${TOOLCHAIN_DIR}/templates-${GODOT_TAG}.tpz"
	local url="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_export_templates.tpz"
	log "installing Godot export templates ${GODOT_TAG}"
	fetch "${url}" "${tpz}" || die "could not download export templates from ${url}"
	rm -rf "${TOOLCHAIN_DIR}/tpl-unpack"
	mkdir -p "${TOOLCHAIN_DIR}/tpl-unpack"
	# The .tpz is a zip whose payload lives under a top-level "templates/" dir.
	unzip -q -o "${tpz}" -d "${TOOLCHAIN_DIR}/tpl-unpack"
	mkdir -p "${TEMPLATES_DIR}"
	cp -f "${TOOLCHAIN_DIR}/tpl-unpack/templates/"* "${TEMPLATES_DIR}/"
	rm -rf "${TOOLCHAIN_DIR}/tpl-unpack" "${tpz}"
}

if templates_ok; then
	record_pass "export templates" "${GODOT_TEMPLATE_DIR_NAME} (already installed)"
elif [[ "${CHECK_ONLY}" == "1" ]]; then
	record_fail "export templates" "missing web_nothreads_{debug,release}.zip in ${TEMPLATES_DIR}"
else
	install_templates
	if templates_ok; then
		record_pass "export templates" "${GODOT_TEMPLATE_DIR_NAME} (installed)"
	else
		record_fail "export templates" "install completed but web_nothreads templates are absent"
	fi
fi

# --------------------------------------------------------------------------
# 3. gdtoolkit (gdlint / gdformat)
# --------------------------------------------------------------------------
readonly GDLINT_BIN="${VENV_DIR}/bin/gdlint"
readonly GDFORMAT_BIN="${VENV_DIR}/bin/gdformat"

gdtoolkit_version_ok() {
	[[ -x "${GDLINT_BIN}" ]] || return 1
	# Actually RUN it. A venv whose directory has been moved or copied still
	# looks executable but has a dead interpreter path baked into its shebang,
	# so an existence check alone reports a healthy environment that cannot
	# lint a single file.
	"${GDLINT_BIN}" --version >/dev/null 2>&1 || return 1
	"${VENV_DIR}/bin/python" -c "
import sys
try:
    from importlib.metadata import version
    sys.exit(0 if version('gdtoolkit') == '${GDTOOLKIT_VERSION}' else 1)
except Exception:
    sys.exit(1)
" >/dev/null 2>&1
}

install_gdtoolkit() {
	log "installing gdtoolkit ${GDTOOLKIT_VERSION}"
	[[ -x "${VENV_DIR}/bin/python" ]] || python3 -m venv "${VENV_DIR}"
	"${VENV_DIR}/bin/python" -m pip install --quiet --upgrade pip
	"${VENV_DIR}/bin/python" -m pip install --quiet "gdtoolkit==${GDTOOLKIT_VERSION}"
}

if gdtoolkit_version_ok; then
	record_pass "gdtoolkit" "${GDTOOLKIT_VERSION} (already installed)"
elif [[ "${CHECK_ONLY}" == "1" ]]; then
	record_fail "gdtoolkit" "missing or wrong version in ${VENV_DIR}; expected ${GDTOOLKIT_VERSION}"
else
	install_gdtoolkit
	if gdtoolkit_version_ok; then
		record_pass "gdtoolkit" "${GDTOOLKIT_VERSION} (installed)"
	else
		record_fail "gdtoolkit" "install completed but version check failed"
	fi
fi

# --------------------------------------------------------------------------
# 4. GUT testing addon (vendored into addons/gut, git-ignored)
# --------------------------------------------------------------------------
gut_version_ok() {
	[[ -f "${GUT_DIR}/plugin.cfg" ]] || return 1
	grep -qF "\"${GUT_VERSION}\"" "${GUT_DIR}/plugin.cfg"
}

install_gut() {
	log "installing GUT ${GUT_VERSION}"
	local tmp="${TOOLCHAIN_DIR}/gut-src"
	rm -rf "${tmp}"
	git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${GUT_VERSION}" \
		https://github.com/bitwes/Gut.git "${tmp}" \
		|| die "could not clone GUT v${GUT_VERSION}"
	[[ -d "${tmp}/addons/gut" ]] || die "GUT checkout has no addons/gut directory"
	rm -rf "${GUT_DIR}"
	mkdir -p "${REPO_ROOT}/addons"
	cp -R "${tmp}/addons/gut" "${GUT_DIR}"
	rm -rf "${tmp}"
}

if gut_version_ok; then
	record_pass "gut addon" "${GUT_VERSION} (already installed)"
elif [[ "${CHECK_ONLY}" == "1" ]]; then
	record_fail "gut addon" "missing or wrong version at ${GUT_DIR}; expected ${GUT_VERSION}"
else
	install_gut
	if gut_version_ok; then
		record_pass "gut addon" "${GUT_VERSION} (installed)"
	else
		record_fail "gut addon" "install completed but plugin.cfg does not report ${GUT_VERSION}"
	fi
fi

# --------------------------------------------------------------------------
# 5. Guardrail: this project is GDScript-only. C# cannot export to Web.
# --------------------------------------------------------------------------
if [[ ! -x "${GODOT_BIN}" ]]; then
	record_fail "gdscript-only" "cannot verify: no Godot binary at ${GODOT_BIN}"
elif "${GODOT_BIN}" --headless --version 2>/dev/null | grep -qi 'mono'; then
	record_fail "gdscript-only" "the installed Godot build is a Mono/.NET build; this repo forbids C#"
else
	record_pass "gdscript-only" "non-Mono Godot build confirmed"
fi

# --------------------------------------------------------------------------
# 6. Expose the toolchain on PATH for the rest of the job/session
# --------------------------------------------------------------------------
ln -sfn "${GDLINT_BIN}"   "${BIN_DIR}/gdlint"   2>/dev/null || true
ln -sfn "${GDFORMAT_BIN}" "${BIN_DIR}/gdformat" 2>/dev/null || true

if [[ -n "${GITHUB_PATH:-}" ]]; then
	echo "${BIN_DIR}" >> "${GITHUB_PATH}"
	log "added ${BIN_DIR} to GITHUB_PATH"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
	{
		echo "GODOT_BIN=${GODOT_BIN}"
		echo "GODOT_TOOLCHAIN_DIR=${TOOLCHAIN_DIR}"
	} >> "${GITHUB_ENV}"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo
printf '%s---------------- environment summary ----------------%s\n' "${C_BLD}" "${C_OFF}"
for row in "${SUMMARY[@]}"; do
	status="${row%%|*}"
	rest="${row#*|}"
	name="${rest%%|*}"
	detail="${rest#*|}"
	if [[ "${status}" == "PASS" ]]; then
		printf '  %sPASS%s  %-18s %s\n' "${C_GRN}" "${C_OFF}" "${name}" "${detail}"
	else
		printf '  %sFAIL%s  %-18s %s\n' "${C_RED}" "${C_OFF}" "${name}" "${detail}"
	fi
done
printf '%s-----------------------------------------------------%s\n' "${C_BLD}" "${C_OFF}"

if (( FAILURES > 0 )); then
	printf '%sbootstrap FAILED%s (%d problem(s))\n' "${C_RED}" "${C_OFF}" "${FAILURES}"
	exit 1
fi

printf '%sbootstrap OK%s\n' "${C_GRN}" "${C_OFF}"
printf 'godot binary: %s\n' "${GODOT_BIN}"
printf 'add to PATH:  export PATH="%s:$PATH"\n' "${BIN_DIR}"
