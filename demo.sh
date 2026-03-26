#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "demo-magic.sh" ]; then
  echo "Downloading demo-magic.sh..."
  curl -fsSL https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh -o demo-magic.sh
  chmod +x demo-magic.sh
fi

. ./demo-magic.sh

TYPE_SPEED=80
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

clear

################################################################################
# Introduction
################################################################################
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║              Vault SSH signed certificate demo 🚀                        ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo ""
echo "This demo shows one integrated SSH trust story:"
echo ""
echo "  • Vault signs the server host key"
echo "  • the client trusts Vault's host CA"
echo "  • Vault signs the client user key"
echo "  • the server trusts Vault's user CA"
echo ""
echo "The login path is real SSH. We are not using docker exec as the auth path."
echo ""
echo -e "${YELLOW}Press ENTER to continue...${COLOR_RESET}"

wait
clear

################################################################################
# Section 1: Verify the lab
################################################################################
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                 Section 1: Verify the lab                                ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo ""
echo "First, verify that Vault is unsealed and the server host certificate exists."
echo ""

p "# Check container status"
pe "docker compose ps"
echo ""

p "# Check Vault status"
pe "make verify"
echo ""

wait
clear

################################################################################
# Section 2: Host trust only
################################################################################
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                 Section 2: Host trust only                               ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo ""
echo "The client can already verify the server through Vault's host CA."
echo "Authentication should still fail, because we have not signed a user key yet."
echo ""

p "# Inspect the server host certificate"
pe "docker compose exec linux-server bash -lc 'ssh-keygen -Lf /demo/server/ssh_host_ed25519_key-cert.pub | sed -n \"1,12p\"'"
echo ""

p "# Attempt SSH without a user certificate"
pe "docker compose exec -u demo linux-client bash -lc 'ssh -o BatchMode=yes -o PreferredAuthentications=none server.demo.internal true || true'"
echo ""

echo -e "${GREEN}Key point:${COLOR_RESET} host trust succeeds first, then SSH fails at user authentication."
echo ""

wait
clear

################################################################################
# Section 3: Sign a user key
################################################################################
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                 Section 3: Sign a user key                               ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo ""
echo "Now generate a client keypair and ask Vault to sign the public key."
echo ""

p "# Generate the client keypair if it does not exist yet"
pe "docker compose exec -u demo linux-client bash -lc 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -N \"\" -f ~/.ssh/id_ed25519'"
echo ""

p "# Request a signed user certificate from Vault"
pe "docker compose exec -u demo linux-client bash -lc 'source /demo/client/demo.env && vault write -field=signed_key ssh-client-signer/sign/demo-user public_key=@\$HOME/.ssh/id_ed25519.pub valid_principals=demo > \$HOME/.ssh/id_ed25519-cert.pub'"
echo ""

p "# Inspect the signed user certificate"
pe "docker compose exec -u demo linux-client bash -lc 'ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub'"
echo ""

wait
clear

################################################################################
# Section 4: Real SSH login
################################################################################
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                 Section 4: Real SSH login                                ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo ""
echo "Now the client proves its identity with a Vault-signed user certificate."
echo "The certificate includes the permit-pty extension, so a real shell can open."
echo ""

p "# Open a real interactive SSH session to the target host"
echo "When the remote shell opens, run:"
echo "  hostname"
echo "  whoami"
echo "  exit"
echo ""
pe "docker compose exec -it -u demo linux-client bash -lc 'ssh server.demo.internal'"
echo ""

echo -e "${GREEN}Key points:${COLOR_RESET}"
echo "  • The client trusted the server through the host CA"
echo "  • The server trusted the client through the user CA"
echo "  • Neither private key left its own machine"
echo ""

wait
clear

################################################################################
# Conclusion
################################################################################
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                          Demo complete! 🎉                               ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo ""
echo "You demonstrated:"
echo ""
echo "  ✅ host trust with a Vault-signed host certificate"
echo "  ✅ user authentication with a Vault-signed user certificate"
echo "  ✅ real SSH login between two containers"
echo ""
echo "Useful commands:"
echo "  make shell-client"
echo "  make shell-server"
echo "  make shell-vault"
echo "  make reset"
echo "  make clean"
echo ""
