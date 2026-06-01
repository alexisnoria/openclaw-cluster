# Architecture

OpenClaw Cluster Manager is a single-host, multi-instance Docker orchestrator. It manages N isolated OpenClaw gateways on one machine, each with its own ports, network, tokens, and persistent volumes.

## High-level diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  Host (your laptop / server)                                     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  openclaw-cluster.sh  (orchestrator, single source of truth)│  │
│  │  ├── lib/cluster.sh   (pure helpers)                       │  │
│  │  ├── scripts/lint.sh  (shellcheck + shfmt)                 │  │
│  │  └── scripts/test-unit.sh (bats runner)                    │  │
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

### `openclaw-cluster.sh` — orchestrator

A 1 298-line Bash script (intentionally kept monolithic in v1.x for stability). It implements:

- `cluster_init` — build image, create N instances
- `cluster_start` / `cluster_stop` / `cluster_restart` — Docker compose lifecycle
- `cluster_status` — formatted table
- `cluster_logs` — `docker compose logs`
- `cluster_exec` — `docker compose exec`
- `cluster_config` — edit `openclaw.json` in `$EDITOR`
- `cluster_destroy` / `cluster_clean_all` — teardown with typed confirmation
- `cluster_update` — rebuild + recreate
- `cluster_backup` / `cluster_restore` — tar.gz snapshot of an instance
- `cluster_scale` — add/remove instances
- `cluster_tokens` / `cluster_dashboard` — show / open gateway URL
- `cluster_set_openrouter_key` / `cluster_set_telegram` — live config update

It runs in two modes: **interactive menu** (no args) and **batch** (first arg = command).

### `lib/cluster.sh` — pure helpers

Extracted pure functions, currently used by tests and slated to be sourced by the main script in v1.2.0:

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
| `openclaw-cluster.sh` | no | Orchestrator |
| `lib/cluster.sh` | no | Pure helpers |
| `Dockerfile.openclaw-chrome` | no | Image recipe |
| `docker-compose.template.yml` | no | Compose template |
| `.env.example` | no | Sample env vars |
| `.env` | **yes** | Local secrets (created by `init`) |
| `instances/` | **yes** | Per-instance data |
| `backups/` | **yes** | tar.gz snapshots |

## Future architecture (post-1.x)

```
bin/openclaw-cluster  (thin entry-point, sources lib/*)
lib/
  ├── cluster.sh       (pure)
  ├── logging.sh
  ├── ui.sh
  ├── docker.sh
  ├── template.sh      (compose + openclaw.json render)
  ├── lifecycle.sh     (start/stop/destroy/clean)
  ├── backup.sh
  ├── menu.sh
  └── batch.sh
```

This is **Phase 2** in the roadmap. v1.1.0 adds the foundation; v1.2.0 will refactor without breaking compat.
