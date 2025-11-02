FROM ubuntu:24.04

# Set environment
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
WORKDIR /app

# --- Install system dependencies, Python, Node.js, Docker CLI ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        openssl \
        openssh-client \
        curl \
        wget \
        unzip \
        git \
        docker.io \
        build-essential \
        python3 \
        python3-venv \
        python3-pip \
        jq \
        coreutils \
        apt-transport-https \
        ca-certificates \
        gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Python venv setup and pip upgrades ---
RUN python3 -m venv /opt/venv && \
    pip install --upgrade pip setuptools wheel

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

# --- Python packages & Ansible Galaxy collections ---
RUN pip install ansible hvac requests boto3 && \
    ansible-galaxy collection install community.hashi_vault

# --- Docker Buildx plugin ---
RUN mkdir -p ~/.docker/cli-plugins && \
    curl -sSL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
        -o ~/.docker/cli-plugins/docker-buildx && \
    chmod +x ~/.docker/cli-plugins/docker-buildx && \
    docker buildx version || true

# --- Use bash by default ---
SHELL ["/bin/bash", "-c"]
