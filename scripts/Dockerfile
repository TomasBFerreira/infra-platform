FROM alpine:3.21

RUN apk update && apk add --no-cache \
  bash \
  openssl \
  openssh \
  curl \
  wget \
  unzip \
  python3 \
  py3-virtualenv \
  nodejs npm

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip setuptools wheel

RUN apk add --no-cache curl unzip && \
    VAULT_VERSION=1.15.2 && \
    curl -sLo vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    unzip vault.zip -d /usr/local/bin/ && \
    rm vault.zip

WORKDIR /app
SHELL ["/bin/bash", "-c"]
