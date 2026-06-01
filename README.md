# OpenClaw Cluster Manager

[![CI](https://github.com/alexisnoria/openclaw-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisnoria/openclaw-cluster/actions/workflows/ci.yml)
[![Release](https://github.com/alexisnoria/openclaw-cluster/actions/workflows/release.yml/badge.svg)](https://github.com/alexisnoria/openclaw-cluster/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](VERSION)
[![Shellcheck](https://img.shields.io/badge/shellcheck-clean-brightgreen.svg)](.shellcheckrc)

Orquestador multi-instancia Docker para [OpenClaw](https://github.com/openclaw/openclaw) con Google Chrome integrado para automatización de navegador.

> **Estado:** v1.1.0 — 100% compatible con v1.0.0. No se introdujeron cambios funcionales; esta versión añade infraestructura de calidad (CI, tests, lint, docs).

---

## Tabla de contenidos

- [Características](#características)
- [Requisitos](#requisitos)
- [Inicio rápido](#inicio-rápido)
- [Uso](#uso)
  - [Modo interactivo](#modo-interactivo-menú)
  - [Modo batch](#modo-batch-comandos-directos)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Cómo funciona](#cómo-funciona)
- [Documentación](#documentación)
- [Desarrollo y contribución](#desarrollo-y-contribución)
- [Seguridad](#seguridad)
- [Licencia](#licencia)

---

## Características

- 🐳 **Multi-instancia aislada** — Cada instancia tiene su propia red Docker, puertos, tokens y volúmenes.
- 🌐 **Google Chrome integrado** — Imagen base con Chrome estable (amd64 + arm64 con fallback a Chromium).
- 🤖 **OpenRouter listo** — Soporte de modelos vía OpenRouter API.
- 💬 **Telegram opcional** — Bot integrado con `dmPolicy` configurable.
- 📦 **Backup / restore** — Snapshots `.tar.gz` de instancias completas.
- 🏗️ **Escalado dinámico** — `scale +N` / `scale -N` sin reiniciar el cluster.
- 🛠️ **CLI dual** — Menú interactivo y batch scripts.
- ✅ **Calidad** — shellcheck + shfmt + 36 tests bats en CI.
- 🔒 **Seguro por defecto** — Token hex de 32 bytes, `cap_drop`, `no-new-privileges`, confirmación tipeada para operaciones destructivas.

---

## Requisitos

- Docker 20.10+ y Docker Compose v2
- OpenSSL
- `bash` 4.4+
- OpenRouter API Key
- (Opcional) Telegram Bot Token de @BotFather

---

## Inicio rápido

```bash
git clone https://github.com/alexisnoria/openclaw-cluster.git
cd openclaw-cluster
cp .env.example .env
# Edita .env con tus credenciales reales

chmod +x openclaw-cluster.sh
./openclaw-cluster.sh          # menú interactivo
# o en batch:
./openclaw-cluster.sh init 1   # crea 1 instancia
./openclaw-cluster.sh start all
./openclaw-cluster.sh dashboard
```

---

## Uso

### Modo interactivo (menú)

```bash
./openclaw-cluster.sh
```

Abre un menú con 18 operaciones agrupadas en **Operaciones** y **Administración**. La opción `0` sale.

### Modo batch (comandos directos)

```bash
./openclaw-cluster.sh init [count] [tag] [chrome] [headless] [tz] [api_key] [model] [telegram_token] [dm_policy]
./openclaw-cluster.sh start [all|<id>|range:<start>-<end>]
./openclaw-cluster.sh stop [all|<id>|range:<start>-<end>]
./openclaw-cluster.sh restart <id>
./openclaw-cluster.sh status
./openclaw-cluster.sh logs <id>
./openclaw-cluster.sh exec <id> <command>
./openclaw-cluster.sh config <id>
./openclaw-cluster.sh destroy <id>
./openclaw-cluster.sh clean
./openclaw-cluster.sh update [tag]
./openclaw-cluster.sh backup <id>
./openclaw-cluster.sh restore <backup_file> [id]
./openclaw-cluster.sh scale
./openclaw-cluster.sh tokens
./openclaw-cluster.sh dashboard
./openclaw-cluster.sh set-openrouter-key [instance|all] [new_key]
./openclaw-cluster.sh set-telegram [instance|all] [bot_token] [dm_policy]
```

Para hacer scripting más cómodo también hay un `Makefile`:

```bash
make init COUNT=3    # inicializa 3 instancias
make status          # muestra estado
make lint            # corre shellcheck + shfmt
make test            # corre bats
make doctor          # verifica estructura del proyecto
make help            # lista todos los targets
```

---

## Estructura del proyecto

```
openclaw-cluster/
├── openclaw-cluster.sh         # Orquestador (estable, 100% compat)
├── lib/cluster.sh              # Helpers puros (testables)
├── Dockerfile.openclaw-chrome  # Imagen con Chrome integrado
├── docker-compose.template.yml # Plantilla por instancia
├── .env.example
├── Makefile                    # `make lint test build run`
├── scripts/
│   ├── lint.sh                 # shellcheck + shfmt
│   └── test-unit.sh            # bats runner
├── tests/bats/                 # 36 tests unitarios
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEVELOPMENT.md
│   └── TROUBLESHOOTING.md
├── .github/
│   ├── workflows/{ci,release}.yml
│   ├── ISSUE_TEMPLATE/
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── CODEOWNERS
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── CHANGELOG.md
├── VERSION
├── LICENSE
└── README.md
```

Directorios gitignored (generados en runtime):

```
instances/        # datos por instancia (config, workspace, home, .env)
backups/          # tar.gz de snapshots
```

---

## Cómo funciona

1. **`init`** construye la imagen Docker y crea N instancias con configuración aislada
2. Cada instancia tiene su propia red Docker (`oc-net-N`), puertos, tokens y configuración
3. Los puertos gateway se asignan desde `18000` con incrementos de `22` por instancia
4. **`start`/`stop`** controlan el ciclo de vida de las instancias vía Docker Compose
5. **`scale`** agrega o elimina instancias dinámicamente
6. **`backup`/`restore`** permite respaldar y restaurar instancias completas

Más detalles en [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Documentación

| Documento | Para quién |
|-----------|-----------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Quiere entender cómo está organizado |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Va a contribuir código |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Algo no funciona |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow de contribución |
| [SECURITY.md](SECURITY.md) | Reportar vulnerabilidad |
| [CHANGELOG.md](CHANGELOG.md) | Qué cambió en cada versión |

---

## Desarrollo y contribución

```bash
brew install shellcheck shfmt bats-core make  # macOS
# o
sudo apt install shellcheck bats make        # Debian/Ubuntu

make doctor   # valida estructura
make lint     # shellcheck + shfmt
make test     # 36 tests bats
```

Las contribuciones requieren:

- `make lint` y `make test` en verde
- 100% compatibilidad con el CLI existente (ver [CONTRIBUTING.md](CONTRIBUTING.md))
- `CHANGELOG.md` actualizado bajo `[Unreleased]`

Ver [CONTRIBUTING.md](CONTRIBUTING.md) para el flujo completo.

---

## Seguridad

Para reportar una vulnerabilidad **no abras un issue público**. Sigue el proceso en [SECURITY.md](SECURITY.md).

Recomendaciones operativas:

- `chmod 600 .env` después de crearlo
- Usa `TELEGRAM_DM_POLICY=pairing` (default) en lugar de `open`
- Rota `OPENROUTER_API_KEY` periódicamente
- No expongas los puertos gateway directamente a internet; ponlos detrás de un reverse proxy con TLS

---

## Licencia

MIT — ver [LICENSE](LICENSE).

---

🦞 **OpenClaw Cluster Manager** — Hecho con [OpenClaw](https://github.com/openclaw/openclaw).
