#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# n8n Production Stack - Backup Script
# =============================================================================
# Creates timestamped backups of PostgreSQL, n8n data, and Traefik certs.
#   ./scripts/backup.sh              # Backup to ./backups/
#   ./scripts/backup.sh /path/to/dir # Backup to custom directory
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[backup]${NC} $1"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BACKUP_BASE="${1:-${PROJECT_ROOT}/backups}"
BACKUP_DIR="${BACKUP_BASE}/n8n-backup-$(date +%Y%m%d-%H%M%S)"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
ENV_FILE=".env"

# Source .env for DB credentials if it exists
if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  source "${ENV_FILE}"
  set +a
else
  err ".env file not found. Cannot determine database credentials."
fi

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log "Starting n8n backup..."

for cmd in docker tar gzip; do
  command -v "${cmd}" >/dev/null 2>&1 || err "${cmd} is not installed."
done

mkdir -p "${BACKUP_DIR}"
ok "Backup directory: ${BACKUP_DIR}"

# ---------------------------------------------------------------------------
# 1. PostgreSQL Dump
# ---------------------------------------------------------------------------
log "Backing up PostgreSQL database..."
POSTGRES_CONTAINER=$(docker ps --filter "name=n8n-postgres" --format "{{.Names}}" 2>/dev/null || echo "")
if [ -n "${POSTGRES_CONTAINER}" ]; then
  docker exec "${POSTGRES_CONTAINER}" pg_dump \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    --no-comments \
    -F c \
    -f "/tmp/n8n_db_backup.dump" 2>/dev/null || {
    warn "pg_dump via exec failed. Trying docker cp approach..."
    docker exec "${POSTGRES_CONTAINER}" pg_dump -U "${DB_USER}" -d "${DB_NAME}" -F c > "${BACKUP_DIR}/n8n_db.dump" 2>/dev/null || err "PostgreSQL backup failed."
    ok "PostgreSQL dumped (direct stream)."
  }
  if [ -f "${BACKUP_DIR}/n8n_db.dump" ]; then
    : # already streamed above
  else
    docker cp "${POSTGRES_CONTAINER}:/tmp/n8n_db_backup.dump" "${BACKUP_DIR}/n8n_db.dump" 2>/dev/null || err "Failed to copy database dump."
    docker exec "${POSTGRES_CONTAINER}" rm -f /tmp/n8n_db_backup.dump
    ok "PostgreSQL backed up."
  fi
else
  warn "PostgreSQL container not running. Skipping database backup."
fi

# ---------------------------------------------------------------------------
# 2. n8n Data
# ---------------------------------------------------------------------------
log "Backing up n8n data volume..."
N8N_CONTAINER=$(docker ps --filter "name=^n8n$" --format "{{.Names}}" 2>/dev/null || echo "")
if [ -n "${N8N_CONTAINER}" ]; then
  docker run --rm \
    --volumes-from "${N8N_CONTAINER}" \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.19 \
    tar czf "/backup/n8n-data.tar.gz" -C /home/node/.n8n . 2>/dev/null || warn "n8n data backup had warnings."
  ok "n8n data backed up."
else
  # Try volume-based backup
  if docker volume inspect n8n-data >/dev/null 2>&1; then
    docker run --rm \
      -v n8n-data:/source:ro \
      -v "${BACKUP_DIR}:/backup" \
      alpine:3.19 \
      tar czf "/backup/n8n-data.tar.gz" -C /source . 2>/dev/null || warn "n8n volume backup had warnings."
    ok "n8n volume data backed up."
  else
    warn "n8n container and volume not found. Skipping n8n data backup."
  fi
fi

# ---------------------------------------------------------------------------
# 3. Traefik Certificates
# ---------------------------------------------------------------------------
log "Backing up Traefik certificates..."
if docker volume inspect n8n-traefik-certificates >/dev/null 2>&1; then
  docker run --rm \
    -v n8n-traefik-certificates:/source:ro \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.19 \
    tar czf "/backup/traefik-certificates.tar.gz" -C /source . 2>/dev/null || warn "Traefik cert backup had warnings."
  ok "Traefik certificates backed up."
else
  warn "Traefik certificates volume not found. Skipping."
fi

# ---------------------------------------------------------------------------
# 4. Environment Files
# ---------------------------------------------------------------------------
log "Backing up configuration files..."
[ -f .env ] && cp .env "${BACKUP_DIR}/.env.backup"
[ -f compose.yaml ] && cp compose.yaml "${BACKUP_DIR}/compose.yaml.backup"
ok "Configuration files backed up."

# ---------------------------------------------------------------------------
# 5. Create manifest
# ---------------------------------------------------------------------------
{
  echo "Backup Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "n8n Version: $(docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' "${N8N_CONTAINER}" 2>/dev/null || echo "unknown")"
  echo "PostgreSQL Version: $(docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' "${POSTGRES_CONTAINER}" 2>/dev/null || echo "unknown")"
  echo "Files:"
  ls -lh "${BACKUP_DIR}"
} > "${BACKUP_DIR}/MANIFEST.txt"
ok "Manifest created."

# ---------------------------------------------------------------------------
# 6. Compress backup directory
# ---------------------------------------------------------------------------
log "Compressing backup..."
COMPRESSED_FILE="${BACKUP_DIR}.tar.gz"
tar czf "${COMPRESSED_FILE}" -C "$(dirname "${BACKUP_DIR}")" "$(basename "${BACKUP_DIR}")"
rm -rf "${BACKUP_DIR}"
ok "Backup compressed: ${COMPRESSED_FILE}"

# ---------------------------------------------------------------------------
# 7. Cleanup old backups
# ---------------------------------------------------------------------------
log "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_BASE}" -name "n8n-backup-*.tar.gz" -type f -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true
ok "Old backups cleaned."

# ---------------------------------------------------------------------------
# 8. Summary
# ---------------------------------------------------------------------------
BACKUP_SIZE=$(du -h "${COMPRESSED_FILE}" | cut -f1)
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Backup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  File:   ${COMPRESSED_FILE}"
echo "  Size:   ${BACKUP_SIZE}"
echo "  Date:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "  To restore:"
echo "    1. Extract: tar xzf ${COMPRESSED_FILE}"
echo "    2. Restore DB: docker exec -i n8n-postgres pg_restore -U \${DB_USER} -d \${DB_NAME} < n8n_db.dump"
echo "    3. Restore data: docker cp n8n-data.tar.gz n8n:/tmp/ && docker exec n8n tar xzf /tmp/n8n-data.tar.gz -C /home/node/.n8n/"
echo ""
