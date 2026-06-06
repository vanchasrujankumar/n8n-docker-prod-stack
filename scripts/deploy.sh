#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# n8n Production Stack - Deploy Script
# =============================================================================
# Pulls latest images and deploys the full stack in detached mode.
#   ./scripts/deploy.sh              # Deploy with .env (production)
#   ./scripts/deploy.sh dev          # Deploy with .env.dev (development)
#   ./scripts/deploy.sh prod         # Explicit production deploy
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[deploy]${NC} $1"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ---------------------------------------------------------------------------
# Determine environment
# ---------------------------------------------------------------------------
ENV="${1:-prod}"
COMPOSE_FILE="compose.yaml"
ENV_FILE=".env"

case "${ENV}" in
  prod|production)
    ENV="prod"
    COMPOSE_FILE="compose.yaml"
    ENV_FILE=".env"
    STACK_NAME="n8n"
    ;;
  dev|development)
    ENV="dev"
    COMPOSE_FILE="compose.dev.yaml"
    ENV_FILE=".env.dev"
    STACK_NAME="n8n-dev"
    ;;
  *)
    err "Unknown environment '${ENV}'. Use: prod, dev"
    ;;
esac

if [ ! -f "${ENV_FILE}" ]; then
  err "Environment file '${ENV_FILE}' not found. Run ./scripts/setup.sh or copy ${ENV_FILE}.example to ${ENV_FILE}"
fi

log "Deploying ${ENV} stack using ${COMPOSE_FILE} with ${ENV_FILE}"

# ---------------------------------------------------------------------------
# Pre-deployment checks
# ---------------------------------------------------------------------------
log "Running pre-deployment checks..."
docker compose version >/dev/null 2>&1 || err "Docker Compose v2 not available."

# Check required tools
for cmd in docker curl; do
  command -v "${cmd}" >/dev/null 2>&1 || err "${cmd} is not installed."
done

if [ "${ENV}" = "prod" ]; then
  # Verify DNS resolves for the domain
  N8N_HOST=$(grep -E '^N8N_HOST=' "${ENV_FILE}" | cut -d= -f2- | tr -d '"'"'" 2>/dev/null || echo "")
  if [ -n "${N8N_HOST}" ] && [ "${N8N_HOST}" != "localhost" ]; then
    log "Checking DNS resolution for ${N8N_HOST}..."
    SERVER_IP=$(curl -fsSL http://checkip.amazonaws.com 2>/dev/null || curl -fsSL https://api.ipify.org 2>/dev/null || echo "unknown")
    DOMAIN_IP=$(dig +short "${N8N_HOST}" 2>/dev/null || nslookup "${N8N_HOST}" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -1 || echo "unknown")
    if [ "${SERVER_IP}" != "unknown" ] && [ "${DOMAIN_IP}" != "unknown" ] && [ "${SERVER_IP}" != "${DOMAIN_IP}" ]; then
      warn "Server IP (${SERVER_IP}) does not match DNS A record for ${N8N_HOST} (${DOMAIN_IP}). SSL certificate issuance may fail."
    fi
  fi
fi

ok "Pre-deployment checks passed."

# ---------------------------------------------------------------------------
# Pull latest images
# ---------------------------------------------------------------------------
log "Pulling latest Docker images..."
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull --quiet 2>/dev/null || {
  warn "Some images could not be pulled. Continuing with cached images."
}
ok "Images pulled."

# ---------------------------------------------------------------------------
# Deploy stack
# ---------------------------------------------------------------------------
log "Deploying stack..."
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" -p "${STACK_NAME}" up -d --remove-orphans
ok "Stack deployed."

# ---------------------------------------------------------------------------
# Wait for health
# ---------------------------------------------------------------------------
log "Waiting for services to become healthy..."
MAX_RETRIES=30
RETRY_INTERVAL=5

wait_for_container() {
  local container_name="$1"
  local retries=0
  while [ $retries -lt $MAX_RETRIES ]; do
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "unhealthy")
    if [ "${status}" = "healthy" ]; then
      ok "${container_name} is healthy."
      return 0
    fi
    retries=$((retries + 1))
    sleep "${RETRY_INTERVAL}"
  done
  warn "${container_name} did not become healthy within $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
  return 1
}

if [ "${ENV}" = "prod" ]; then
  wait_for_container "n8n-postgres" || warn "PostgreSQL health check timed out."
  wait_for_container "n8n" || warn "n8n health check timed out."
  wait_for_container "n8n-traefik" || warn "Traefik health check timed out."
else
  wait_for_container "n8n-dev-postgres" || warn "PostgreSQL health check timed out."
  wait_for_container "n8n-dev" || warn "n8n health check timed out."
fi

# ---------------------------------------------------------------------------
# Print status
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  n8n ${ENV} stack is running!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" -p "${STACK_NAME}" ps

if [ "${ENV}" = "prod" ]; then
  N8N_HOST=$(grep -E '^N8N_HOST=' "${ENV_FILE}" | cut -d= -f2- | tr -d '"' 2>/dev/null || echo "unknown")
  echo ""
  echo "  Access n8n:    https://${N8N_HOST}"
  echo "  Traefik:       https://traefik.${N8N_HOST#n8n.}"
  echo ""
  echo "  Commands:"
  echo "    Logs:        docker compose logs -f n8n"
  echo "    Restart:     docker compose restart n8n"
  echo "    Stop:        docker compose down"
  echo "    Update:      docker compose pull && docker compose up -d"
else
  echo ""
  echo "  Access n8n:    http://localhost:5678"
  echo ""
  echo "  Commands:"
  echo "    Logs:        docker compose -f compose.dev.yaml logs -f n8n"
  echo "    Restart:     docker compose -f compose.dev.yaml restart n8n"
  echo "    Stop:        docker compose -f compose.dev.yaml down"
fi
echo ""
