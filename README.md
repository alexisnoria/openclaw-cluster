# OpenClaw Cluster Manager

Orquestador multi-instancia Docker para [OpenClaw](https://github.com/openclaw/openclaw) con Google Chrome integrado para automatización de navegador.

## Requisitos

- Docker y Docker Compose
- OpenSSL
- OpenRouter API Key
- (Opcional) Telegram Bot Token

## Instalación

```bash
git clone https://github.com/<tu-usuario>/openclaw-cluster.git
cd openclaw-cluster
cp .env.example .env
# Edita .env con tus credenciales reales
```

## Uso

### Modo interactivo (menú)

```bash
chmod +x openclaw-cluster.sh
./openclaw-cluster.sh
```

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

## Estructura del proyecto

```
openclaw-cluster/
├── .env.example                  # Plantilla de variables de entorno
├── .gitignore
├── docker-compose.template.yml   # Template por instancia
├── Dockerfile.openclaw-chrome    # Imagen con Chrome integrado
├── openclaw-cluster.sh           # Script principal del cluster
├── instances/                    # Datos generados por instancia (gitignored)
│   └── instance-<n>/
│       ├── config/
│       ├── workspace/
│       └── home/
└── backups/                      # Backups generados (gitignored)
```

## Cómo funciona

1. **`init`** construye la imagen Docker y crea N instancias con configuración aislada
2. Cada instancia tiene su propia red Docker, puertos, tokens y configuración
3. Los puertos gateway se asignan desde `18000` con incrementos de `22` por instancia
4. **`start`/`stop`** controlan el ciclo de vida de las instancias vía Docker Compose
5. **`scale`** agrega o elimina instancias dinámicamente
6. **`backup`/`restore`** permite respaldar y restaurar instancias completas

## Licencia

MIT
