#!/usr/bin/env bash
#
# Stamps a Web export with the commit it was built from.
#
# Why: when a PR preview is replaced in place, a tester who already has the
# page open — or a cached copy — cannot tell whether they are playing the new
# build or the old one. The stamp makes that answerable at a glance, and gives
# testers something exact to quote when reporting what they saw.
#
# Usage: .github/stamp-build.sh <build-dir> <label> <full-sha>

set -Eeuo pipefail

BUILD_DIR="${1:?build dir required}"
LABEL="${2:?label required}"        # e.g. "main" or "PR #12"
SHA="${3:?commit sha required}"
SHORT="${SHA:0:7}"
BUILT_AT="$(date -u +'%Y-%m-%d %H:%MZ')"

INDEX="${BUILD_DIR}/index.html"
[[ -f "${INDEX}" ]] || { echo "no index.html in ${BUILD_DIR}" >&2; exit 1; }

# Machine-readable, for anyone who wants to check without squinting.
cat > "${BUILD_DIR}/build-info.json" <<JSON
{
  "label": "${LABEL}",
  "commit": "${SHA}",
  "short": "${SHORT}",
  "built_at": "${BUILT_AT}"
}
JSON

# Human-readable badge. pointer-events:none so it can never intercept a tap —
# the game is a one-tap game and the badge must not steal that tap.
BADGE="<div id=\"build-stamp\" style=\"position:fixed;right:6px;bottom:5px;z-index:2147483647;pointer-events:none;font:11px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace;color:#8b8a87;background:rgba(20,20,20,.72);padding:2px 7px;border-radius:3px;letter-spacing:.04em\">${LABEL} &middot; ${SHORT} &middot; ${BUILT_AT}</div>"

if grep -q '</body>' "${INDEX}"; then
	python3 - "${INDEX}" "${BADGE}" <<'PY'
import sys, pathlib
path, badge = sys.argv[1], sys.argv[2]
p = pathlib.Path(path)
html = p.read_text()
# Inject before the LAST </body>, so a </body> inside a script string cannot
# be mistaken for the document's own closing tag.
head, sep, tail = html.rpartition('</body>')
p.write_text(head + badge + '\n\t' + sep + tail)
PY
	echo "stamped ${INDEX}: ${LABEL} ${SHORT} ${BUILT_AT}"
else
	echo "::warning::no </body> in ${INDEX}; wrote build-info.json but no badge"
fi
