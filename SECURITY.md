# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 1.1.x   | :white_check_mark: |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security issues.**

Report privately via one of these channels:

1. **GitHub Security Advisories** (preferred): https://github.com/alexisnoria/openclaw-cluster/security/advisories/new
2. **Email**: `security@openclaw-cluster.local` (replace with the real address)

You should receive an acknowledgment within 72 hours. We aim to provide a fix
or mitigation within 14 days for critical issues, 30 days for high severity,
and 60 days for medium/low.

## What to include

- Affected version (commit SHA, tag, or branch)
- Environment (OS, Docker version, OpenClaw image tag)
- Reproduction steps
- Impact assessment
- Suggested fix (optional)

## Scope

In scope:

- The cluster manager script (`openclaw-cluster.sh`)
- The Docker image (`Dockerfile.openclaw-chrome`)
- Generated files written under `instances/`
- The companion library `lib/cluster.sh`

Out of scope:

- The upstream `ghcr.io/openclaw/openclaw` image — report to OpenClaw maintainers
- Your local Docker daemon, host OS, or your own `~/.bashrc`

## Hardening checklist for users

- Never commit `.env` (it's in `.gitignore`).
- Set `chmod 600 .env` and `chmod 600 instances/*/.env` after creation.
- Run `cluster destroy` before deleting files manually; the script asks for typed confirmation.
- Use unique `OPENROUTER_API_KEY` per environment; rotate if exposed.
- If exposing the gateway beyond `127.0.0.1`, put it behind a reverse proxy with TLS.
- Prefer `TELEGRAM_DM_POLICY=pairing` (default) over `open` unless you understand the risk.
- Backups in `backups/` are not encrypted; store them on encrypted volumes.
