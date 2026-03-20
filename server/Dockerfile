FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    openssh-client \
    bash \
    ca-certificates \
    curl \
    jq \
    procps \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash demo \
  && mkdir -p /var/run/sshd /demo/server /home/demo/.ssh \
  && passwd -d demo \
  && chown -R demo:demo /home/demo

COPY server/entrypoint.sh /usr/local/bin/server-entrypoint.sh
RUN chmod +x /usr/local/bin/server-entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/server-entrypoint.sh"]
