#!/usr/bin/env bash
# Self-check for .github/workflows/pr-checks.yml: extracts the real step scripts and runs them
# against known-good and known-bad cases. Needs bun + python3 with PyYAML.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
python3 - "$root/.github/workflows/pr-checks.yml" <<'PY'
import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
def step(job, name):
    return next(s["run"] for s in w["jobs"][job]["steps"] if s.get("name") == name)
open("title.sh", "w").write(step("title", "Lint PR title with commitlint").replace(" --verbose", ""))
open("flow.sh", "w").write(step("flow", "Check source → target branch and linked issue"))
PY
fails=0
check() { [ "$1" = "$2" ] && echo "ok   $3" || { echo "FAIL $3 (got $1)"; fails=$((fails+1)); }; }
t() { TITLE="$1" SCOPES="$2" bash title.sh >/dev/null 2>&1 && r=pass || r=fail; check $r "$3" "title: $1"; }
f() { HEAD=$1 BASE=$2 BODY="$3" bash flow.sh >/dev/null 2>&1 && r=pass || r=fail; check $r "$4" "flow: $1 → $2"; }

t "docs: add PRD" "" pass
t "build(deps): bump the py group in /backend with 3 updates" "deps,deps-dev" pass
t "build(deps-dev): bump @types/bun from 1.4.2 to 1.4.3 in /web" "deps,deps-dev" pass
t "feat(api): add run listing endpoint" "api,web" pass
t "feat(nope): x" "api,web" fail
t "Added stuff" "" fail
t "style: reformat" "" fail
t "feat: Add Thing" "" fail
t "feat: $(printf 'x%.0s' {1..80})" "" fail
f fae/4-x dev "Closes #4" pass
f fae/4-x dev "Closes byfae-dev/project-fae#4" pass
f fae/4-x dev "no link" fail
f fae/22-x dev "Refs byfae-dev/project-fae#22" pass
f fae/22-x dev "Refs: #22" pass
f fae/22-x dev "see #22" fail
f fae/4-x main "Closes #4" fail
f dev staging "" pass
f staging dev "" pass
f dev main "" fail
f staging main "" pass
f hotfix/9-y main "Fixes #9" pass
f release-please--branches--main main "" pass
f random dev "" fail
f dependabot/uv/backend/fastapi-0.143.0 dev "" pass
f dependabot/bun/web/vite-8.4.0 main "" fail
f fae/5-y fae/4-x "" pass
exit $fails
