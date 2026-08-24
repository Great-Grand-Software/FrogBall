#!/usr/bin/env bash
#
# Repo protection and merge policy
#
# Applies (or verifies) branch protection, merge policy, and GitHub Pages
# configuration. These settings cannot be committed as files — they live in
# GitHub's own configuration — so this script is the repo's checked-in,
# reviewable definition of them, and the thing to re-run after any drift.
#
# Usage:
#   GH_TOKEN=<token> scripts/apply-repo-settings.sh apply
#   GH_TOKEN=<token> scripts/apply-repo-settings.sh verify
#   scripts/apply-repo-settings.sh plan        # print intent, call nothing
#
# The token needs admin rights on the repo (a classic PAT with `repo`, or a
# fine-grained token with Administration: read/write).

set -Eeuo pipefail

# Owner and repo are read from the git remote, so this script needs no editing
# when you start a new project from this template. Override only if you are
# pointing it at a repo other than the one you are standing in.
remote_slug() {
	local url
	url="$(git config --get remote.origin.url 2>/dev/null || true)"
	[[ -n "${url}" ]] || return 0
	# Handles both git@github.com:owner/repo.git and https://github.com/owner/repo
	printf '%s' "${url%.git}" | sed -E 's#^.*github\.com[:/]##'
}

readonly SLUG="$(remote_slug)"
readonly OWNER="${GAME_OWNER:-${SLUG%%/*}}"
readonly REPO="${GAME_REPO:-${SLUG##*/}}"
readonly BRANCH="${GAME_BRANCH:-main}"

if [[ -z "${OWNER}" || -z "${REPO}" || "${OWNER}" == "${REPO}" && -z "${SLUG}" ]]; then
	printf 'could not determine owner/repo from the git remote.\n' >&2
	printf 'Run this inside a clone, or set GAME_OWNER and GAME_REPO.\n' >&2
	exit 1
fi
readonly PAGES_BRANCH="gh-pages"
readonly API="https://api.github.com"

# The required status checks. These strings must exactly match the `name:`
# of each job in .github/workflows/ci.yml.
readonly REQUIRED_CHECKS=("constraints" "lint" "unit-tests" "smoke-test" "web-export" "web-smoke")

if [[ -t 1 ]]; then
	C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLD=$'\033[1m'; C_OFF=$'\033[0m'
else
	C_RED=""; C_GRN=""; C_YEL=""; C_BLD=""; C_OFF=""
fi

pass() { printf '  %sPASS%s  %s\n' "${C_GRN}" "${C_OFF}" "$*"; }
fail() { printf '  %sFAIL%s  %s\n' "${C_RED}" "${C_OFF}" "$*"; VERIFY_FAILURES=$((VERIFY_FAILURES + 1)); }
info() { printf '%s==>%s %s\n' "${C_BLD}" "${C_OFF}" "$*"; }
warn() { printf '%s[warn]%s %s\n' "${C_YEL}" "${C_OFF}" "$*" >&2; }
die()  { printf '%s[fatal]%s %s\n' "${C_RED}" "${C_OFF}" "$*" >&2; exit 1; }

VERIFY_FAILURES=0

require_token() {
	[[ -n "${GH_TOKEN:-}" ]] || die "GH_TOKEN is not set (needs repo admin rights)"
}

api() {
	local method="$1" path="$2" body="${3:-}"
	local args=(-sS -X "${method}"
		-H "Authorization: Bearer ${GH_TOKEN}"
		-H "Accept: application/vnd.github+json"
		-H "X-GitHub-Api-Version: 2022-11-28"
		-w '\n%{http_code}')
	[[ -n "${body}" ]] && args+=(-d "${body}")
	curl "${args[@]}" "${API}${path}"
}

api_ok() {
	local out status
	out="$(api "$@")" || return 1
	status="$(tail -n1 <<<"${out}")"
	printf '%s' "$(sed '$d' <<<"${out}")"
	[[ "${status}" =~ ^2 ]]
}

checks_json() {
	printf '%s\n' "${REQUIRED_CHECKS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
}

protection_payload() {
	python3 - "$(checks_json)" <<'PY'
import json, sys
contexts = json.loads(sys.argv[1])
print(json.dumps({
    # All six CI checks must pass, against an up-to-date branch.
    "required_status_checks": {"strict": True, "contexts": contexts},
    # Admin bypass, deliberately off: admins are bound by everything below,
    # exactly like everyone else. The trade-off is worth stating plainly. A
    # gate an admin can step around is only as strong as the habit of not
    # stepping around it, and on a project with one or two admins that is no
    # gate at all.
    # The cost is real and worth knowing before you hit it: there is now no
    # way to force-push or merge past a wedged main. Unsticking one means
    # turning protection off by hand (or re-running this script with False),
    # fixing the state, and turning it back on.
    "enforce_admins": True,
    "required_pull_request_reviews": {
        "required_approving_review_count": 1,
        # This is what makes CODEOWNERS binding.
        "require_code_owner_reviews": True,
        # A new push invalidates a stale approval.
        "dismiss_stale_reviews": True,
        "require_last_push_approval": False,
    },
    # No user/team push restrictions: collaborators have write access, they
    # just cannot push to main directly.
    "restrictions": None,
    "allow_force_pushes": False,
    "allow_deletions": False,
    "block_creations": False,
    # Squash-only merges keep history linear.
    "required_linear_history": True,
    "required_conversation_resolution": True,
}))
PY
}

settings_payload() {
	cat <<'JSON'
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY",
  "has_issues": true,
  "has_wiki": false,
  "has_projects": false
}
JSON
}

cmd_plan() {
	info "target: ${OWNER}/${REPO} (branch ${BRANCH})"
	echo
	echo "Repo settings (PATCH /repos/${OWNER}/${REPO}):"
	settings_payload | python3 -m json.tool
	echo
	echo "Branch protection (PUT /repos/${OWNER}/${REPO}/branches/${BRANCH}/protection):"
	protection_payload | python3 -m json.tool
	echo
	echo "GitHub Pages (POST /repos/${OWNER}/${REPO}/pages): source branch '${PAGES_BRANCH}', path '/'"
	echo
	echo "No API calls were made. Run 'apply' to write these."
}

cmd_apply() {
	require_token
	info "applying repo settings to ${OWNER}/${REPO}"

	if api_ok PATCH "/repos/${OWNER}/${REPO}" "$(settings_payload)" >/dev/null; then
		pass "merge policy: squash-only, auto-merge on, auto-delete branch on merge"
	else
		fail "could not update repo settings (needs admin rights)"
	fi

	info "applying branch protection to '${BRANCH}'"
	if api_ok PUT "/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" "$(protection_payload)" >/dev/null; then
		pass "branch protection: PRs required, 6 checks, 1 approval, CODEOWNERS binding"
	else
		fail "could not apply branch protection (needs admin rights)"
	fi

	info "configuring GitHub Pages from '${PAGES_BRANCH}'"
	local pages_body
	pages_body="$(printf '{"source":{"branch":"%s","path":"/"}}' "${PAGES_BRANCH}")"
	if api_ok POST "/repos/${OWNER}/${REPO}/pages" "${pages_body}" >/dev/null; then
		pass "GitHub Pages enabled from ${PAGES_BRANCH}"
	elif api_ok PUT "/repos/${OWNER}/${REPO}/pages" "${pages_body}" >/dev/null; then
		pass "GitHub Pages source updated to ${PAGES_BRANCH}"
	else
		warn "could not configure Pages. This is expected until the ${PAGES_BRANCH}"
		warn "branch exists (the first PR preview creates it). Re-run then."
	fi

	echo
	info "re-reading settings to confirm they stuck"
	cmd_verify
}

cmd_verify() {
	require_token
	info "verifying ${OWNER}/${REPO}"
	VERIFY_FAILURES=0

	local repo_json protection_json
	repo_json="$(api_ok GET "/repos/${OWNER}/${REPO}" || true)"
	protection_json="$(api_ok GET "/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" || true)"

	python3 - "${repo_json}" "${protection_json}" "$(checks_json)" <<'PY'
import json, sys

repo_raw, prot_raw, checks_raw = sys.argv[1], sys.argv[2], sys.argv[3]
want_checks = set(json.loads(checks_raw))
BRANCH_LABEL = "the default branch"
failures = 0

def result(ok, label, detail=""):
    global failures
    tag = "\033[32mPASS\033[0m" if ok else "\033[31mFAIL\033[0m"
    print(f"  {tag}  {label}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures += 1

try:
    repo = json.loads(repo_raw)
except Exception:
    repo = {}
try:
    prot = json.loads(prot_raw)
except Exception:
    prot = {}

# Tell "the API would not talk to us" apart from "the settings are wrong".
# Without this, a 403 renders as every line FAIL, which reads exactly like
# drift and sends you hunting a problem that is not there. A successful repo
# read always carries full_name; a successful protection read always carries
# url. The one exception is a genuine 404 "Branch not protected", which IS a
# real answer and must stay a FAIL rather than an error.
prot_absent = str(prot.get("message", "")).lower().startswith("branch not protected")
if "full_name" not in repo or ("url" not in prot and not prot_absent):
    said = repo.get("message") or prot.get("message") or "no response from the API"
    print("  \033[31mERROR\033[0m  could not read the repository from the API")
    print(f"         GitHub said: {said}")
    print( "         Nothing was checked. This is NOT a report about your settings.")
    print( "         Check the token has admin rights on the repo, and that you are")
    print( "         not running this from an agent session (see the README).      ")
    sys.exit(2)

if not repo:
    result(False, "repo readable", "could not read repo settings")
else:
    result(repo.get("allow_squash_merge") is True, "squash merge allowed")
    result(repo.get("allow_merge_commit") is False, "merge commits disabled")
    result(repo.get("allow_rebase_merge") is False, "rebase merges disabled")
    result(repo.get("allow_auto_merge") is True, "auto-merge enabled")
    result(repo.get("delete_branch_on_merge") is True, "auto-delete branch on merge")

if not prot or "required_status_checks" not in prot:
    result(False, "branch protection", f"{BRANCH_LABEL} is not protected")
else:
    got_checks = set(prot.get("required_status_checks", {}).get("contexts", []))
    result(want_checks <= got_checks,
           "all six CI checks required",
           f"missing: {sorted(want_checks - got_checks)}" if want_checks - got_checks else "")
    extra = got_checks - want_checks
    if extra:
        print(f"  \033[33mNOTE\033[0m  additional required checks present: {sorted(extra)}")

    result(prot.get("required_status_checks", {}).get("strict") is True,
           "branch must be up to date before merge")

    reviews = prot.get("required_pull_request_reviews") or {}
    result(bool(reviews), "pull request reviews required")
    result(reviews.get("required_approving_review_count") == 1,
           "exactly 1 approving review required",
           f"got {reviews.get('required_approving_review_count')}")
    result(reviews.get("require_code_owner_reviews") is True,
           "CODEOWNERS review required")
    result(reviews.get("dismiss_stale_reviews") is True,
           "a new push dismisses stale approvals")

    result((prot.get("allow_force_pushes") or {}).get("enabled") is False,
           "force pushes to main blocked")
    result((prot.get("allow_deletions") or {}).get("enabled") is False,
           "deleting main blocked")
    result((prot.get("required_linear_history") or {}).get("enabled") is True,
           "linear history required")
    result((prot.get("required_conversation_resolution") or {}).get("enabled") is True,
           "review threads must be resolved before merge")
    # Checked last because it is the one that decides whether any of the above
    # actually binds the person running this script.
    result((prot.get("enforce_admins") or {}).get("enabled") is True,
           "admins bound by protection too (enforce_admins)")

print()
if failures:
    print(f"\033[31m{failures} setting(s) do not match the intended configuration\033[0m")
    sys.exit(1)
print("\033[32mall repo settings match the intended configuration\033[0m")
PY
}

case "${1:-plan}" in
	plan)   cmd_plan ;;
	apply)  cmd_apply ;;
	verify) cmd_verify ;;
	*) die "unknown command: ${1}. Use plan | apply | verify" ;;
esac
