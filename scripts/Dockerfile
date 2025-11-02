# -------------------------------
# Base Image: Python 3.12 + Node.js (CircleCI official)
# -------------------------------
FROM cimg/python:3.12-node

# -------------------------------
# System dependencies
# -------------------------------
USER root
RUN sudo apt-get update && DEBIAN_FRONTEND=noninteractive sudo apt-get install -y \
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
    && sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

RUN sudo apt-get update && \
    sudo apt-get install -y ca-certificates curl gnupg lsb-release && \
    sudo mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    sudo apt-get update && \
    sudo apt-get install -y docker-ce-cli

# -------------------------------
# Python virtual environment
# -------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Upgrade pip and tools
RUN pip install --upgrade pip setuptools wheel

# -------------------------------
# Terraform installation
# -------------------------------
ARG TERRAFORM_VERSION=1.9.8
RUN curl -sLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin/ && \
    rm /tmp/terraform.zip && \
    terraform -version

# -------------------------------
# Vault installation
# -------------------------------
ARG VAULT_VERSION=1.15.2
RUN curl -sLo /tmp/vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    unzip /tmp/vault.zip -d /usr/local/bin/ && \
    rm /tmp/vault.zip && \
    vault --version

# -------------------------------
# Ansible and Python libraries
# -------------------------------
RUN pip install \
    ansible \
    hvac \
    requests \
    boto3

# Install Ansible Galaxy collections for Vault integration
RUN ansible-galaxy collection install community.hashi_vault

# -------------------------------
# Docker Buildx plugin
# -------------------------------
RUN mkdir -p ~/.docker/cli-plugins && \
    curl -sSL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
      -o ~/.docker/cli-plugins/docker-buildx && \
    chmod +x ~/.docker/cli-plugins/docker-buildx

# Verify Buildx
RUN docker buildx version || true

# -------------------------------
# Final setup
# -------------------------------
WORKDIR /app
SHELL ["/bin/bash", "-c"]

# Set PATH for all subsequent steps
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
