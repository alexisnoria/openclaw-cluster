# Contributing to OpenClaw Cluster Manager

Thanks for your interest in contributing! This document explains how to set up a development environment, run the test suite, and submit a pull request.

## Code of Conduct

This project follows the [Contributor Covenant v2.1](CODE_OF_CONDUCT.md). By participating, you agree to its terms.

## Compatibility policy

> **100% backward compatible.**
>
> Every change in `openclaw-cluster.sh` must preserve the public CLI (18 batch commands + interactive menu). The `lib/cluster.sh` module is allowed to evolve freely as long as no behavior changes.

If your PR needs to break compatibility, the PR description must explain why and provide a migration path. The maintainer reserves the right to reject breaking changes for releases in the `1.x` line.

## Development setup

You need:

- `bash` 4.4+ (macOS users: `brew install bash`)
- `docker` and `docker compose`
- `shellcheck` (lint)
- `shfmt` (format)
- `bats` (tests)
- `make`

```bash
# macOS
brew install shellcheck shfmt bats-core make

# Debian/Ubuntu
sudo apt install shellcheck bats make
# shfmt: see https://github.com/mvdan/sh#shfmt
```

Clone and verify:

```bash
git clone https://github.com/<your-user>/openclaw-cluster.git
cd openclaw-cluster
make doctor         # verifies required files exist
make lint           # shellcheck + shfmt
make test-unit      # bats
```

If `make doctor` complains, re-read the **Definition of Done** below.

## Running tests

| Command | What it does | Speed |
|---|---|---|
| `make test-unit` | Pure bash unit tests (no Docker) | < 5s |
| `make test-integration` | bats tests with real Docker (manual) | minutes |
| `make lint` | shellcheck + shfmt | < 5s |
| `make format` | Auto-format with shfmt | < 5s |
| `make doctor` | Verify project structure | < 1s |

CI runs `lint` + `unit` on every push and PR. Integration tests only run on `workflow_dispatch` to keep CI fast.

## Project layout

```
.
├── openclaw-cluster.sh         # Main script (stable API)
├── lib/cluster.sh              # Pure helpers extracted for testability
├── tests/bats/                 # Unit tests
├── scripts/                    # lint.sh, test-unit.sh
├── docs/                       # ARCHITECTURE, DEVELOPMENT, TROUBLESHOOTING
├── .github/                    # Workflows, templates, CODEOWNERS
├── Dockerfile.openclaw-chrome
├── docker-compose.template.yml
└── .env.example
```

## Workflow for a change

1. **Branch off `main`**: `git checkout -b feat/short-description`
2. **Write tests first** when adding new pure functions: add to `lib/cluster.sh` + `tests/bats/*.bats`
3. **Run the local gates**:
   ```bash
   make format
   make lint
   make test-unit
   ```
4. **Commit** with [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat: add status --json output`
   - `fix: scale -N handles zero gracefully`
   - `docs: clarify Telegram dmPolicy values`
   - `chore: bump shellcheck action to v3`
5. **Update CHANGELOG.md** under `[Unreleased]` in the appropriate section.
6. **Push and open a PR** using the provided template.
7. Wait for CI green and a review. A maintainer will merge.

## Style guide

- 2-space indent, LF line endings (see `.editorconfig`)
- shfmt compliance enforced in CI (`.shfmt.conf`)
- shellcheck must pass with at most `warning` severity
- All new shell files must start with `#!/usr/bin/env bash` + `set -euo pipefail`
- Functions in `lib/*.sh` must be **pure** (no Docker, no FS writes, no global state beyond safe defaults)
- Comments only when the why is non-obvious

## Definition of Done for a release

- [ ] `make lint` and `make test-unit` pass in CI
- [ ] `make doctor` passes
- [ ] `CHANGELOG.md` has a dated section for the new version
- [ ] `VERSION` bumped per semver
- [ ] `docs/` updated if behavior changed
- [ ] Tagged as `vX.Y.Z` (the release workflow handles GitHub Release + GHCR push)
- [ ] `openclaw-cluster.sh` byte-identical **OR** diff explained in PR

## Reporting security issues

Please do **not** open a public issue. See [SECURITY.md](SECURITY.md) for the disclosure process.

## License

By contributing, you agree that your contributions are licensed under the MIT License (see [LICENSE](LICENSE)).
