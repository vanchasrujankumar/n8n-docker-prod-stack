.PHONY: setup dev prod logs ps stop restart update backup backup-to \
        health test test-security lint clean shellcheck help

SHELL := /bin/bash

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
setup:
	@echo "==> Running initial setup..."
	@bash scripts/setup.sh

# ---------------------------------------------------------------------------
# Start environments
# ---------------------------------------------------------------------------
dev: check-dir
	@echo "==> Starting development stack..."
	@bash scripts/deploy.sh dev

prod: check-dir check-env
	@echo "==> Starting production stack..."
	@docker network inspect n8n-web >/dev/null 2>&1 || docker network create n8n-web
	@docker compose pull
	@docker compose up -d --remove-orphans

prod-build: check-dir check-env
	@echo "==> Building and starting production stack..."
	@docker network inspect n8n-web >/dev/null 2>&1 || docker network create n8n-web
	@docker compose up -d --build --remove-orphans

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
logs:
	@echo "==> Tailing logs..."
	@docker compose logs -f

logs-dev:
	@echo "==> Tailing dev stack logs..."
	@docker compose -f compose.dev.yaml logs -f

logs-n8n:
	@docker compose logs -f n8n

logs-db:
	@docker compose logs -f postgres

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
ps:
	@docker compose ps

ps-dev:
	@docker compose -f compose.dev.yaml ps

stats:
	@docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}'

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
stop:
	@docker compose down

stop-dev:
	@docker compose -f compose.dev.yaml down

restart:
	@docker compose restart

restart-dev:
	@docker compose -f compose.dev.yaml restart

down:
	@docker compose down -v --remove-orphans

down-dev:
	@docker compose -f compose.dev.yaml down -v --remove-orphans

# ---------------------------------------------------------------------------
# Updates
# ---------------------------------------------------------------------------
update: check-env
	@echo "==> Updating production stack..."
	@docker compose pull
	@docker compose up -d --remove-orphans
	@echo "==> Pruning old images..."
	@docker image prune -f

update-dev: check-dir
	@echo "==> Updating development stack..."
	@docker compose -f compose.dev.yaml pull
	@docker compose -f compose.dev.yaml up -d --remove-orphans

# ---------------------------------------------------------------------------
# Backup & Restore
# ---------------------------------------------------------------------------
backup:
	@bash scripts/backup.sh

backup-to:
	@if [ -z "$(path)" ]; then echo "Usage: make backup-to path=/absolute/path"; exit 1; fi
	@bash scripts/backup.sh $(path)

# ---------------------------------------------------------------------------
# Health & Tests
# ---------------------------------------------------------------------------
health:
	@bash scripts/healthcheck.sh

health-dev:
	@bash scripts/healthcheck.sh dev

test: test-health test-security

test-health:
	@bash tests/test_health.sh

test-security:
	@bash tests/test_security.sh

# ---------------------------------------------------------------------------
# Lint
# ---------------------------------------------------------------------------
lint:
	@echo "==> Linting compose files..."
	@docker compose -f compose.yaml config --quiet && echo "  compose.yaml: OK" || echo "  compose.yaml: FAIL"
	@docker compose -f compose.dev.yaml config --quiet && echo "  compose.dev.yaml: OK" || echo "  compose.dev.yaml: FAIL"

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "==> Running shellcheck..."; \
		shellcheck scripts/*.sh tests/*.sh; \
	else \
		echo "shellcheck not installed. Run: brew install shellcheck"; \
	fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
clean:
	@echo "==> Stopping all stacks and removing volumes..."
	@docker compose down -v --remove-orphans 2>/dev/null || true
	@docker compose -f compose.dev.yaml down -v --remove-orphans 2>/dev/null || true
	@echo "==> Pruning unused Docker resources..."
	@docker system prune -f --volumes 2>/dev/null || true
	@echo "Done."

clean-all: clean
	@echo "==> Removing all Docker resources (images, networks)..."
	@docker network rm n8n-web 2>/dev/null || true
	@docker network rm n8n-dev-internal 2>/dev/null || true
	@echo "Done."

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help:
	@echo ""
	@echo "  n8n Docker Stack - Makefile Commands"
	@echo "  ===================================="
	@echo ""
	@echo "  SETUP:"
	@echo "    make setup           Initial server setup (dirs, secrets, .env)"
	@echo ""
	@echo "  DEPLOY:"
	@echo "    make dev             Start development stack"
	@echo "    make prod            Start production stack"
	@echo "    make prod-build      Build and start production stack"
	@echo ""
	@echo "  LOGS:"
	@echo "    make logs            Tail production logs"
	@echo "    make logs-dev        Tail development logs"
	@echo "    make logs-n8n        Tail n8n logs only"
	@echo "    make logs-db         Tail PostgreSQL logs only"
	@echo ""
	@echo "  STATUS:"
	@echo "    make ps              List production containers"
	@echo "    make ps-dev          List development containers"
	@echo "    make stats           Show resource usage"
	@echo ""
	@echo "  LIFECYCLE:"
	@echo "    make stop            Stop production stack"
	@echo "    make stop-dev        Stop development stack"
	@echo "    make restart         Restart production stack"
	@echo "    make down            Stop and remove volumes (production)"
	@echo ""
	@echo "  UPDATE:"
	@echo "    make update          Pull latest images and recreate production"
	@echo "    make update-dev      Pull latest images and recreate development"
	@echo ""
	@echo "  BACKUP:"
	@echo "    make backup          Backup database and volumes"
	@echo "    make backup-to       Backup to custom path: make backup-to path=/mnt/backups"
	@echo ""
	@echo "  HEALTH:"
	@echo "    make health          Run production health check"
	@echo "    make health-dev      Run development health check"
	@echo "    make test            Run all tests"
	@echo "    make test-health     Run health tests"
	@echo "    make test-security   Run security audit"
	@echo ""
	@echo "  LINT:"
	@echo "    make lint            Validate compose files"
	@echo "    make shellcheck      Lint shell scripts"
	@echo ""
	@echo "  CLEANUP:"
	@echo "    make clean           Stop stacks and prune unused resources"
	@echo "    make clean-all       Full cleanup including networks"
	@echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
check-dir:
	@if [ ! -d "scripts" ] || [ ! -f "compose.yaml" ]; then \
		echo "Error: Run from the project root directory."; \
		exit 1; \
	fi

check-env:
	@if [ ! -f ".env" ]; then \
		echo "Error: .env file not found. Run 'make setup' or 'cp .env.example .env' first."; \
		exit 1; \
	fi
