#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# n8n Production Stack - Setup Script
# =============================================================================
# Run this once on a fresh server to bootstrap the n8n deployment.
#   curl -fsSL https://raw.githubusercontent.com/vanchasrujankumar/n8n-docker-prod-stack/main/scripts/setup.sh | bash
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[setup]${NC} $1"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ---------------------------------------------------------------------------
# Prerequisites Check
# ---------------------------------------------------------------------------
log "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || err "Docker is not installed. Install it first: https://docs.docker.com/engine/install/"
command -v docker compose >/dev/null 2>&1 || err "Docker Compose is not available."

DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
log "Docker version: ${DOCKER_VERSION}"

# Docker Compose v2 check
docker compose version >/dev/null 2>&1 || err "Docker Compose v2 plugin is required."

ok "All prerequisites met."

# ---------------------------------------------------------------------------
# Create Docker Network
# ---------------------------------------------------------------------------
log "Creating external Docker network 'n8n-web' if not exists..."
docker network inspect n8n-web >/dev/null 2>&1 && ok "Network 'n8n-web' already exists." || {
  docker network create n8n-web --driver bridge --attachable
  ok "Network 'n8n-web' created."
}

# ---------------------------------------------------------------------------
# Create Directories
# ---------------------------------------------------------------------------
log "Creating directories..."
mkdir -p docker/n8n/scripts docker/traefik
ok "Directories created."

# ---------------------------------------------------------------------------
# Set Permissions
# ---------------------------------------------------------------------------
log "Setting filesystem permissions (UID/GID 1000 for n8n)..."
chown -R 1000:1000 docker/n8n 2>/dev/null || warn "Could not chown docker/n8n (may require sudo). Run: sudo chown -R 1000:1000 docker/n8n"
ok "Permissions set."

# ---------------------------------------------------------------------------
# Generate Secrets
# ---------------------------------------------------------------------------
log "Generating secure random secrets..."
ENCRYPTION_KEY=$(openssl rand -hex 32 2>/dev/null || echo "change_me_encryption_key_placeholder_32chars")
JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || echo "change_me_jwt_secret_placeholder_32chars")
DB_PASSWORD=$(openssl rand -base64 24 2>/dev/null || echo "change_me_db_password_placeholder")
ok "Secrets generated."

# ---------------------------------------------------------------------------
# Create .env from template if not exists
# ---------------------------------------------------------------------------
if [ -f .env ]; then
  warn ".env already exists. Skipping creation. Review it manually: nano .env"
else
  if [ ! -f .env.example ]; then
    err ".env.example not found. Ensure the project files are present."
  fi
  cp .env.example .env
  log "Populating .env with generated secrets..."

  # Determine hostname
  HOSTNAME_VAR="${N8N_HOST:-$(hostname -f 2>/dev/null || echo 'n8n.example.com')}"
  DOMAIN_VAR="${DOMAIN_NAME:-${HOSTNAME_VAR}}"

  # Use portable sed for macOS/Linux
  sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "$@"
    else
      sed -i "$@"
    fi
  }

  sed_i "s/^DOMAIN_NAME=.*/DOMAIN_NAME=${DOMAIN_VAR}/" .env
  sed_i "s/^N8N_HOST=.*/N8N_HOST=${HOSTNAME_VAR}/" .env
  sed_i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" .env
  sed_i "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}/" .env
  sed_i "s/^N8N_USER_MANAGEMENT_JWT_SECRET=.*/N8N_USER_MANAGEMENT_JWT_SECRET=${JWT_SECRET}/" .env

  ok ".env file created with generated secrets."
  warn "IMPORTANT: Review .env and fill in: SSL_EMAIL, N8N_HOST, DOMAIN_NAME, and Traefik auth."
fi

# ---------------------------------------------------------------------------
# Generate htpasswd for Traefik dashboard
# ---------------------------------------------------------------------------
if command -v htpasswd >/dev/null 2>&1; then
  if grep -q "TRAEFIK_AUTH_PASS_HASH=" .env && [ "$(grep 'TRAEFIK_AUTH_PASS_HASH=' .env | cut -d= -f2)" = "" ]; then
    log "Generating Traefik dashboard credentials..."
    read -r -p "Enter Traefik dashboard username [admin]: " TRAEFIK_USER
    TRAEFIK_USER="${TRAEFIK_USER:-admin}"
    read -r -s -p "Enter Traefik dashboard password: " TRAEFIK_PASS
    echo
    HASH=$(htpasswd -nb "${TRAEFIK_USER}" "${TRAEFIK_PASS}" 2>/dev/null | sed -e 's/\$/\$\$/g')
    sed_i "s/^TRAEFIK_AUTH_USER=.*/TRAEFIK_AUTH_USER=${TRAEFIK_USER}/" .env
    sed_i "s/^TRAEFIK_AUTH_PASS_HASH=.*/TRAEFIK_AUTH_PASS_HASH=${HASH}/" .env
    ok "Traefik dashboard credentials set."
  fi
else
  warn "htpasswd not found. Install apache2-utils (apt) or httpd-tools (yum) to set Traefik auth."
  warn "Edit .env manually to set TRAEFIK_AUTH_USER and TRAEFIK_AUTH_PASS_HASH."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  n8n Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Next steps:"
echo "    1. Review .env and fill in missing values:"
echo "       - SSL_EMAIL (for Let's Encrypt notifications)"
echo "       - N8N_HOST (your n8n domain)"
echo "       - DOMAIN_NAME (your base domain)"
echo "       - TRAEFIK_AUTH_PASS_HASH (if not set above)"
echo "    2. Ensure DNS A record points to this server"
echo "    3. Run: docker compose up -d"
echo "    4. Check logs: docker compose logs -f"
echo ""
