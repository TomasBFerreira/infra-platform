FROM alpine:3.21

# --- System dependencies ---
RUN apk update && apk add --no-cache \
  bash \
  openssl \
  openssh \
  curl \
  wget \
  unzip \
  git \
  docker-cli \
  build-base \
  python3 \
  py3-pip \
  py3-virtualenv \
  nodejs \
  npm \
  jq \
  coreutils

# --- Python setup ---
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip and common tools
RUN pip install --upgrade pip setuptools wheel

# --- Terraform installation ---
ARG TERRAFORM_VERSION=1.9.8
RUN curl -sLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin/ && \
    rm /tmp/terraform.zip && \
    terraform -version

# --- Vault installation ---
ARG VAULT_VERSION=1.15.2
RUN curl -sLo /tmp/vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    unzip /tmp/vault.zip -d /usr/local/bin/ && \
    rm /tmp/vault.zip && \
    vault --version

# --- Ansible and Python libraries ---
RUN pip install \
    ansible \
    hvac \
    requests \
    boto3

# Install Ansible Galaxy collections (for Vault integration, etc.)
RUN ansible-galaxy collection install community.hashi_vault

# --- Docker Buildx plugin ---
RUN mkdir -p ~/.docker/cli-plugins && \
    curl -sSL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
      -o ~/.docker/cli-plugins/docker-buildx && \
    chmod +x ~/.docker/cli-plugins/docker-buildx && \
    docker buildx version || true

# --- Final setup ---
WORKDIR /app
SHELL ["/bin/bash", "-c"]
