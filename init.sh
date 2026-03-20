#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
SHARED_DIR="${ROOT_DIR}/shared"
SERVER_SHARED_DIR="${SHARED_DIR}/server"
CLIENT_SHARED_DIR="${SHARED_DIR}/client"
INIT_FILE="${ARTIFACTS_DIR}/vault-init.json"

SSH_DEMO_DOMAIN="${SSH_DEMO_DOMAIN:-demo.internal}"
SSH_DEMO_USER="${SSH_DEMO_USER:-demo}"
SERVER_FQDN="server.${SSH_DEMO_DOMAIN}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "${ARTIFACTS_DIR}" "${SERVER_SHARED_DIR}" "${CLIENT_SHARED_DIR}"
touch "${ARTIFACTS_DIR}/.gitkeep" "${SHARED_DIR}/.gitkeep" "${SERVER_SHARED_DIR}/.gitkeep" "${CLIENT_SHARED_DIR}/.gitkeep"

wait_for_vault() {
  echo -e "${YELLOW}⏳ Waiting for Vault API to accept connections...${NC}"
  until docker compose exec -T vault sh -lc "VAULT_ADDR=http://127.0.0.1:8200 vault status >/dev/null 2>&1; code=\$?; [ \$code -eq 0 ] || [ \$code -eq 2 ]"; do
    sleep 2
  done
  echo -e "${GREEN}✅ Vault container is reachable${NC}"
}

read_json_field() {
  local json_file="$1"
  local field="$2"
  python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$json_file" "$field"
}

read_json_list_item() {
  local json_file="$1"
  local field="$2"
  local index="$3"
  python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]][int(sys.argv[3])])" "$json_file" "$field" "$index"
}

vault_exec() {
  local command="$1"
  docker compose exec -T vault sh -lc "export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='${ROOT_TOKEN}'; ${command}"
}

wait_for_server_key() {
  echo -e "${YELLOW}⏳ Waiting for the SSH server to generate its host key...${NC}"
  until [ -f "${SERVER_SHARED_DIR}/ssh_host_ed25519_key.pub" ]; do
    sleep 1
  done
  echo -e "${GREEN}✅ SSH server host key is present${NC}"
}

wait_for_vault

VAULT_STATUS_JSON="$(docker compose exec -T vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 vault status -format=json || true')"
VAULT_INITIALIZED="$(printf '%s' "${VAULT_STATUS_JSON}" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["initialized"]).lower())')"
VAULT_SEALED="$(printf '%s' "${VAULT_STATUS_JSON}" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["sealed"]).lower())')"

if [ "${VAULT_INITIALIZED}" = "false" ]; then
  echo -e "${BLUE}🔧 Initializing Vault...${NC}"
  docker compose exec -T vault sh -lc "VAULT_ADDR=http://127.0.0.1:8200 vault operator init -key-shares=1 -key-threshold=1 -format=json" > "${INIT_FILE}"
  echo -e "${GREEN}✅ Vault initialized${NC}"
fi

if [ ! -f "${INIT_FILE}" ]; then
  echo -e "${RED}❌ Vault is already initialized, but ${INIT_FILE} is missing.${NC}"
  echo -e "${YELLOW}💡 Run 'make reset' to rebuild the lab from scratch.${NC}"
  exit 1
fi

UNSEAL_KEY="$(read_json_list_item "${INIT_FILE}" unseal_keys_b64 0)"
ROOT_TOKEN="$(read_json_field "${INIT_FILE}" root_token)"

if [ "${VAULT_SEALED}" = "true" ]; then
  echo -e "${BLUE}🔓 Unsealing Vault...${NC}"
  docker compose exec -T vault sh -lc "VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal '${UNSEAL_KEY}' >/dev/null"
  echo -e "${GREEN}✅ Vault unsealed${NC}"
fi

echo -e "${BLUE}🔧 Configuring SSH secrets engine mounts...${NC}"

if ! vault_exec "vault secrets list -format=json | grep -q '\"ssh-client-signer/\"'"; then
  vault_exec "vault secrets enable -path=ssh-client-signer ssh >/dev/null"
fi

if ! vault_exec "vault secrets list -format=json | grep -q '\"ssh-host-signer/\"'"; then
  vault_exec "vault secrets enable -path=ssh-host-signer ssh >/dev/null"
fi

vault_exec "vault secrets tune -max-lease-ttl=8760h ssh-host-signer >/dev/null"

if ! vault_exec "vault read ssh-client-signer/config/ca >/dev/null 2>&1"; then
  vault_exec "vault write ssh-client-signer/config/ca generate_signing_key=true >/dev/null"
fi

if ! vault_exec "vault read ssh-host-signer/config/ca >/dev/null 2>&1"; then
  vault_exec "vault write ssh-host-signer/config/ca generate_signing_key=true >/dev/null"
fi

vault_exec "vault write ssh-client-signer/roles/demo-user key_type=ca allow_user_certificates=true allowed_users='${SSH_DEMO_USER}' default_user='${SSH_DEMO_USER}' ttl=30m >/dev/null"
vault_exec "vault write ssh-host-signer/roles/demo-host key_type=ca allow_host_certificates=true allowed_domains='${SSH_DEMO_DOMAIN}' allow_subdomains=true allow_bare_domains=true ttl=24h >/dev/null"

echo -e "${BLUE}🔧 Publishing trust anchors...${NC}"
vault_exec "vault read -field=public_key ssh-client-signer/config/ca" > "${SERVER_SHARED_DIR}/trusted-user-ca-keys.pem"
vault_exec "vault read -field=public_key ssh-host-signer/config/ca" > "${ARTIFACTS_DIR}/host_ca.pub"

chmod 0644 "${SERVER_SHARED_DIR}/trusted-user-ca-keys.pem" "${ARTIFACTS_DIR}/host_ca.pub"

wait_for_server_key

echo -e "${BLUE}🔧 Signing the SSH server host key...${NC}"
vault_exec "vault write -field=signed_key ssh-host-signer/sign/demo-host cert_type=host public_key=@/demo/server/ssh_host_ed25519_key.pub valid_principals='${SERVER_FQDN}' > /demo/server/ssh_host_ed25519_key-cert.pub"
chmod 0644 "${SERVER_SHARED_DIR}/ssh_host_ed25519_key-cert.pub"

cat > "${CLIENT_SHARED_DIR}/known_hosts" <<EOF
@cert-authority *.${SSH_DEMO_DOMAIN} $(cat "${ARTIFACTS_DIR}/host_ca.pub")
EOF

cat > "${CLIENT_SHARED_DIR}/config" <<EOF
Host ${SERVER_FQDN}
  HostName ${SERVER_FQDN}
  User ${SSH_DEMO_USER}
  IdentityFile ~/.ssh/id_ed25519
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  UserKnownHostsFile ~/.ssh/known_hosts
EOF

cat > "${CLIENT_SHARED_DIR}/demo.env" <<EOF
export VAULT_ADDR=http://vault:8200
export VAULT_TOKEN=${ROOT_TOKEN}
export SSH_DEMO_USER=${SSH_DEMO_USER}
export SSH_DEMO_HOST=${SERVER_FQDN}
EOF

chmod 0644 "${CLIENT_SHARED_DIR}/known_hosts" "${CLIENT_SHARED_DIR}/config" "${CLIENT_SHARED_DIR}/demo.env"

echo -e "${BLUE}🔄 Restarting the SSH server so it loads the signed host certificate...${NC}"
docker compose restart linux-server >/dev/null
sleep 2

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗"
echo "║              Vault SSH Demo Ready! 🔐                        ║"
echo -e "╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Quick reference:${NC}"
echo "  Vault UI:               http://localhost:${VAULT_PORT:-8200}"
echo "  SSH server hostname:    ${SERVER_FQDN}"
echo "  Demo user:              ${SSH_DEMO_USER}"
echo "  Root token file:        ${INIT_FILE}"
echo ""
echo "Next steps:"
echo "  1. make verify"
echo "  2. make shell-client"
echo "  3. source /demo/client/demo.env"
echo "  4. ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519"
echo "  5. vault write -field=signed_key ssh-client-signer/sign/demo-user \\"
echo "       public_key=@\$HOME/.ssh/id_ed25519.pub valid_principals=${SSH_DEMO_USER} > \$HOME/.ssh/id_ed25519-cert.pub"
echo "  6. ssh ${SERVER_FQDN}"
