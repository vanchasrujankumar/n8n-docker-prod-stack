# Setup Guide

## Prerequisites

- **Docker** 24+ and **Docker Compose** v2 plugin
- **Domain name** with DNS A records pointing to your server
- **Ports 80/443** open (Traefik handles SSL termination)
- **Server**: 2 vCPU, 4GB RAM minimum; 4 vCPU, 8GB RAM recommended

## DNS Configuration

| Record | Name | Value | Target |
|--------|------|-------|--------|
| A | `n8n` | `<your-server-ip>` | n8n UI |
| A | `traefik` | `<your-server-ip>` | Traefik dashboard |
| A | `monitor` | `<your-server-ip>` | Grafana |
| A | `prometheus` | `<your-server-ip>` | Prometheus |
| A | `minio` | `<your-server-ip>` | MinIO API |
| A | `minio-console` | `<your-server-ip>` | MinIO console |

Verify: `dig +short n8n.example.com`

## Server Preparation

```bash
ssh user@your-server-ip
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# re-login, then:
git clone https://github.com/vanchasrujankumar/n8n-docker-prod-stack.git
cd n8n-docker-prod-stack
```

## Setup Script

```bash
make setup
```

This generates:
- `N8N_ENCRYPTION_KEY` (openssl rand -hex 32)
- `N8N_USER_MANAGEMENT_JWT_SECRET` (openssl rand -hex 32)
- `DB_PASSWORD` (openssl rand -base64 24)
- Docker network `n8n-web`
- Directories and permissions (UID 1000)

## Configure .env

```bash
nano .env
```

Required:
```ini
DOMAIN_NAME=example.com
N8N_HOST=n8n.example.com
SSL_EMAIL=admin@example.com
```

Traefik auth:
```bash
htpasswd -nb admin your_secure_password | sed -e 's/\$/\$\$/g'
```

## Deploy Production

```bash
make prod
```

Verify:
```bash
make ps
make health
make logs
```

## Deploy Development

```bash
cp .env.dev.example .env.dev
make dev
# Access: http://localhost:5678
```

## Dev vs Prod

| Feature | Production | Development |
|---------|-----------|-------------|
| Access | `https://n8n.example.com` | `http://localhost:5678` |
| SSL | Let's Encrypt | None |
| Proxy | Traefik | Direct port |
| Execution | Own process | Main process |
| Pruning | 7 days | Disabled |
| Log Level | info | debug |
| DB port | Internal only | 5432 exposed |
| Resources | Capped | Unrestricted |
