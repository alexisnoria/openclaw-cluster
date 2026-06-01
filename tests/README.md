# tests/

Tests for OpenClaw Cluster Manager, split into two suites.

## Layout

```
tests/
├── bats/                          # Unit tests — no Docker, fast
│   ├── helpers/load.bash
│   ├── validation.bats
│   ├── instance.bats
│   ├── targets.bats
│   └── safety.bats
└── integration/                   # Integration tests — need Docker daemon
    ├── helpers/setup.bash
    ├── init.bats                  # init creates correct layout & config
    ├── config.bats                # set-openrouter-key, set-telegram
    ├── commands.bats              # batch dispatcher + error paths
    ├── ports.bats                 # port allocation & network names
    ├── scale.bats                 # scale +N / -N
    └── backup.bats                # backup / restore round-trip
```

## Running

| Command | What it does | Speed | Needs |
|---|---|---|---|
| `make test-unit` | bats unit tests | < 5s | bats |
| `make test-integration` | bats integration tests | 30-90s | bats, docker |
| `make test` | both | < 2 min | all |
| `make lint` | shellcheck + shfmt | < 5s | shellcheck, shfmt |
| `make doctor` | project structure | < 1s | bash |

## Integration test rules

- Every test runs in an **isolated sandbox** (copy of the repo in `$TMPDIR`).
- `teardown()` removes the sandbox and stops any leftover containers.
- Tests that require the docker daemon **skip with a clear message** if docker isn't running.
- They are **not** part of `make test`; run them explicitly with `make test-integration` or in CI via `workflow_dispatch`.

## Phase 2 safety net

`tests/integration/` was created in PR #1 of Phase 2 to capture v1.1.0 behavior. **Every subsequent PR in Phase 2 must keep all these tests green.** A refactor that breaks them is a refactor that changes user-visible behavior.
