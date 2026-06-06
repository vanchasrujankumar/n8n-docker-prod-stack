# CI/CD Pipeline

## CI (`.github/workflows/ci.yml`)

Triggered on push/PR to `main`:

1. **Lint** — Compose validation, Traefik YAML, env completeness, shellcheck
2. **Security** — Trivy vulnerability scan, Gitleaks secret detection
3. **Test** — Deploys stack, runs health checks, verifies API + PostgreSQL

## CD (`.github/workflows/cd.yml`)

| Trigger | Env | Action |
|---------|-----|--------|
| Push `main` | Dev | Rsync + `docker compose up -d` |
| Tag `v*.*.*` | Prod | Rsync + `.env` from secrets + deploy |
| `workflow_dispatch` | Dev/Prod | Manual with `confirm: deploy` |

## Required GitHub Secrets

```
SSH_PRIVATE_KEY              # Deploy server SSH key
SSH_HOST                     # Server hostname/IP
SSH_USER                     # SSH user
N8N_HOST                     # Production domain
SSL_EMAIL                    # Let's Encrypt email
DB_PASSWORD                  # Database password
N8N_ENCRYPTION_KEY           # openssl rand -hex 32
N8N_USER_MANAGEMENT_JWT_SECRET  # openssl rand -hex 32
TRAEFIK_AUTH_USER            # Dashboard username
TRAEFIK_AUTH_PASS_HASH       # Dashboard password hash
DEPLOY_PATH                  # Server path (default: /opt/n8n-docker-prod-stack)
```

---

# Automated Updates

## Renovate

- **Schedule**: Weekly (Monday 9 AM UTC)
- **n8n**: PR for review (never auto-merged)
- **PostgreSQL/Traefik patches**: Auto-merged
- Dashboard: repo Settings → Renovate

## WhiteSource / Mend

- Scans Docker base images
- Integrates as GitHub PR check
- Reports in Security tab

## Local Security

```bash
brew install trivy
make test-security
trivy image docker.n8n.io/n8nio/n8n:latest
```
