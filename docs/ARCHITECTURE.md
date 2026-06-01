# Architecture

OpenClaw Cluster Manager is a single-host, multi-instance Docker orchestrator. It manages N isolated OpenClaw gateways on one machine, each with its own ports, network, tokens, and persistent volumes.

## High-level diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  Host (your laptop / server)                                     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  bin/openclaw-cluster   (canonical entry point)            │  │
│  │     │                                                      │  │
│  │     ├─▶ openclaw-cluster.sh  (1-line shim, backward compat)│  │
│  │     │                                                      │  │
│  │     └─▶ lib/  (sourced in order)                           │  │
│  │          ├── cluster.sh    (validate_*, naming, paths)      │  │
│  │          ├── logging.sh    (print_*, log_*, colors)        │  │
│  │          ├── ui.sh         (read_input, read_confirm)      │  │
│  │          ├── instance.sh   (instance_*, set_openrouter,     │  │
│  │          │                 set_telegram)                    │  │
│  │          ├── template.sh   (gen_*, render_compose)         │  │
│  │          ├── lifecycle.sh  (init/start/stop/restart/      │  │
│  │          │                 update/scale)                   │  │
│  │          ├── status.sh     (status/logs/exec/tokens/      │  │
│  │          │                 dashboard)                      │  │
│  │          ├── config.sh     (edit openclaw.json)            │  │
│  │          ├── destroy.sh    (destroy, clean_all)            │  │
│  │          ├── backup.sh     (backup, restore)               │  │
│  │          ├── menu.sh       (show_menu, run_interactive)    │  │
│  │          ├── batch.sh      (run_batch, batch_usage)        │  │
│  │          └── main.sh       (main entry point)              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              │ docker compose -f                 │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  instances/instance-1/                                      │  │
│  │  ├── docker-compose.yml   (rendered from template)          │  │
│  │  ├── config/openclaw.json                                   │  │
│  │  ├── config/agents/main/agent/auth-profiles.json            │  │
│  │  ├── workspace/                                              │  │
│  │  ├── home/         (Playwright caches)                       │  │
│  │  └── .env          (per-instance token, gitignored)         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  instances/instance-2/   (isolated, same shape as #1)      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  instances/instance-N/                                      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Each instance has:                                               │
│    • Bridge network  oc-net-N   (isolated)                        │
│    • Host port       18000 + N*22  (gateway)                      │
│    • Host port       18000 + N*22 + 1 (bridge)                    │
│    • Container       instance-N-gateway   (always running)        │
│    • Container       instance-N-cli       (profile: cli)          │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  backups/  (tar.gz, gitignored)                             │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Components

### `bin/openclaw-cluster` — entry point

The canonical entry point. It:

1. Resolves the repo root from `BASH_SOURCE[0]`.
2. Exports cluster-wide config (`CLUSTER_DIR`, `INSTANCES_DIR`, `TEMPLATE_FILE`, `DOCKERFILE`, `IMAGE_NAME`, `BASE_PORT`).
3. Sources every `lib/*.sh` in alphabetical order (each lib guards against double-source via `__LIB_*_SOURCED`).
4. Calls `main "$@"`.

`openclaw-cluster.sh` at the repo root is a 1-line shim that `exec`s this binary, preserving backward compatibility with existing invocations.

### `lib/*.sh` — modular libraries

Each lib is self-contained, idempotent (re-source safe), and declares its own dependencies at the top. The libs form a clean dependency DAG:

```
       ┌────────────┐
       │ cluster.sh │  (leaf: pure functions, no I/O)
       └─────┬──────┘
             │ foundation for everyone
   ┌─────────┼─────────┬──────────┬──────────┐
   ▼         ▼         ▼          ▼          ▼
 logging   ui.sh   instance  template   (no deps:
 .sh                .sh       .sh         destroy,
   │                 │         │          backup,
   │                 ▼         │          status,
   └────────────►    ├────◄────┘          config,
                     │                   lifecycle)
                     ▼
              (lifecycle/status/config/destroy/backup
               use all of cluster/logging/ui/instance/template)
```

### Per-lib responsibilities

| Lib | Responsibility | Testable in bats |
| --- | --- | --- |
| `cluster.sh` | `validate_number`, `validate_range`, `validate_yes`, instance naming, port math, `expand_targets`, `is_safe_token`, `safe_path_component` | yes (pure) |
| `logging.sh` | `print_success` / `print_info` / `print_warn` / `print_error` / `print_cmd` + `log_*` + color constants | yes (string output) |
| `ui.sh` | `read_input` / `read_confirm` / `read_confirm_strong` / `section_header` | yes (stubbed stdin) |
| `instance.sh` | `instance_*`, `generate_token`, `require_command`, `check_docker`, `instance_compose`, `cluster_set_openrouter_key`, `cluster_set_telegram` | yes (pure helpers) |
| `template.sh` | `gen_openclaw_json` / `gen_auth_profiles` / `gen_auth_state` / `gen_models_json` / `gen_instance_env` / `render_compose` | yes (golden files) |
| `lifecycle.sh` | `cluster_init`, `_create_instance`, `cluster_start/stop/restart`, `cluster_update`, `cluster_scale` | yes (init is pure FS) |
| `status.sh` | `cluster_status`, `cluster_logs`, `cluster_exec`, `cluster_tokens`, `cluster_dashboard` | partial (table render) |
| `config.sh` | `cluster_config` | yes (file existence) |
| `destroy.sh` | `cluster_destroy`, `cluster_clean_all` | partial (errors) |
| `backup.sh` | `cluster_backup`, `cluster_restore` | yes (pure FS) |
| `menu.sh` | `show_menu`, `run_interactive` | yes (rendering) |
| `batch.sh` | `run_batch`, `batch_usage` | yes (dispatch table) |
| `main.sh` | `main()` | integration only |

The entry point runs in two modes: **interactive menu** (no args) and **batch** (first arg = command). The 18 batch commands are:

- `init` — build image, create N instances
- `start` / `stop` / `restart` — Docker compose lifecycle
- `status` — formatted table
- `logs` — `docker compose logs`
- `exec` — `docker compose exec`
- `config` — edit `openclaw.json` in `$EDITOR`
- `destroy` / `clean` — teardown with typed confirmation
- `update` — rebuild + recreate
- `backup` / `restore` — tar.gz snapshot of an instance
- `scale` — add/remove instances
- `tokens` / `dashboard` — show / open gateway URL
- `set-openrouter-key` / `set-telegram` — live config update

### `lib/cluster.sh` — pure helpers

The foundation library. Pure functions only, no I/O:

- `validate_number`, `validate_range`, `validate_yes`
- `instance_gateway_port`, `instance_bridge_port`, `instance_name`, `instance_dir`
- `expand_targets` (handles `all | range:N-M | N`)
- `is_safe_token`, `safe_path_component`

### `Dockerfile.openclaw-chrome`

Multi-stage-ready single-stage Dockerfile that:

1. Pulls `ghcr.io/openclaw/openclaw:<tag>` as base
2. Installs Google Chrome stable (with Chromium fallback on arm64)
3. Pre-creates `~/.cache/ms-playwright` for the `node` user
4. Sets `OPENCLAW_BROWSER_EXECUTABLE_PATH=/usr/bin/google-chrome`

### `docker-compose.template.yml`

Two services per instance:

- `openclaw-gateway` — long-running, exposes `18789` and `18790`
- `openclaw-cli` — `network_mode: service:openclaw-gateway` (shares net ns), `cap_drop: [NET_RAW, NET_ADMIN]`, `security_opt: no-new-privileges`, profile `cli` (only brought up with `--profile cli`)

Variables replaced by `sed` at instance creation time: `{{INSTANCE_ID}}`, `{{INSTANCE_NAME}}`, `{{GATEWAY_PORT}}`, `{{BRIDGE_PORT}}`, `{{NETWORK_NAME}}`, `{{CONFIG_DIR}}`, `{{WORKSPACE_DIR}}`, `{{HOME_DIR}}`, `{{GATEWAY_TOKEN}}`, `{{TZ}}`, `{{BROWSER_HEADLESS}}`.

## Port assignment

| Instance | Gateway | Bridge |
|----------|---------|--------|
| 1        | 18022   | 18023  |
| 2        | 18044   | 18045  |
| 3        | 18066   | 18067  |
| N        | 18000 + N×22 | 18000 + N×22 + 1 |

Stride of 22 leaves room for future per-instance aux ports.

## Security model

- **Per-instance auth token** (`openssl rand -hex 32`) — required by `openclaw-gateway`
- **Capability dropping** on the `openclaw-cli` service (`NET_RAW`, `NET_ADMIN`)
- **`no-new-privileges`** security opt on the CLI
- **Bind to `lan`** (configurable per gateway) — change to `127.0.0.1` for local-only
- **No secrets in git** — `.env` and `instances/` are gitignored
- **Typed confirmation** for destructive ops (`DESTRUIR-instance-N`, `NUCLEAR`)
- **Defaults to safe Telegram policy** (`pairing`)

## Lifecycle

```
   init
    │  build image
    │  create N instances (config, env, compose)
    ▼
  start ──────► running
  stop  ──────► stopped
  restart ────► running
  backup ─────► backups/instance-N_TIMESTAMP.tar.gz
  restore ────► instance recreated with new token
  update ─────► image rebuilt, all instances recreated
  destroy ────► instance removed (data optionally preserved)
  scale ±N ───► instances added/removed
  clean ──────► NUCLEAR: everything wiped
```

## What lives where

| Path | Gitignored | Purpose |
|------|------------|---------|
| `bin/openclaw-cluster` | no | Canonical entry point |
| `openclaw-cluster.sh` | no | 1-line shim (backward compat) |
| `lib/*.sh` | no | Modular libraries (13 files) |
| `scripts/*.sh` | no | Lint, test, golden-snapshot helpers |
| `tests/bats/` | no | Unit tests (182 across 14 files) |
| `tests/integration/` | no | End-to-end tests (42 across 6 files) |
| `tests/golden/` | no | Byte-for-byte reference output |
| `Dockerfile.openclaw-chrome` | no | Image recipe |
| `docker-compose.template.yml` | no | Compose template |
| `.env.example` | no | Sample env vars |
| `.env` | **yes** | Local secrets (created by `init`) |
| `instances/` | **yes** | Per-instance data |
| `backups/` | **yes** | tar.gz snapshots |
