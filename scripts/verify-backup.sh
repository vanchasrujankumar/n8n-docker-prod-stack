#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# n8n Backup Verification Script
# =============================================================================
# Restores the latest backup to a temporary container and validates integrity.
# Run manually or via cron: 0 3 * * 0 /opt/n8n-docker-prod-stack/scripts/verify-backup.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[verify]${NC} $1"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[FAIL]${NC} $1"; }
fail() { err "$@"; VERIFY_EXIT=1; }

VERIFY_EXIT=0
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

LATEST_BACKUP=$(ls -t ${PROJECT_ROOT}/backups/n8n-backup-*.tar.gz 2>/dev/null | head -1)

if [ -z "${LATEST_BACKUP}" ]; then
  err "No backups found in ${PROJECT_ROOT}/backups/"
  exit 1
fi

log "Verifying backup: $(basename ${LATEST_BACKUP})"
log "File size: $(du -h "${LATEST_BACKUP}" | cut -f1)"

# ---------------------------------------------------------------------------
# 1. Archive integrity check
# ---------------------------------------------------------------------------
log "Checking archive integrity..."
if gzip -t "${LATEST_BACKUP}" 2>/dev/null; then
  ok "Archive is valid (gzip integrity check passed)"
else
  fail "Archive is corrupt (gzip integrity check FAILED)"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Extract and validate contents
# ---------------------------------------------------------------------------
log "Extracting backup..."
tar xzf "${LATEST_BACKUP}" -C "${WORK_DIR}" 2>/dev/null || {
  fail "Failed to extract backup archive"
  exit 1
}
ok "Archive extracted successfully"

EXTRACTED_DIR=$(find "${WORK_DIR}" -maxdepth 1 -type d | tail -1)

# Check required files
REQUIRED_FILES=("n8n_db.dump" "MANIFEST.txt")
MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "${EXTRACTED_DIR}/${file}" ]; then
    ok "Found required file: ${file}"
    FILE_SIZE=$(stat -f%z "${EXTRACTED_DIR}/${file}" 2>/dev/null || stat -c%s "${EXTRACTED_DIR}/${file}" 2>/dev/null)
    log "  ${file} size: ${FILE_SIZE} bytes"
    if [ "${FILE_SIZE}" -eq 0 ]; then
      fail "${file} is empty (0 bytes)"
    fi
  else
    fail "Missing required file: ${file}"
    MISSING=1
  fi
done

# ---------------------------------------------------------------------------
# 3. Validate PostgreSQL dump (header check)
# ---------------------------------------------------------------------------
if [ -f "${EXTRACTED_DIR}/n8n_db.dump" ]; then
  log "Validating PostgreSQL dump format..."
  DUMP_HEADER=$(head -c 20 "${EXTRACTED_DIR}/n8n_db.dump" 2>/dev/null || echo "")
  if echo "${DUMP_HEADER}" | grep -qE "^(PGDMP|-- )"; then
    ok "PostgreSQL dump has valid header signature"
  else
    warn "PostgreSQL dump header looks unusual: $(echo "${DUMP_HEADER}" | xxd | head -1 2>/dev/null || echo "non-binary")"
  fi

  # Try restoring to a temp PostgreSQL container
  log "Attempting restore to temporary PostgreSQL container..."
  TMP_DB_CONTAINER="n8n-verify-pg-$(date +%s)"
  if docker run --rm -d \
    --name "${TMP_DB_CONTAINER}" \
    -e POSTGRES_USER=verify \
    -e POSTGRES_PASSWORD=verify_pass \
    -e POSTGRES_DB=verify_restore \
    postgres:16-alpine \
    >/dev/null 2>&1; then
    sleep 5
    if docker exec -i "${TMP_DB_CONTAINER}" pg_restore \
      -U verify \
      -d verify_restore \
      --no-owner \
      --no-privileges \
      --exit-on-error \
      < "${EXTRACTED_DIR}/n8n_db.dump" \
      >/dev/null 2>&1; then
      ok "PostgreSQL dump restores successfully (no errors)"
    else
      fail "PostgreSQL dump restore FAILED - backup may be corrupt"
    fi
    docker rm -f "${TMP_DB_CONTAINER}" >/dev/null 2>&1 || true
  else
    warn "Could not start temporary PostgreSQL container (Docker may be unavailable). Skipping restore test."
  fi
fi

# ---------------------------------------------------------------------------
# 4. Validate n8n data tarball
# ---------------------------------------------------------------------------
if [ -f "${EXTRACTED_DIR}/n8n-data.tar.gz" ]; then
  log "Validating n8n data archive..."
  if tar tzf "${EXTRACTED_DIR}/n8n-data.tar.gz" >/dev/null 2>&1; then
    FILE_COUNT=$(tar tzf "${EXTRACTED_DIR}/n8n-data.tar.gz" 2>/dev/null | wc -l)
    ok "n8n data archive is valid (${FILE_COUNT} files/dirs)"
  else
    fail "n8n data archive is corrupt"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Print manifest
# ---------------------------------------------------------------------------
if [ -f "${EXTRACTED_DIR}/MANIFEST.txt" ]; then
  log "Backup manifest:"
  cat "${EXTRACTED_DIR}/MANIFEST.txt" | while IFS= read -r line; do
    log "  ${line}"
  done
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [ "${VERIFY_EXIT}" -eq 0 ]; then
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}  Backup Verification PASSED${NC}"
  echo -e "${GREEN}  $(basename ${LATEST_BACKUP})${NC}"
  echo -e "${GREEN}========================================${NC}"
else
  echo -e "${RED}========================================${NC}"
  echo -e "${RED}  Backup Verification FAILED${NC}"
  echo -e "${RED}========================================${NC}"
fi

exit "${VERIFY_EXIT}"
