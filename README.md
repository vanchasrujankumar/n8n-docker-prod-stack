# n8n Docker Production Stack

[![CI](https://github.com/vanchasrujankumar/n8n-docker-prod-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/vanchasrujankumar/n8n-docker-prod-stack/actions/workflows/ci.yml)
[![CD](https://github.com/vanchasrujankumar/n8n-docker-prod-stack/actions/workflows/cd.yml/badge.svg)](https://github.com/vanchasrujankumar/n8n-docker-prod-stack/actions/workflows/cd.yml)

Production-grade self-hosted n8n — PostgreSQL, Traefik SSL, Prometheus/Grafana monitoring, MinIO storage, SMTP email, CI/CD, Renovate auto-updates.

## Architecture

```
  Internet                    Host Server (Docker)
  ─────────                   ─────────────────────
                              ┌──────────────────┐
  User ──► n8n.example.com ──►│  Traefik v3.1    │
                              │  :80 ──► :443     │
                              └──────┬───────────┘
                  ┌───────────────────┼───────────────────┐
                  ▼                   ▼                   ▼
          ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
          │   n8n :5678  │   │ Grafana :3000 │   │ Prometheus   │
          │  Workflows   │   │  Dashboards   │   │  :9090       │
          └──────┬───────┘   └──────────────┘   └──────────────┘
                  │
          ┌───────▼────────┐
          │ PostgreSQL 16  │
          │  :5432 (int.)  │
          └────────────────┘
```

Also: MinIO S3 (:9000), Let's Encrypt (auto-SSL), SMTP email, Cloudflare DNS-01 optional.

## Quick Start

```bash
git clone https://github.com/vanchasrujankumar/n8n-docker-prod-stack.git
cd n8n-docker-prod-stack
make setup          # Interactive: secrets, .env, permissions
nano .env           # Set DOMAIN_NAME, N8N_HOST, SSL_EMAIL
make prod           # Deploy
make health         # Verify
```

## Makefile Commands

| Command | Action |
|---------|--------|
| `make dev` | Start dev stack (localhost:5678) |
| `make prod` | Start production stack |
| `make logs` / `make logs-n8n` | Tail logs |
| `make ps` / `make stats` | Container status / resource usage |
| `make update` | Pull latest images + recreate |
| `make backup` | Full backup (PG + volumes + configs) |
| `make health` | Health check |
| `make test` | Run all tests |
| `make clean` / `make clean-all` | Teardown |

## Project Layout

```
├── compose.yaml              # Production (n8n + PG + Traefik + Prom/Graf + MinIO)
├── compose.dev.yaml          # Development (n8n + PG, direct port)
├── .env.example              # Template with 30+ vars
├── renovate.json             # Auto-update Docker images weekly
├── Makefile                  # 30+ convenience commands
├── docker/
│   ├── traefik/              # Traefik static config
│   ├── prometheus/           # Alert rules + scrape configs
│   └── grafana/              # Provisioned dashboard + datasource
├── scripts/                  # setup, deploy, backup, healthcheck, verify-backup
├── tests/                    # Integration + security audit
├── .github/workflows/        # CI (lint→scan→test) + CD (dev/prod auto-deploy)
└── docs/                     # Detailed guides
```

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/setup.md](docs/setup.md) | Full setup: DNS, server prep, .env, deploy dev & prod |
| [docs/operations.md](docs/operations.md) | Logs, updates, backup/restore, user management |
| [docs/monitoring.md](docs/monitoring.md) | Prometheus + Grafana dashboards, SMTP email, MinIO storage |
| [docs/ci-cd.md](docs/ci-cd.md) | CI/CD pipelines, GitHub secrets, Renovate, security scanning |
| [docs/hardening.md](docs/hardening.md) | Security checklist, Docker config, troubleshooting |

## License

MIT
