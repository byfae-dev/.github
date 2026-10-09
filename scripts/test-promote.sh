#!/usr/bin/env bash
# Self-check for .github/workflows/promote.yml: extracts the real "Decide what to merge" step and
# runs it against a throwaway repo through a release cycle. Needs git + python3 with PyYAML.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
python3 - "$root/.github/workflows/promote.yml" <<'PY'
import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
job = w["jobs"]["promote"]
# The checkout reads the repo with Actions' own token: without contents: read a private repo is
# "not found" (it was, on the first live run).
assert (job.get("permissions") or {}).get("contents") == "read", "promote needs contents: read"
for name, file in (("Decide what to merge", "decide.sh"), ("Open the PR and merge it when green", "merge.sh"),
                   ("Keep staging → main open for the board", "main.sh")):
    open(file, "w").write(next(s["run"] for s in job["steps"] if s.get("name") == name))
PY
[ -f decide.sh ] || { echo "FAIL the workflow's permissions"; exit 1; }
export RUNNER_TEMP=$tmp GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare origin.git && git clone -q origin.git work 2>/dev/null && cd work
git switch -q -c main && echo 0.1.0 > version.txt && git add . && git commit -qm "chore: start"
git branch staging && git branch dev && git push -q origin main staging dev
fails=0
# decide PUSHED → "head→base method ci title", or "nothing"
decide() {
  git push -q origin dev staging main 2>/dev/null; : > "$tmp/out"
  ( cd "$tmp/work" && git fetch -q origin && PUSHED=$1 GITHUB_OUTPUT="$tmp/out" bash "$tmp/decide.sh" ) || { echo "error"; return; }
  if [ -s "$tmp/out" ]; then
    # shellcheck disable=SC1090
    . <(sed 's/^\([a-z]*\)=\(.*\)$/\1="\2"/' "$tmp/out")
    echo "$head→$base $method ci=$ci $title"
  else echo nothing; fi
}
check() { [ "$1" = "$2" ] && echo "ok   $3" || { echo "FAIL $3"; echo "     got:  $1"; echo "     want: $2"; fails=$((fails+1)); }; }
on() { git switch -q "$1"; }
work() { on dev; echo "$1" >> notes.txt; git add .; git commit -qm "feat: $1"; }

check "$(decide dev)" nothing "equal branches: a push to dev needs nothing"
work one
check "$(decide dev)" "dev→staging merge ci=false chore: promote dev to staging" "work on dev is promoted"
grep -q -- "- feat: one" "$tmp/body.md"; check $? 0 "the promotion lists the work"
on staging; git merge -q --no-ff -m "chore: promote dev to staging (#1)" dev
check "$(decide staging)" nothing "a promotion merged into staging is not merged back"
work two
check "$(decide staging)" nothing "dev moving on meanwhile doesn't trigger a back-merge either"
on main; git merge -q --no-ff -m "chore: promote staging to main (#2)" staging
check "$(decide main)" nothing "the board's staging → main needs nothing back"
echo 0.2.0 > version.txt; git commit -qam "chore: release 0.2.0 (#3)"
check "$(decide main)" "main→staging merge ci=false chore: back-merge main into staging after v0.2.0" "a release is back-merged into staging"
on staging; git merge -q --no-ff -m "chore: back-merge main into staging after v0.2.0 (#4)" main
check "$(decide staging)" "staging→dev squash ci=false chore: back-merge staging into dev after v0.2.0" "then into dev, squashed"
on dev; git merge -q --squash staging >/dev/null 2>&1 && git commit -qm "chore: back-merge staging into dev after v0.2.0 (#5)"
check "$(decide dev)" "dev→staging merge ci=false chore: promote dev to staging" "after the squash, only the unpromoted work is promoted"
grep -q -- "- feat: two" "$tmp/body.md"; check $? 0 "…and listed"
on staging; git merge -q --no-ff -m "chore: promote dev to staging (#6)" dev
check "$(decide dev)" nothing "the squash back into dev never starts an empty promotion"
on dev; mkdir -p .github/workflows; echo "name: x" > .github/workflows/x.yml; git add .; git commit -qm "ci: a workflow"
check "$(decide dev)" "dev→staging merge ci=true chore: promote dev to staging" "a CI change is marked for the board"
grep -q "the board merges it" "$tmp/body.md"; check $? 0 "…and its body says so"
check "$(decide fae/9-x)" nothing "pushes to other branches need nothing"
# A second release while dev has nothing new: the squash back into dev must not promote.
on staging; git merge -q --no-ff -m "chore: promote dev to staging (#7)" dev
on main; git merge -q --no-ff -m "chore: promote staging to main (#8)" staging
echo 0.3.0 > version.txt; git commit -qam "chore: release 0.3.0 (#9)"
on staging; git merge -q --no-ff -m "chore: back-merge main into staging after v0.3.0 (#10)" main
on dev; git merge -q --squash staging >/dev/null 2>&1 && git commit -qm "chore: back-merge staging into dev after v0.3.0 (#11)"
check "$(decide dev)" nothing "a release back-merged into a quiet dev starts no promotion"

# The merge step, against a fake gh: it plays back the PR's head commit and its required checks
# (one line per read) and records merges. `sleep` returns at once.
mkdir -p "$tmp/bin"; printf '#!/bin/sh\n' > "$tmp/bin/sleep"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
next() { local n; n=$(cat "$FAKE/$1.n" 2>/dev/null || echo 1); sed -n "${n}p" "$FAKE/$1"; echo $((n + 1)) > "$FAKE/$1.n"; }
case "$1 $2" in
  "pr list") cat "$FAKE/open" 2>/dev/null || true ;;
  "pr create") echo "create ${*:3}" >> "$FAKE/calls"; echo "https://github.com/o/r/pull/7" ;;
  "pr edit") echo "edit ${*:3}" >> "$FAKE/calls"; cp "${@: -1}" "$FAKE/body" 2>/dev/null ;;
  "pr view")
    sha=$(next shas)
    if [[ " $* " == *mergeable* ]]; then echo "$sha $(next mergeable)"; else echo "$sha"; fi ;;
  "pr checks")
    line=$(next checks)
    case "$line" in
      ERR*) echo "GraphQL: Resource not accessible by integration" >&2; exit 1 ;;
      NONE) echo "no required checks reported on the 'dev' branch" >&2; exit 1 ;;
      *) echo "$line" ;;
    esac ;;
  "pr merge") echo "${*:3}" >> "$FAKE/merged" ;;
esac
GH
chmod +x "$tmp/bin/gh" "$tmp/bin/sleep"
# merge CI SHAS CHECKS [MERGEABLE] → what the step merged, or "nothing"; "error" when it failed
merge() {
  export FAKE="$tmp/fake"; rm -rf "$FAKE"; mkdir -p "$FAKE"
  printf '%b' "$2" > "$FAKE/shas"; printf '%b' "$3" > "$FAKE/checks"; printf '%b' "${4:-}" > "$FAKE/mergeable"
  echo body > "$tmp/body.md"
  PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=o/r HEAD=dev BASE=staging METHOD=merge TITLE=t CI=$1 \
    POLL_SECONDS=600 bash "$tmp/merge.sh" >/dev/null 2>&1 || { echo error; return; }
  cat "$FAKE/merged" 2>/dev/null || echo nothing
}
check "$(merge false 'a\na\na\na\n' 'pending pass\npass pass\n')" \
  "7 --repo o/r --admin --merge --match-head-commit a" "green required checks: merged, that commit only"
check "$(merge false 'a\na\n' 'pass fail\n')" nothing "a red required check: left for the board"
check "$(merge false 'a\na\n' 'pass cancel\n')" nothing "a cancelled one too"
check "$(merge true 'a\na\n' 'pass pass\n')" nothing "a CI change: left for the board"
check "$(merge false 'a\nb\nb\nb\n' 'pass pass\npass pass\n')" \
  "7 --repo o/r --admin --merge --match-head-commit b" "a push while it checked: only the new head is merged"
check "$(merge false 'a\na\na\na\n' '\n\n')" nothing "no checks reported in 20 minutes: left for the board"
check "$(merge false 'a\na\na\na\n' 'pending pass\npending pass\n')" nothing "checks still running after 20 minutes: left for the board"
check "$(merge false 'a\na\n' 'pass pass\n' 'CONFLICTING\n')" nothing "a conflict: left for the board"
grep -q "Conflicts with \`staging\`" "$tmp/fake/body"; check $? 0 "…and the PR says so"
check "$(merge false 'a\na\n' 'ERR\n')" error "checks GitHub won't show: the run fails, no waiting"
check "$(merge false 'a\na\na\na\n' 'NONE\npass pass\n')" \
  "7 --repo o/r --admin --merge --match-head-commit a" "checks not reported yet: it waits, then merges"

# staging → main is opened and kept up to date for the board, never merged.
main_pr() {
  export FAKE="$tmp/fake"; rm -rf "$FAKE"; mkdir -p "$FAKE"; printf '%s' "${1:-}" > "$FAKE/open"
  git push -q origin dev staging main 2>/dev/null
  ( cd "$tmp/work" && git fetch -q origin && PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=o/r bash "$tmp/main.sh" ) >/dev/null 2>&1 || { echo error; return; }
  cut -d' ' -f1 "$FAKE/calls" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true
  [ -s "$FAKE/calls" ] || echo nothing
}
on staging
check "$(main_pr)" nothing "staging equal to main: no promotion to main"
work three; on staging; git merge -q --no-ff -m "chore: promote dev to staging (#12)" dev
check "$(main_pr)" create "staging ahead of main: a PR for the board"
grep -q -- "- feat: three" "$tmp/fake/body" 2>/dev/null || grep -q -- "- feat: three" "$tmp/main.md"; check $? 0 "…listing what main lacks"
check "$(main_pr 13)" edit "an open one is kept up to date, not doubled"
grep -q "never merged" "$RUNNER_TEMP/main.md"; check $? 0 "…and never merged by the app"
grep -q -- "--admin\|pr merge" "$tmp/main.sh"; check $? 1 "the staging → main step can't merge"

[ "$fails" -eq 0 ] && echo "all promote checks pass" || { echo "$fails failing"; exit 1; }
