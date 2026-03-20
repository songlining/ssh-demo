#!/usr/bin/env bash
set -euo pipefail

mkdir -p /var/run/sshd /demo/server /home/demo/.ssh
touch /demo/server/trusted-user-ca-keys.pem

if [ ! -f /demo/server/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N "" -f /demo/server/ssh_host_ed25519_key
fi

chmod 0600 /demo/server/ssh_host_ed25519_key
chmod 0644 /demo/server/ssh_host_ed25519_key.pub /demo/server/trusted-user-ca-keys.pem
if [ -f /demo/server/ssh_host_ed25519_key-cert.pub ]; then
  chmod 0644 /demo/server/ssh_host_ed25519_key-cert.pub
fi

cat > /etc/ssh/sshd_config <<'EOF'
Port 22
Protocol 2
AddressFamily any
ListenAddress 0.0.0.0
PermitRootLogin no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
TrustedUserCAKeys /demo/server/trusted-user-ca-keys.pem
HostKey /demo/server/ssh_host_ed25519_key
AllowUsers demo
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp /usr/lib/openssh/sftp-server
PidFile /var/run/sshd.pid
LogLevel VERBOSE
EOF

if [ -f /demo/server/ssh_host_ed25519_key-cert.pub ]; then
  echo "HostCertificate /demo/server/ssh_host_ed25519_key-cert.pub" >> /etc/ssh/sshd_config
fi

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
