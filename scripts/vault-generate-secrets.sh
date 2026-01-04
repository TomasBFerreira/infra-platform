#!/bin/bash
set -e

# ----------------- Debugging and Package Installation -----------------

echo "========= DEBUG: Distribution Info ========="
cat /etc/os-release || echo "No /etc/os-release file found"

# Try to install openssl and ssh-keygen (openssh-client/openssh) using all common package managers.
if command -v apt-get >/dev/null 2>&1; then
  echo "DEBUG: Using apt-get to install openssl openssh-client"
  apt-get update && apt-get install -y openssl openssh-client
elif command -v apk >/dev/null 2>&1; then
  echo "DEBUG: Using apk to install openssl openssh"
  apk update && apk add openssl openssh
elif command -v yum >/dev/null 2>&1; then
  echo "DEBUG: Using yum to install openssl openssh-clients"
  yum install -y openssl openssh-clients
elif command -v dnf >/dev/null 2>&1; then
  echo "DEBUG: Using dnf to install openssl openssh-clients"
  dnf install -y openssl openssh-clients
else
  echo "ERROR: No compatible package manager found; please update your runner/container image."
  exit 1
fi

# ----------------- Config/Vars For Debugging -----------------

export VAULT_TOKEN="myroot"
export VAULT_ADDR="http://localhost:8200"
PROJECT="media-stack"
SSH_SECRET_PATH="${SSH_SECRET_PATH:-secret/ssh_keys/${PROJECT}_worker}"
PASSWORD_SECRET_PATH="${PASSWORD_SECRET_PATH:-secret/${PROJECT}/root_password}"
VAULT_VERSION="1.15.2"
VAULT_BIN="./vault"

echo "========= DEBUG: Environment Variables ========="
echo "PROJECT=$PROJECT"
echo "SSH_SECRET_PATH=$SSH_SECRET_PATH"
echo "PASSWORD_SECRET_PATH=$PASSWORD_SECRET_PATH"
echo "VAULT_ADDR=$VAULT_ADDR"
echo "VAULT_TOKEN=$VAULT_TOKEN"

# ----------------- Vault Connectivity Test -----------------

echo "Testing Vault connectivity to $VAULT_ADDR..."
curl -sf "$VAULT_ADDR/v1/sys/health" && echo "Vault reachable!" || (echo "Vault unreachable!"; exit 1)

# ----------------- Download Vault CLI -----------------

if ! [ -f "${VAULT_BIN}" ]; then
  echo "DEBUG: Downloading Vault CLI version ${VAULT_VERSION}"
  wget -q https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
  unzip -q vault_${VAULT_VERSION}_linux_amd64.zip
  mv vault "${VAULT_BIN}"
  chmod +x "${VAULT_BIN}"
  rm vault_${VAULT_VERSION}_linux_amd64.zip
fi

# ----------------- SSH Key Management -----------------

if ! "${VAULT_BIN}" kv get -field=private "${SSH_SECRET_PATH}" 2>/dev/null; then
  echo "DEBUG: No SSH key found—generating new SSH keypair"
  rm -f /tmp/${PROJECT}_worker /tmp/${PROJECT}_worker.pub
  ssh-keygen -t ed25519 -f /tmp/${PROJECT}_worker -N '' -q
  # Store the SSH key with newlines preserved
  PRIVATE_KEY=$(cat /tmp/${PROJECT}_worker)
  PUBLIC_KEY=$(cat /tmp/${PROJECT}_worker.pub)
  "${VAULT_BIN}" kv put "${SSH_SECRET_PATH}" \
    private="${PRIVATE_KEY}" \
    public="${PUBLIC_KEY}" || { echo "ERROR: Failed to store SSH key in Vault"; exit 1; }
  rm /tmp/${PROJECT}_worker*
  echo "SSH key created and stored in Vault under ${SSH_SECRET_PATH}."
else
  echo "SSH key already in Vault at ${SSH_SECRET_PATH}, skipping."
fi

# ----------------- Password Management -----------------

if ! "${VAULT_BIN}" kv get -field=password "${PASSWORD_SECRET_PATH}" 2>/dev/null; then
  echo "DEBUG: No root password found—generating new password"
  RANDOM_PASS=$(openssl rand -base64 32)
  "${VAULT_BIN}" kv put "${PASSWORD_SECRET_PATH}" password="$RANDOM_PASS" || { echo "ERROR: Failed to store password in Vault"; exit 1; }
  echo "Root password created and stored in Vault under ${PASSWORD_SECRET_PATH}."
else
  echo "Root password already in Vault at ${PASSWORD_SECRET_PATH}, skipping."
fi
