# -------------------------------
# Base Image: Python 3.12
# -------------------------------
FROM cimg/python:3.12

# -------------------------------
# System dependencies
# -------------------------------
USER root

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bash \
    curl \
    wget \
    unzip \
    git \
    docker-ce-cli \
    build-essential \
    jq \
    coreutils \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# -------------------------------
# Node.js 20.x installation
# -------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Verify Node.js and create symlinks in common locations
RUN node -v && npm -v && \
    ln -sf /usr/bin/node /usr/local/bin/node && \
    ln -sf /usr/bin/npm /usr/local/bin/npm

# -------------------------------
# Python virtual environment
# -------------------------------
RUN python3 -m venv /opt/venv && \
    chown -R circleci:circleci /opt/venv

# -------------------------------
# Terraform installation
# -------------------------------
ARG TERRAFORM_VERSION=1.9.8
RUN curl -sLo /tmp/terraform.zip \
    https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin/ && \
    rm /tmp/terraform.zip && \
    chmod +x /usr/local/bin/terraform && \
    terraform -version

# -------------------------------
# Vault installation
# -------------------------------
ARG VAULT_VERSION=1.15.2
RUN curl -sLo /tmp/vault.zip \
    https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    unzip /tmp/vault.zip -d /usr/local/bin/ && \
    rm /tmp/vault.zip && \
    chmod +x /usr/local/bin/vault && \
    vault --version

# -------------------------------
# Docker Buildx plugin (system-wide)
# -------------------------------
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -sSL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
      -o /usr/local/lib/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx && \
    ln -sf /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/bin/docker-buildx

# Also install in circleci user's home for compatibility
RUN mkdir -p /home/circleci/.docker/cli-plugins && \
    cp /usr/local/lib/docker/cli-plugins/docker-buildx /home/circleci/.docker/cli-plugins/ && \
    chown -R circleci:circleci /home/circleci/.docker

# -------------------------------
# Switch to circleci user
# -------------------------------
USER circleci

# Upgrade pip and install Python packages
RUN /opt/venv/bin/pip install --upgrade pip setuptools wheel && \
    /opt/venv/bin/pip install ansible hvac requests boto3

# Install Ansible Galaxy collections
RUN /opt/venv/bin/ansible-galaxy collection install community.hashi_vault

# -------------------------------
# Final setup
# -------------------------------
WORKDIR /home/circleci/project

# Set environment variables
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH" \
    DOCKER_CONFIG=/home/circleci/.docker

# Verify all tools
RUN node --version && \
    npm --version && \
    terraform --version && \
    vault --version && \
    ansible --version && \
    docker buildx version

SHELL ["/bin/bash", "-c"]
