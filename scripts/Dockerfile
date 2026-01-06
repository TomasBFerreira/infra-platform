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

# Create symlinks only where needed
RUN ln -sf /usr/bin/node /usr/local/bin/node || true && \
    ln -sf /usr/bin/npm /usr/local/bin/npm || true

# Add node to system-wide PATH configuration
RUN echo 'export PATH="/usr/bin:/usr/local/bin:$PATH"' >> /etc/profile && \
    echo 'export PATH="/usr/bin:/usr/local/bin:$PATH"' >> /etc/bash.bashrc

# Verify Node.js
RUN which node && node -v && npm -v

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
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# Install for circleci user
RUN mkdir -p /home/circleci/.docker/cli-plugins && \
    cp /usr/local/lib/docker/cli-plugins/docker-buildx /home/circleci/.docker/cli-plugins/ && \
    chown -R circleci:circleci /home/circleci/.docker

# Install for root user (for act compatibility)
RUN mkdir -p /root/.docker/cli-plugins && \
    cp /usr/local/lib/docker/cli-plugins/docker-buildx /root/.docker/cli-plugins/

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

# Set environment variables - these will be inherited by all shells
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH" \
    DOCKER_CONFIG=/home/circleci/.docker

# Verify all tools
RUN which node && \
    node --version && \
    npm --version && \
    terraform --version && \
    vault --version && \
    ansible --version && \
    docker buildx version

SHELL ["/bin/bash", "-c"]

# Switch back to root for act compatibility
USER root

# Ensure PATH is set for root user too
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint to fix SSH keys before running commands
ENTRYPOINT ["/entrypoint.sh"]

# Final verification as root
RUN which node && node --version
