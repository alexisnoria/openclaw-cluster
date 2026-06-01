# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-06-01

### Added
- **Modular lib/** layout: the 1,288-line `openclaw-cluster.sh` is replaced by 8 specialized libraries
  - `lib/cluster.sh`   — pure helpers (validation, naming, target expansion, token safety)
  - `lib/logging.sh`   — `print_*` / `log_*` functions and color constants
  - `lib/ui.sh`        — `read_input` / `read_confirm` / `read_confirm_strong` / `section_header`
  - `lib/instance.sh`  — instance discovery, naming, port math, docker compose plumbing, `cluster_set_openrouter_key`, `cluster_set_telegram`
  - `lib/template.sh`  — config + compose generators: `gen_openclaw_json`, `gen_auth_profiles`, `gen_auth_state`, `gen_models_json`, `gen_instance_env`, `render_compose`
  - `lib/lifecycle.sh` — `cluster_init` / `_create_instance` / `cluster_start` / `cluster_stop` / `cluster_restart` / `cluster_update` / `cluster_scale`
  - `lib/status.sh`    — `cluster_status` / `cluster_logs` / `cluster_exec` / `cluster_tokens` / `cluster_dashboard`
  - `lib/config.sh`    — `cluster_config` (edit openclaw.json)
  - `lib/destroy.sh`   — `cluster_destroy` / `cluster_clean_all`
  - `lib/backup.sh`    — `cluster_backup` / `cluster_restore` (pure-FS)
  - `lib/menu.sh`      — `show_menu` (18-option interactive menu) + `run_interactive` (dispatch loop)
  - `lib/batch.sh`     — `run_batch` (non-interactive dispatcher) + `batch_usage`
  - `lib/main.sh`      — `main()` entry point: validates requirements, dispatches to menu or batch
- **New `bin/openclaw-cluster`** — canonical entry point. Sources all libs in order, exports config, calls `main`.
- **Integration test harness** — `scripts/test-integration.sh` + 6 bats files in `tests/integration/` (init, commands, ports, scale, backup, config) covering 42 end-to-end scenarios. Tests skip cleanly when Docker daemon is unavailable.
- **Golden file safety net** — `tests/golden/instance-1/` is the byte-for-byte reference output of `lib/template.sh` generators. `scripts/golden-snapshot.sh` regenerates them from a known-good openclaw-cluster.sh.
- **`_resolve_targets` / `_resolve_target_ids`** — extracted from `cluster_start` / `cluster_stop`, fixing a token-eating bug in `get_highest_instance_id`.

### Changed
- **`openclaw-cluster.sh` reduced from 1,288 → 8 lines** — now a 1-line shim that execs `bin/openclaw-cluster`. CLI behavior 100% preserved (`./openclaw-cluster.sh <cmd>` and `./bin/openclaw-cluster <cmd>` are equivalent).
- **`_update_instance_telegram` migrated from awk to jq** — single `jq` expression replaces three separate `awk` / `grep` / `sed` passes. Output is well-formed JSON regardless of existing structure. Idempotency verified by tests.

### Tests
- **Unit: 36 → 182 tests passing** (+146 across 13 bats files).
- **Integration: 42 scenarios** (init, commands, ports, scale, backup, config).
- shellcheck `--severity=warning` clean. shfmt clean. Backward compat verified end-to-end.

### Compatibility

All 18 batch commands (`init`, `start`, `stop`, `restart`, `status`, `logs`, `exec`, `config`, `destroy`, `clean`, `update`, `backup`, `restore`, `scale`, `tokens`, `dashboard`, `set-openrouter-key`, `set-telegram`) and the interactive menu behave identically to v1.1.0. `openclaw-cluster.sh` continues to work for legacy invocations.

## [1.1.0] - 2026-XX-XX

### Added
- GitHub Actions CI: shellcheck, shfmt, bats unit tests, project structure check (`.github/workflows/ci.yml`)
- Release workflow with GitHub Releases + GHCR multi-arch image publishing (`.github/workflows/release.yml`)
- `Makefile` with `lint`, `test`, `test-unit`, `test-integration`, `build`, `run`, `init`, `status`, `doctor`, `format`, `clean`, `tag` targets
- `scripts/lint.sh` — wrapper around shellcheck + shfmt with `doctor`, `clean`, `format` subcommands
- `scripts/test-unit.sh` — bats runner with auto-installer hint
- `lib/cluster.sh` — pure helpers extracted from `openclaw-cluster.sh` (no behavior change)
- `tests/bats/` — 36 unit tests covering validation, instance ports/naming, target expansion, token safety
- `CONTRIBUTING.md` with development workflow and compatibility policy
- `CODE_OF_CONDUCT.md` (Contributor Covenant v2.1)
- `SECURITY.md` with supported-versions table and disclosure policy
- `docs/ARCHITECTURE.md` with component diagram
- `docs/DEVELOPMENT.md` with local dev setup
- `docs/TROUBLESHOOTING.md` with common issues
- `VERSION` file (1.1.0) and `CHANGELOG.md`
- `.editorconfig`, `.shellcheckrc`, `.shfmt.conf`, `.vscode/` settings
- Issue templates (`bug_report.md`, `feature_request.md`) and PR template
- `CODEOWNERS` default reviewer configuration

### Changed
- `.gitignore` extended: editor/OS files, certs, coverage, `*.bak`/`*.tmp`
- `README.md` rewritten with badges, ToC, and links to docs/ (zero behavior change)

### Compatibility

`openclaw-cluster.sh` is **byte-identical** to v1.0. All 18 batch commands and the interactive menu behave exactly as before. `lib/cluster.sh` is new, additive, and unused by the script at this stage — it is the foundation for the v1.2.0 modular refactor.

## [1.0.0] - 2026-XX-XX

### Added
- Initial release: multi-instance Docker orchestrator for OpenClaw + Google Chrome
- 18 operations: init, start, stop, restart, status, logs, exec, config, destroy, clean, update, backup, restore, scale, tokens, dashboard, set-openrouter-key, set-telegram
- Interactive menu and batch CLI mode
- Multi-arch Docker image (amd64 + arm64)
- Per-instance isolation: network, ports, tokens, config, workspace, home
