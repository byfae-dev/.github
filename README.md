# By Fae — org defaults

Shared by every repository in `byfae-dev`. The standards these files enforce live in the brain: `30-knowledge/engineering/` (code-style, git-workflow, testing, security).

## Contents

| Path | What |
|---|---|
| `.github/workflows/pr-checks.yml` | Reusable PR checks: Conventional Commit title (commitlint), branch flow, linked issue on work PRs (`Closes #N` or `Refs #N`) |
| `.github/workflows/python-ci.yml` | Reusable Python CI: ruff format + lint, pyright, vulture, pytest, diff coverage ≥ 80 % |
| `.github/workflows/ts-ci.yml` | Reusable TypeScript CI on Bun: Biome, tsc, knip, `bun test`, diff coverage ≥ 80 %, build |
| `.github/workflows/promote.yml` | Reusable promotions and back-merges: on a push to `dev`, `staging` or `main` it opens the PR that push calls for (`dev → staging`; after a release or hotfix `main → staging`, then `staging → dev`) waits for its required checks and, when every one passed, merges that commit as the `byfae-release` app, whose bypass takes it past the required review. Red, cancelled or still running after 20 minutes, a conflict, or a change to `.github/workflows/` leave it for the board, the PR saying why; checks it can't read fail the run. A `staging → main` PR is kept open and up to date for the board, never merged by it; releases stay the board's |
| `.github/workflows/pr.yml`, `promote-self.yml` | Run `pr-checks` and `promote` on this repo itself |
| `.github/dependabot.yml` | Weekly action updates for this repo |
| `PULL_REQUEST_TEMPLATE.md`, `ISSUE_TEMPLATE/` | Org-wide defaults for repos without their own; the shapes they start from are defined in the brain (`commit-and-pr`, agent brief) |
| `labels.txt`, `scripts/sync-labels.sh` | Workflow labels and the script that applies them |
| `scripts/test-pr-checks.sh` | Self-check for `pr-checks.yml` — run it after changing that workflow (needs Bun) |
| `scripts/test-promote.sh` | Self-check for `promote.yml`: its decision through release cycles in a throwaway repo, its merge and `staging → main` steps against a fake `gh` — run it after changing that workflow |

## Using the workflows

```yaml
# .github/workflows/pr.yml in a repo
name: pr
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
# No cancel-in-progress: a PR edit and push can arrive together (release-please does both);
# a cancelled run counts as a failing required check. These checks take seconds.
jobs:
  checks:
    uses: byfae-dev/.github/.github/workflows/pr-checks.yml@main
    with:
      scopes: api,web,deps,deps-dev   # optional; include deps,deps-dev for Dependabot
```

```yaml
# .github/workflows/ci.yml in a repo
name: ci
on:
  pull_request:
  push:
    branches: [dev, staging, main]
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  backend:
    uses: byfae-dev/.github/.github/workflows/python-ci.yml@main
    with:
      working-directory: backend
  web:
    uses: byfae-dev/.github/.github/workflows/ts-ci.yml@main
    with:
      working-directory: web
```

```yaml
# .github/workflows/promote.yml in a repo
name: promote
on:
  push:
    branches: [dev, staging, main]
jobs:
  promote:
    uses: byfae-dev/.github/.github/workflows/promote.yml@main
    secrets: inherit # BYFAE_RELEASE_KEY (org secret); BYFAE_RELEASE_CLIENT_ID is an org variable
```

**Requirements of a calling project**
- Python: `uv.lock`; dev dependencies ruff, pyright, vulture, pytest, pytest-cov (`--cov-report=xml`), diff-cover; `[tool.vulture]` paths configured.
- Promotions: the repo is among the org secret's and variable's repositories, `byfae-release` is installed on it and a bypass actor (pull requests only) on its three branch rulesets. The app's permissions: contents and pull requests write; checks, commit statuses and actions read (to see a PR's checks); metadata read.
- TypeScript (Bun): `bun.lock`; `"packageManager": "bun@x.y.z"` in `package.json` (CI installs that exact Bun); scripts `check` (Biome), `typecheck`, `knip`, `coverage` (`bun test --coverage` with the `lcov` reporter) and `build`.

## Rules for changing this repo

- Callers pin `@main`: a change reaches other repos only after `dev → staging → main`.
- Actions are pinned to commit SHAs with the version as a comment; Dependabot proposes updates.
- Untrusted values (PR titles, bodies, branch names) are passed via `env`, never interpolated into scripts.
- Every job has `timeout-minutes`; checkouts use `persist-credentials: false`.
