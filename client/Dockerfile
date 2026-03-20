FROM hashicorp/vault:latest AS vaultbin

FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    bash \
    ca-certificates \
    curl \
    jq \
    less \
    procps \
    iputils-ping \
  && rm -rf /var/lib/apt/lists/*

COPY --from=vaultbin /bin/vault /usr/local/bin/vault

RUN useradd -m -s /bin/bash demo \
  && mkdir -p /demo/client /home/demo/.ssh \
  && chown -R demo:demo /home/demo

COPY client/entrypoint.sh /usr/local/bin/client-entrypoint.sh
RUN chmod +x /usr/local/bin/client-entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/client-entrypoint.sh"]
