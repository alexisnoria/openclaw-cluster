# Development Guide

How to set up a dev environment, run the test suite, and iterate on the project.

## Prerequisites

| Tool | Version | macOS | Debian/Ubuntu |
|------|---------|-------|----------------|
| `bash` | ≥ 4.4 | `brew install bash` | `sudo apt install bash` |
| `docker` | ≥ 20.10 | Docker Desktop | `sudo apt install docker.io` |
| `make` | any | preinstalled | `sudo apt install make` |
| `shellcheck` | any | `brew install shellcheck` | `sudo apt install shellcheck` |
| `shfmt` | ≥ 3 | `brew install shfmt` | [shfmt releases](https://github.com/mvdan/sh/releases) |
| `bats` | ≥ 1.5 | `brew install bats-core` | `sudo apt install bats` |

Verify:

```bash
$ make doctor
✅ Estructura OK
```

## Day-to-day workflow

```bash
# 1. Pull latest
git pull --rebase

# 2. Create a branch
git checkout -b feat/my-change

# 3. Edit code

# 4. Format + lint + test
make format        # auto-fix shfmt drift
make lint          # shellcheck + shfmt check
make test-unit     # bats

# 5. Commit with a conventional message
git add -A
git commit -m "feat: add status --json output"

# 6. Push and open a PR
git push origin feat/my-change
gh pr create
```

## Adding a pure helper

Pure helpers (no Docker, no FS writes) belong in `lib/cluster.sh` and must be covered by a `bats` test.

Example: a helper that returns the next available instance id.

```bash
# In lib/cluster.sh
next_instance_id() {
  local current="$1"
  echo $(( current + 1 ))
}
```

```bash
# In tests/bats/instance.bats
load helpers/load

@test "next_instance_id increments" {
  result=$(next_instance_id 4)
  [ "$result" = "5" ]
}
```

Run:

```bash
make test-unit
```

## Adding a batch command

1. Implement the function in `openclaw-cluster.sh` (keep it stable; v1.x guarantees 100% compat).
2. Add a menu entry in `show_menu()` and a `case` arm in `run_batch`.
3. Document it in the README "Usage" section.
4. Add a `CHANGELOG.md` line under `[Unreleased]`.

## Writing integration tests (Docker-required)

`tests/integration/` is reserved for bats tests that need a real Docker daemon. They are **not** run in CI by default.

```bash
# tests/integration/init.bats
setup() {
  load '../bats/helpers/load'
  export TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
  ./openclaw-cluster.sh clean <<< "NUCLEAR"
}

@test "init creates one instance" {
  echo "1
$TAG
yes
yes
UTC
fake-key
openrouter/test/test
" | ./openclaw-cluster.sh init
  [ -d instances/instance-1 ]
}
```

Run with `make test-integration`.

## Debugging

- Trace the script: `bash -x openclaw-cluster.sh init 1`
- Tail logs of one instance: `./openclaw-cluster.sh logs 1` then answer `y` to follow.
- Drop into a running container: `./openclaw-cluster.sh exec 1 bash`
- Inspect config: `./openclaw-cluster.sh config 1`

## Releasing (maintainers)

1. Bump `VERSION` (e.g., `1.1.0` → `1.1.1`).
2. Move `[Unreleased]` content in `CHANGELOG.md` to a dated `[X.Y.Z] - YYYY-MM-DD` section.
3. Commit: `git commit -am "chore: release vX.Y.Z"`.
4. Tag: `make tag` (uses GPG-signed annotated tag).
5. Push: `git push origin main --follow-tags`.
6. The `.github/workflows/release.yml` workflow creates a GitHub Release and pushes multi-arch images to GHCR.

## Pre-release checklist

- [ ] `make lint` and `make test-unit` are green locally
- [ ] CI is green on the commit you'll tag
- [ ] `make doctor` is green
- [ ] `CHANGELOG.md` has the new version with a date
- [ ] `VERSION` is bumped
- [ ] `openclaw-cluster.sh` is byte-identical to the previous release **OR** the diff is documented
