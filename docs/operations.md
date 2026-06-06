# Operations

## Logs

```bash
make logs            # All containers
make logs-n8n        # n8n only
make logs-db         # PostgreSQL only
docker compose logs -f --tail=100 n8n
```

## Updates

```bash
make update          # Pull latest + recreate prod
make update-dev      # Pull latest + recreate dev
```

## Backup

```bash
make backup                              # Default (./backups/)
make backup-to path=/mnt/nas/backups     # Custom path

# Cron (crontab -e):
0 2 * * * /opt/n8n-docker-prod-stack/scripts/backup.sh
```

## Backup Verification

```bash
./scripts/verify-backup.sh

# Cron (crontab -e):
0 3 * * 0 /opt/n8n-docker-prod-stack/scripts/verify-backup.sh
```

## Restore

```bash
# 1. Extract
tar xzf backups/n8n-backup-20260101-120000.tar.gz

# 2. Restore DB
docker exec -i n8n-postgres pg_restore -U n8n -d n8n_production --clean < n8n_db.dump

# 3. Restore n8n data
docker exec -i n8n tar xzf - -C /home/node/.n8n/ < n8n-data.tar.gz

# 4. Restart
docker compose restart n8n
```

## Stop / Start / Clean

```bash
make stop          # Stop production
make restart       # Restart all
make down          # Stop + remove volumes (data loss)
make clean         # Full Docker prune
make clean-all     # + remove custom networks
```

## User Management

```bash
# Create
docker exec -it n8n n8n user:create \
  --email user@example.com \
  --password "SecurePass123!" \
  --firstName Jane --lastName Doe --role member

# List
docker exec -it n8n n8n user:list

# Reset password
docker exec -it n8n n8n user:reset-password --email user@example.com

# Enable/Disable
docker exec -it n8n n8n user:disable --email user@example.com
docker exec -it n8n n8n user:enable --email user@example.com
```
