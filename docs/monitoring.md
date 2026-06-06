# Monitoring

The stack includes Prometheus + Grafana. n8n exposes metrics at `/metrics` when `N8N_METRICS=true`.

## Access

| URL | Credentials |
|-----|-------------|
| `https://monitor.example.com` | `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` in `.env` |
| `https://prometheus.example.com` | No auth |

## Pre-configured Dashboard

The `n8n-overview` dashboard includes:

| Panel | Description |
|-------|-------------|
| n8n Status | Up/down indicator |
| PostgreSQL Status | DB connectivity |
| Execution Rate | Success/failed/running per second |
| Execution Duration | p50/p95/p99 latency |
| Workflow Status | Table by state |
| Active Webhooks | Count of registered webhooks |
| PG Connections | Active vs max |
| MinIO Storage | Object count |

## Alert Rules

| Alert | Threshold | Severity |
|-------|-----------|----------|
| n8nDown | 1m unreachable | Critical |
| HighExecutionFailures | >0.1/s over 5m | Warning |
| PostgresDown | 30s unreachable | Critical |
| PostgresHighConnections | >50 active | Warning |
| DiskSpaceLow | <10% free | Critical |

## Plugins

```ini
GRAFANA_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel
```

---

# Email / SMTP

Required for invites, password resets, and notification nodes.

## Configuration

```ini
N8N_EMAIL_MODE=smtp
N8N_SMTP_HOST=smtp.sendgrid.net
N8N_SMTP_PORT=587
N8N_SMTP_USER=apikey
N8N_SMTP_PASS=your_key
N8N_EMAIL_FROM=n8n@example.com
```

## Providers

| Provider | Host | Port |
|----------|------|------|
| SendGrid | `smtp.sendgrid.net` | 587 |
| AWS SES | `email-smtp.region.amazonaws.com` | 587 |
| Mailgun | `smtp.mailgun.org` | 587 |
| Gmail | `smtp.gmail.com` | 587 |
| Mailjet | `in-v3.mailjet.com` | 587 |
| Postmark | `smtp.postmarkapp.com` | 587 |

## Test

```bash
docker exec -it n8n n8n email:test --email your@email.com
```

---

# Object Storage (MinIO)

n8n stores binary data locally by default. For production scale, use MinIO (S3-compatible).

## Enable S3 Mode

1. Deploy (MinIO starts automatically)
2. Create bucket at `https://minio-console.example.com` using `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
3. Edit `.env`:

```ini
N8N_DEFAULT_BINARY_DATA_MODE=s3
N8N_BINARY_DATA_STORAGE_S3_BUCKET_NAME=n8n-binaries
N8N_BINARY_DATA_STORAGE_S3_ACCESS_KEY=${MINIO_ROOT_USER}
N8N_BINARY_DATA_STORAGE_S3_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
N8N_BINARY_DATA_STORAGE_S3_FORCE_PATH_STYLE=true
N8N_BINARY_DATA_STORAGE_S3_HOST=minio.example.com
N8N_BINARY_DATA_STORAGE_S3_PROTOCOL=https
```

4. Recreate: `docker compose up -d n8n`

Console at `https://minio-console.example.com`.
