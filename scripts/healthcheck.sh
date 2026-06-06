#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# n8n Production Stack - Health Check Script
# =============================================================================
# Checks all services are running and healthy. Exits with non-zero on failure.
#   ./scripts/healthcheck.sh         # Check production stack
#   ./scripts/healthcheck.sh dev     # Check development stack
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

ENV="${1:-prod}"
EXIT_CODE=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; EXIT_CODE=1; }

check_container() {
  local name="$1"
  local status
  status=$(docker inspect --format='{{.State.Status}}' "${name}" 2>/dev/null || echo "not-found")
  if [ "${status}" != "running" ]; then
    fail "Container '${name}' is ${status} (expected running)"
    return 1
  fi
  local health
  health=$(docker inspect --format='{{.State.Health.Status}}' "${name}" 2>/dev/null || echo "no-healthcheck")
  if [ "${health}" != "healthy" ] && [ "${health}" != "no-healthcheck" ]; then
    fail "Container '${name}' health is ${health}"
    return 1
  fi
  pass "Container '${name}' is running (health: ${health})"
}

check_http() {
  local url="$1"
  local expected_code="${2:-200}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${url}" 2>/dev/null || echo "failed")
  if [ "${code}" = "${expected_code}" ]; then
    pass "HTTP ${url} -> ${code}"
  else
    fail "HTTP ${url} -> ${code} (expected ${expected_code})"
  fi
}

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  n8n Health Check (${ENV})${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

if [ "${ENV}" = "prod" ]; then
  check_container "n8n-traefik"
  check_container "n8n-postgres"
  check_container "n8n"
  [ -f .env ] && N8N_HOST=$(grep -E '^N8N_HOST=' .env | cut -d= -f2- | tr -d '"' 2>/dev/null || echo "")
  [ -n "${N8N_HOST}" ] && check_http "https://${N8N_HOST}/healthz" 200
  check_http "http://localhost:5678/healthz" 200
else
  check_container "n8n-dev-postgres"
  check_container "n8n-dev"
  check_http "http://localhost:5678/healthz" 200
fi

echo ""
if [ "${EXIT_CODE}" -eq 0 ]; then
  echo -e "${GREEN}All checks passed.${NC}"
else
  echo -e "${RED}Some checks failed.${NC}"
fi
echo ""

exit "${EXIT_CODE}"
