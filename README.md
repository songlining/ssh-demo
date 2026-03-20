# Vault SSH signed certificate demo

Interactive Docker Compose lab for the Vault SSH secrets engine using the latest Vault Community Edition image.

This demo uses exactly three long-running containers:

- `vault` - Vault Community Edition with two SSH signer mounts
- `linux-server` - OpenSSH server that trusts Vault user certificates and presents a Vault-signed host certificate
- `linux-client` - Linux client used to request certificates from Vault and perform real SSH logins

The demo follows the signed SSH certificate workflow from the HashiCorp documentation:

- user certificates for client authentication
- host certificates for server identity

## What this lab shows

Phase 1: host trust

- Vault signs the server host public key
- the client trusts Vault's host CA
- SSH reaches authentication without a host authenticity prompt

Phase 2: user authentication

- Vault signs the client user public key
- the server trusts Vault's user CA
- the client logs in with a short-lived SSH certificate

## Prerequisites

- Docker
- Docker Compose
- Make
- `python3`
- `curl` for the optional guided demo script

## Quick start

```bash
cp .env.example .env
make setup
make verify
```

Then either:

- run the guided flow with `make demo`
- or run the manual commands below

## Manual demo flow

Open a shell in the client container:

```bash
make shell-client
```

Inside the client shell:

```bash
source /demo/client/demo.env
ssh -o BatchMode=yes -o PreferredAuthentications=none server.demo.internal true
```

That should fail on authentication, but it should not fail on host trust.

Generate a user keypair:

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
```

Ask Vault to sign the client public key:

```bash
vault write -field=signed_key ssh-client-signer/sign/demo-user \
  public_key=@$HOME/.ssh/id_ed25519.pub \
  valid_principals=demo > $HOME/.ssh/id_ed25519-cert.pub
```

Inspect the signed certificate:

```bash
ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub
```

Log in:

```bash
ssh server.demo.internal
hostname
whoami
exit
```

## Available commands

- `make setup` - build containers, start services, and bootstrap Vault
- `make verify` - verify Vault and generated trust material
- `make demo` - run the guided terminal demo
- `make shell-client` - open a shell in the client container as `demo`
- `make shell-server` - open a shell in the server container
- `make shell-vault` - open a shell in the Vault container
- `make reset` - tear down and recreate the lab
- `make clean` - remove containers, volumes, and generated files

## Generated files

Bootstrap writes files into:

- `artifacts/vault-init.json` - Vault init output for this local lab
- `shared/server/` - server trust files and host certificate
- `shared/client/` - client trust files and Vault environment helper

These files are only for the local demo lab.

## Architecture notes

- Vault runs two signer mounts on one CE server:
  - `ssh-client-signer`
  - `ssh-host-signer`
- the server keeps its host private key locally
- the client keeps its user private key locally
- no extra OTP helper is used because this lab is certificate-based
- `docker exec` is only for setup and inspection, not for the login demo path

## Reference

- https://developer.hashicorp.com/vault/docs/secrets/ssh/signed-ssh-certificates
