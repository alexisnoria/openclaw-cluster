# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
