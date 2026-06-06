# Production Hardening

## Checklist

- [ ] DNS A records for all 6 subdomains and propagated
- [ ] Port 80 (redirect) + 443 open; all others closed (firewall/SG)
- [ ] `.env` permissions: `chmod 600 .env`
- [ ] Strong passwords for ALL secrets (DB, n8n, Grafana, MinIO, Traefik)
- [ ] SMTP configured and tested (`n8n email:test`)
- [ ] Traefik dashboard credentials configured
- [ ] Grafana admin password changed from default
- [ ] MinIO root password changed from default
- [ ] n8n metrics enabled (`N8N_METRICS=true`)
- [ ] Prometheus retention tuned for your disk
- [ ] Binary storage reviewed (MinIO/S3 for scale)
- [ ] SSH key-only auth (no passwords)
- [ ] Backups scheduled (cron: `0 2 * * * .../scripts/backup.sh`)
- [ ] Backup verification scheduled (cron: `0 3 * * 0 .../scripts/verify-backup.sh`)
- [ ] Docker daemon: `live-restore: true` + log rotation
- [ ] fail2ban / crowdsec for brute-force protection
- [ ] `docker system prune -f` in crontab

## Recommended Docker Daemon Config

`/etc/docker/daemon.json`:
```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "storage-driver": "overlay2"
}
```

---

# Troubleshooting

## SSL Certificate Not Issued

```bash
docker compose logs traefik
```

Common causes:
- DNS A record not pointing to this server
- Port 80 blocked by firewall
- Let's Encrypt rate limit (5/week/domain)

## n8n Won't Start

```bash
docker compose logs n8n
docker exec -it n8n-postgres pg_isready -U n8n
docker compose restart n8n
```

## High Memory Usage

```bash
make stats
# Tune in .env:
EXECUTIONS_PROCESS_LIMIT=3
N8N_PAYLOAD_SIZE_MAX=8
# Recreate: docker compose up -d
```

## Reset Everything

```bash
make clean-all
make setup && make prod
```
