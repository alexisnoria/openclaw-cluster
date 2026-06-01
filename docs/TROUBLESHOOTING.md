# Troubleshooting

Common problems and fixes. If yours isn't here, please [open an issue](https://github.com/alexisnoria/openclaw-cluster/issues).

## Table of contents

- [Docker](#docker)
- [Ports](#ports)
- [Image build](#image-build)
- [Chrome / browser](#chrome--browser)
- [Telegram](#telegram)
- [OpenRouter](#openrouter)
- [Backup / restore](#backup--restore)
- [Performance](#performance)
- [Logs and debugging](#logs-and-debugging)

---

## Docker

### `docker: command not found`

Install Docker: <https://docs.docker.com/get-docker/>

### `permission denied while trying to connect to the Docker daemon socket`

Add yourself to the `docker` group (Linux) or ensure Docker Desktop is running (macOS).

```bash
# Linux
sudo usermod -aG docker $USER
# Log out and back in, or:
newgrp docker
```

### `Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?`

Start the daemon. On macOS, open Docker Desktop.

---

## Ports

### `bind: address already in use` when starting an instance

The instance's gateway or bridge port is taken. Two options:

1. Free the port: `lsof -i :18022` → kill the process.
2. Reassign via a new instance with a higher id (`init 1` uses port 18022; `init 5` uses 18110).

### Port allocation table

| Instance | Gateway | Bridge |
|----------|---------|--------|
| 1        | 18022   | 18023  |
| 2        | 18044   | 18045  |
| N        | 18000 + N×22 | 18000 + N×22 + 1 |

---

## Image build

### `failed to solve: ghcr.io/openclaw/openclaw:latest`

The upstream image isn't reachable. Check:

```bash
docker pull ghcr.io/openclaw/openclaw:latest
```

If behind a corporate proxy, configure Docker's proxy settings.

### Google Chrome install fails on arm64 (Apple Silicon)

The Dockerfile has a fallback to `chromium` if the Chrome `.deb` install fails. Inspect with:

```bash
docker build -t openclaw-cluster:debug -f Dockerfile.openclaw-chrome . --progress=plain
```

### Build is slow

The Dockerfile uses `--mount=type=cache` for `apt`. Make sure BuildKit is enabled:

```bash
export DOCKER_BUILDKIT=1
```

---

## Chrome / browser

### `browser.executablePath not found`

The image wasn't built with `CHROME=yes`, or the install failed. Rebuild:

```bash
./openclaw-cluster.sh update
```

### Headless mode issues

If you see `chrome: cannot open display` or similar, you're probably in a non-X11 environment. The default `OPENCLAW_BROWSER_HEADLESS=1` should prevent this. To force headed mode (rarely useful inside a container):

```bash
./openclaw-cluster.sh init 1 latest yes no
```

---

## Telegram

### `dmPolicy=open` is dangerous

Don't use `open` unless you fully trust the bot. Stick with `pairing` (default) or `allowlist` with explicit user IDs.

### Bot doesn't respond

1. Check the bot token is correct: `./openclaw-cluster.sh set-telegram 1 <token> pairing`
2. Look at logs: `./openclaw-cluster.sh logs 1` and search for `telegram`.
3. In the gateway control UI, verify the channel is enabled.
4. DM the bot `/start` and approve the pairing code if `pairing` is on.

---

## OpenRouter

### `401 Unauthorized`

Wrong or revoked API key. Update:

```bash
./openclaw-cluster.sh set-openrouter-key all <new_key>
```

The change is applied to `config/openclaw.json` and `config/agents/main/agent/auth-profiles.json`. **You must restart** the instance to pick it up:

```bash
./openclaw-cluster.sh restart 1
```

### `429 Too Many Requests` / rate limiting

OpenRouter applies per-key limits. Either:
- Use a paid plan / higher tier
- Distribute load across multiple keys (each instance can have its own)

### `model not found`

Verify the model id is correct in `instances/instance-1/config/agents/main/agent/models.json` and matches what OpenRouter serves (e.g., `deepseek/deepseek-v4-pro`, not `openrouter/deepseek/deepseek-v4-pro` in the API call path).

---

## Backup / restore

### Restore overwrites a working instance

`restore` will warn and ask before overwriting. If you bypass that, the working instance is gone — restore from a different backup.

### Backups aren't encrypted

`backups/*.tar.gz` contain plaintext config, tokens, and conversation history. Store on encrypted volumes or `gpg` them before uploading.

### How to verify a backup is valid

```bash
tar -tzf backups/instance-1_20260101_120000.tar.gz | head
# Should show: instance-1/, instance-1/config/, instance-1/.env, ...
```

If the archive is corrupt, `tar -xzvf` will fail with a CRC error. Don't restore; re-backup the live instance instead.

---

## Performance

### Instances consume a lot of RAM

Each instance runs its own Node.js + Chrome. Budget ~500 MB per idle instance, 1-2 GB under load.

- 1-3 instances: 4 GB host is fine
- 5-10 instances: 8 GB recommended
- 20+ instances: 16 GB+, consider a server

### Slow `docker compose up` after changes

Edit a single file in `instances/instance-1/config/` and the bind-mount means no rebuild is needed — just `restart`. Heavy changes (`.env`, `docker-compose.yml`) do trigger recreates.

---

## Logs and debugging

### Get more verbose logs

```bash
docker compose -f instances/instance-1/docker-compose.yml logs --tail=200 -f openclaw-gateway
```

### Drop into the container

```bash
./openclaw-cluster.sh exec 1 bash
# or
docker compose -f instances/instance-1/docker-compose.yml --profile cli run --rm openclaw-cli
```

### Nuclear option: nuke and rebuild

```bash
./openclaw-cluster.sh clean
# type NUCLEAR when prompted
./openclaw-cluster.sh init 3
```

This destroys all instances, images, and `.env`. Backups in `backups/` are kept.

---

## Still stuck?

1. Run `make doctor` and `make lint` to catch environment issues.
2. Open a [bug report](https://github.com/alexisnoria/openclaw-cluster/issues/new?template=bug_report.md) with the output of `./openclaw-cluster.sh status`, the failing log lines, and your OS + Docker versions.
