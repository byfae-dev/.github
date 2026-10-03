# By Fae — org defaults

Shared by every repo in `byfae-dev`. Standards live in the brain: `30-knowledge/engineering/`.

| Path | What |
|---|---|
| `.github/workflows/pr-checks.yml` | Reusable PR checks: Conventional Commit title (commitlint), branch flow, linked issue |
| `.github/workflows/python-ci.yml` | Reusable Python CI: ruff, pyright, vulture, pytest, diff coverage ≥ 80 % |
| `.github/workflows/ts-ci.yml` | Reusable TypeScript CI: Biome, tsc, knip, Vitest, diff coverage ≥ 80 %, build |
| `PULL_REQUEST_TEMPLATE.md`, `ISSUE_TEMPLATE/` | Org-wide defaults (apply to repos without their own) |
| `labels.txt` + `scripts/sync-labels.sh` | Workflow labels |

## Using the PR checks

```yaml
# .github/workflows/pr.yml in a repo
name: pr
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
jobs:
  checks:
    uses: byfae-dev/.github/.github/workflows/pr-checks.yml@main
    with:
      scopes: api,orchestrator,web   # optional
```

Callers pin `@main`: changes here reach other repos only after `dev → staging → main`.

## Using the CI workflows

```yaml
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

Python projects need `uv.lock`, ruff/pyright/vulture/pytest(-cov, `--cov-report=xml`)/diff-cover as dev dependencies. TS projects need `package-lock.json`, Biome, knip and Vitest with the `cobertura` coverage reporter.
