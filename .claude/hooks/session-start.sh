#!/bin/bash
#
# SessionStart hook
#
# Two jobs, both of which a fresh container otherwise gets wrong:
#
#   1. Attribute commits to the human whose account this session is running as.
#      A fresh container inherits `Claude <noreply@anthropic.com>` from
#      /root/.gitconfig. GitHub links a commit to an account by matching the
#      author email, and that address matches nobody — so without this, every
#      commit from every developer shows as the same unlinked "Claude" and
#      `git blame` stops telling you whose work is whose.
#
#   2. Install the pinned toolchain, so tests and linters actually run.
#
# Idempotent: safe to run on startup, resume, clear and compact alike.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "${PROJECT_DIR}"

# ---------------------------------------------------------------------------
# 1. Git identity
# ---------------------------------------------------------------------------
# Only ever writes repo-local config, so it overrides the container default
# without touching anything the developer set globally on purpose.

configure_identity() {
	# Never clobber an identity already set for this repo deliberately.
	local existing
	existing="$(git config --local --get user.email || true)"
	if [[ -n "${existing}" && "${existing}" != "noreply@anthropic.com" ]]; then
		echo "git identity: already set locally (${existing})"
		return 0
	fi

	if [[ -z "${GH_TOKEN:-}" ]]; then
		echo "git identity: GH_TOKEN unset, leaving default — commits will not be attributed to you" >&2
		return 0
	fi

	local body
	body="$(curl -sS --max-time 15 \
		-H "Authorization: Bearer ${GH_TOKEN}" \
		-H "Accept: application/vnd.github+json" \
		https://api.github.com/user 2>/dev/null || true)"

	local parsed
	parsed="$(printf '%s' "${body}" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
login, uid = d.get("login"), d.get("id")
if not login or not uid:
    sys.exit(1)
# The users.noreply address links the commit to the GitHub account without
# publishing a private address.
print(d.get("name") or login)
print(f"{uid}+{login}@users.noreply.github.com")
' 2>/dev/null || true)"

	if [[ -z "${parsed}" ]]; then
		echo "git identity: could not resolve GitHub account, leaving default" >&2
		return 0
	fi

	local name email
	name="$(sed -n 1p <<<"${parsed}")"
	email="$(sed -n 2p <<<"${parsed}")"
	git config --local user.name "${name}"
	git config --local user.email "${email}"
	echo "git identity: ${name} <${email}>"
}

configure_identity

# ---------------------------------------------------------------------------
# 2. Toolchain
# ---------------------------------------------------------------------------
# scripts/bootstrap.sh is the single source of truth for the environment and is
# idempotent — a second run is a no-op in well under a second.

./scripts/bootstrap.sh

# Make the toolchain visible to every later command in this session.
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
	echo 'export PATH="$HOME/.godot-toolchain/bin:$PATH"' >> "${CLAUDE_ENV_FILE}"
fi
