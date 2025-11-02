FROM ubuntu:24.04

# --- System dependencies ---
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Node.js installation (via NodeSource) ---
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    ln -sf /usr/bin/node /usr/local/bin/node && \
    ln -sf /usr/bin/npm /usr/local/bin/npm

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

# Ensure node is globally visible
RUN ln -sf /usr/bin/node /usr/local/bin/node && \
    ln -sf /usr/bin/node /bin/node && \
    echo 'export PATH=$PATH:/usr/bin:/usr/local/bin:/bin' >> /etc/profile && \
    node -v

# --- Final setup ---
WORKDIR /app
SHELL ["/bin/bash", "-c"]
