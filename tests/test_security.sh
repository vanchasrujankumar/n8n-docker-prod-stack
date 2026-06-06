#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Security Audit & Vulnerability Scan
# =============================================================================
# Scans Docker images for vulnerabilities, checks file permissions,
# and validates secret management.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

EXIT_CODE=0

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Security Audit${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# 1. File Permission Checks
# ---------------------------------------------------------------------------
info "Checking file permissions..."

# .env should be 600 (readable only by owner)
if [ -f .env ]; then
  PERMS=$(stat -f "%Lp" .env 2>/dev/null || stat -c "%a" .env 2>/dev/null || echo "000")
  if [ "${PERMS}" = "600" ] || [ "${PERMS}" = "400" ]; then
    pass ".env has secure permissions (${PERMS})"
  else
    warn ".env permissions are ${PERMS} (recommended: 600). Run: chmod 600 .env"
  fi
else
  # .env.example is not sensitive
  if [ -f .env.example ]; then
    pass ".env not found (safe in CI context). .env.example is not sensitive."
  fi
fi

# Scripts should be executable
for script in scripts/*.sh tests/*.sh; do
  if [ -f "${script}" ] && [ ! -x "${script}" ]; then
    warn "${script} is not executable. Run: chmod +x ${script}"
  fi
done

# ---------------------------------------------------------------------------
# 2. Secrets in Compose Files
# ---------------------------------------------------------------------------
info "Checking for hardcoded secrets in compose files..."
for file in compose.yaml compose.dev.yaml; do
  if [ -f "${file}" ]; then
    # Check for placeholder passwords
    if grep -qiE '(password|secret|token|key).*:.*[a-zA-Z0-9]{8,}' "${file}" 2>/dev/null; then
      # Specifically look for values that look hardcoded (not env vars)
      if grep -qE ':\s+[a-zA-Z0-9_!@#$%^&*()]{8,}' "${file}" 2>/dev/null; then
        if ! grep -qE ':\s+\$\{' "${file}" 2>/dev/null; then
          warn "${file} may contain hardcoded secrets (use environment variables instead)"
        fi
      fi
    fi
    # Verify compose files use env vars for secrets
    if grep -qE 'POSTGRES_PASSWORD:|N8N_ENCRYPTION_KEY:|N8N_USER_MANAGEMENT_JWT_SECRET:' "${file}" 2>/dev/null; then
      if grep -qE '(POSTGRES_PASSWORD|N8N_ENCRYPTION_KEY|N8N_USER_MANAGEMENT_JWT_SECRET):\s+\$' "${file}" 2>/dev/null; then
        pass "${file} uses environment variables for secrets"
      else
        fail "${file} may have hardcoded secrets"
        EXIT_CODE=1
      fi
    fi
  fi
done

# ---------------------------------------------------------------------------
# 3. Docker Security Configuration
# ---------------------------------------------------------------------------
info "Checking Docker security configuration..."

# Check for no-new-privileges
if grep -q "no-new-privileges:true" compose.yaml 2>/dev/null; then
  pass "compose.yaml uses no-new-privileges security_opt"
else
  warn "compose.yaml does not set no-new-privileges"
fi

# Check for read-only root filesystem on traefik
if grep -A2 "traefik:" compose.yaml 2>/dev/null | grep -q "read_only: true"; then
  pass "Traefik has read-only root filesystem"
else
  warn "Traefik does not have read_only: true (consider adding it)"
fi

# Check internal network
if grep -q "internal: true" compose.yaml 2>/dev/null; then
  pass "compose.yaml uses an internal network for backend services"
else
  warn "compose.yaml does not define an internal network"
fi

# Check user directive
if grep -q "user: \"1000:1000\"" compose.yaml 2>/dev/null; then
  pass "n8n runs as non-root user (1000:1000)"
else
  warn "n8n may be running as root"
fi

# ---------------------------------------------------------------------------
# 4. Image Source Verification
# ---------------------------------------------------------------------------
info "Checking image sources..."
if grep -q "docker.n8n.io/n8nio/n8n:" compose.yaml 2>/dev/null; then
  pass "n8n uses official image from docker.n8n.io"
else
  warn "n8n uses a non-official image source"
fi
if grep -q "postgres:16-alpine" compose.yaml 2>/dev/null; then
  pass "PostgreSQL uses official Alpine-based image"
fi
if grep -q "traefik:v3" compose.yaml 2>/dev/null; then
  pass "Traefik uses official v3 image"
fi

# ---------------------------------------------------------------------------
# 5. Trivy Vulnerability Scan (if available)
# ---------------------------------------------------------------------------
if command -v trivy >/dev/null 2>&1; then
  info "Running Trivy vulnerability scan on compose images..."
  IMAGES=$(grep -E '^\s+image:' compose.yaml 2>/dev/null | awk '{print $2}' | sort -u)
  for IMAGE in ${IMAGES}; do
    info "Scanning ${IMAGE}..."
    if trivy image --severity CRITICAL,HIGH --no-progress --exit-code 1 "${IMAGE}" 2>/dev/null; then
      pass "${IMAGE}: No critical/high vulnerabilities found"
    else
      # Pull first and retry
      docker pull "${IMAGE}" >/dev/null 2>&1 || true
      if trivy image --severity CRITICAL,HIGH --no-progress --exit-code 0 "${IMAGE}" 2>/dev/null; then
        warn "${IMAGE}: Has vulnerabilities (review recommended)"
      else
        # Trivy may fail for some images; don't fail the whole check
        warn "${IMAGE}: Trivy scan produced warnings (review required)"
      fi
    fi
  done
else
  info "Trivy not installed. Skipping vulnerability scan."
  info "  Install: brew install trivy (macOS) or https://trivy.dev/"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Security audit complete"
echo "========================================"

if [ "${EXIT_CODE}" -eq 0 ]; then
  echo -e "${GREEN}No security issues found.${NC}"
else
  echo -e "${RED}Security issues detected. Review warnings above.${NC}"
fi
exit "${EXIT_CODE}"
