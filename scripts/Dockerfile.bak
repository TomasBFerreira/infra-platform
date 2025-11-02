# --- Stage 1: Builder ---
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

WORKDIR /app

# System deps, Python, Node
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash curl wget unzip git build-essential python3 python3-venv python3-pip \
        docker.io jq coreutils apt-transport-https ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && ln -sf /usr/bin/node /usr/local/bin/node \
    && python3 -m venv /opt/venv \
    && pip install --upgrade pip setuptools wheel \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Terraform
ARG TERRAFORM_VERSION=1.9.8
RUN curl -sLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin/ \
    && rm /tmp/terraform.zip \
    && terraform -version

# Vault
ARG VAULT_VERSION=1.15.2
RUN curl -sLo /tmp/vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip \
    && unzip /tmp/vault.zip -d /usr/local/bin/ \
    && rm /tmp/vault.zip \
    && vault --version

# Python packages
RUN pip install ansible hvac requests boto3 \
    && ansible-galaxy collection install community.hashi_vault

# Docker Buildx plugin
RUN mkdir -p ~/.docker/cli-plugins && \
    curl -sSL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
      -o ~/.docker/cli-plugins/docker-buildx && \
    chmod +x ~/.docker/cli-plugins/docker-buildx && \
    docker buildx version || true

# --- Stage 2: Final ---
FROM ubuntu:24.04

ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
WORKDIR /app

# Copy everything from builder
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /usr/bin/node /usr/bin/node
COPY --from=builder /usr/bin/npm /usr/bin/npm

SHELL ["/bin/bash", "-c"]
