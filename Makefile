.PHONY: help env-check start stop status logs setup verify demo reset clean shell-vault shell-server shell-client
.DEFAULT_GOAL := help

-include .env
export

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-14s\033[0m %s\n", $$1, $$2}'

env-check: ## Check prerequisites and create .env if missing
	@command -v docker >/dev/null 2>&1 || { echo "❌ docker is required"; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "❌ docker compose is required"; exit 1; }
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "ℹ️  Created .env from .env.example"; \
	fi
	@mkdir -p shared/client shared/server artifacts
	@touch shared/.gitkeep shared/client/.gitkeep shared/server/.gitkeep artifacts/.gitkeep
	@echo "✅ Environment check passed"

start: env-check ## Start Docker services
	@echo "🚀 Starting services..."
	@docker compose up -d --build
	@echo "✅ Services started"

stop: ## Stop Docker services
	@echo "🛑 Stopping services..."
	@docker compose down
	@echo "✅ Services stopped"

status: ## Show container status
	@docker compose ps

logs: ## Tail logs from all services
	@docker compose logs -f

setup: start ## Start services and initialize Vault SSH demo
	@chmod +x init.sh
	@./init.sh

verify: ## Verify Vault and SSH trust material
	@echo "📊 Container status"
	@docker compose ps
	@echo ""
	@if [ ! -f artifacts/vault-init.json ]; then \
		echo "❌ Vault has not been initialized yet. Run 'make setup'."; \
		exit 1; \
	fi
	@ROOT_TOKEN=$$(python3 -c "import json;print(json.load(open('artifacts/vault-init.json'))['root_token'])"); \
	docker compose exec -T vault sh -lc "export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='$$ROOT_TOKEN'; vault status"
	@echo ""
	@echo "🔐 Host certificate summary"
	@docker compose exec -T linux-server sh -lc "ssh-keygen -Lf /demo/server/ssh_host_ed25519_key-cert.pub | sed -n '1,12p'"
	@echo ""
	@echo "✅ Verification complete"

demo: ## Run the interactive demo
	@chmod +x demo.sh
	@./demo.sh

reset: ## Reset the environment for another run
	@echo "🔄 Resetting demo environment..."
	@docker compose down -v --remove-orphans
	@rm -f artifacts/* shared/client/demo.env shared/client/known_hosts shared/client/config
	@rm -f shared/server/ssh_host_ed25519_key shared/server/ssh_host_ed25519_key.pub shared/server/ssh_host_ed25519_key-cert.pub shared/server/trusted-user-ca-keys.pem
	@touch shared/.gitkeep shared/client/.gitkeep shared/server/.gitkeep artifacts/.gitkeep
	@$(MAKE) setup

clean: ## Remove containers, volumes, and generated artifacts
	@echo "🧹 Cleaning up demo environment..."
	@docker compose down -v --remove-orphans
	@rm -f demo-magic.sh
	@rm -f artifacts/* shared/client/demo.env shared/client/known_hosts shared/client/config
	@rm -f shared/server/ssh_host_ed25519_key shared/server/ssh_host_ed25519_key.pub shared/server/ssh_host_ed25519_key-cert.pub shared/server/trusted-user-ca-keys.pem
	@touch shared/.gitkeep shared/client/.gitkeep shared/server/.gitkeep artifacts/.gitkeep
	@echo "✅ Cleanup complete"

shell-vault: ## Open a shell in the Vault container
	@docker compose exec vault sh

shell-server: ## Open a shell in the SSH server container
	@docker compose exec linux-server bash

shell-client: ## Open a shell in the client container as the demo user
	@docker compose exec -u demo linux-client bash
