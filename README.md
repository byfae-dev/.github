# By Fae — org defaults

Shared by every repository in `byfae-dev`. The standards these files enforce live in the brain: `30-knowledge/engineering/` (code-style, git-workflow, testing, security).

## Contents

| Path | What |
|---|---|
| `.github/workflows/pr-checks.yml` | Reusable PR checks: Conventional Commit title (commitlint), branch flow, linked issue on work PRs (`Closes #N` or `Refs #N`) |
| `.github/workflows/python-ci.yml` | Reusable Python CI: ruff format + lint, pyright, vulture, pytest, diff coverage ≥ 80 % |
| `.github/workflows/ts-ci.yml` | Reusable TypeScript CI on Bun: Biome, tsc, knip, `bun test`, diff coverage ≥ 80 %, build |
| `.github/workflows/pr.yml` | Runs `pr-checks` on this repo's own PRs |
| `.github/dependabot.yml` | Weekly action updates for this repo |
| `PULL_REQUEST_TEMPLATE.md`, `ISSUE_TEMPLATE/` | Org-wide defaults for repos without their own |
| `labels.txt`, `scripts/sync-labels.sh` | Workflow labels and the script that applies them |
| `scripts/test-pr-checks.sh` | Self-check for `pr-checks.yml` — run it after changing that workflow (needs Bun) |

## Using the workflows

```yaml
# .github/workflows/pr.yml in a repo
name: pr
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
concurrency:
  group: pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true
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

**Requirements of a calling project**
- Python: `uv.lock`; dev dependencies ruff, pyright, vulture, pytest, pytest-cov (`--cov-report=xml`), diff-cover; `[tool.vulture]` paths configured.
- TypeScript (Bun): `bun.lock`; `"packageManager": "bun@x.y.z"` in `package.json` (CI installs that exact Bun); scripts `check` (Biome), `typecheck`, `knip`, `coverage` (`bun test --coverage` with the `lcov` reporter) and `build`.

## Rules for changing this repo

- Callers pin `@main`: a change reaches other repos only after `dev → staging → main`.
- Actions are pinned to commit SHAs with the version as a comment; Dependabot proposes updates.
- Untrusted values (PR titles, bodies, branch names) are passed via `env`, never interpolated into scripts.
- Every job has `timeout-minutes`; checkouts use `persist-credentials: false`.
