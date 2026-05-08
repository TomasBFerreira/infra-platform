# ARC runner image — pre-baked tools so ephemeral pods skip apt-get on every job.
#
# Used by the gha-runner-scale-set Helm chart as the runner image. The chart
# injects the actions/runner binary into /home/runner/_work; this image only
# needs the tools workflows reach for during a job.
#
# Tools chosen by reading existing pipelines under .github/workflows/:
#   - vault CLI         — used for "vault kv get" in github-runner_setup.yml
#   - kubectl           — every ops-portal-* deploy.yml installs it on demand;
#                         baking it in saves ~15s per job
#   - terraform         — run-terraform.sh prefers docker but falls through to
#                         a native binary, which is what we use here
#   - ansible           — ansible-playbook is invoked directly by infra-platform
#                         workflows (no docker-compose wrapper)
#   - gh                — used by sync-gh-pat-to-vault.yml + several others
#   - python3 + pyyaml  — every workflow that reads registered-repos.yml or
#                         parses Vault JSON output
#   - openssh-client    — workflows SCP keys to nodes / SSH to Proxmox
#   - jq, curl, git     — table stakes
#
# Versions tracked here are the floor; bump in lockstep with what production
# pipelines test against. ARC controller version is pinned separately in the
# Helm chart values.
FROM debian:12-slim

ARG TERRAFORM_VERSION=1.9.8
ARG KUBECTL_VERSION=1.32.0
ARG VAULT_VERSION=1.18.2

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl wget git ca-certificates gnupg lsb-release \
        jq unzip sudo openssh-client rsync \
        python3 python3-pip python3-yaml \
        ansible \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
        -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin/ \
    && rm /tmp/terraform.zip

# vault CLI
RUN curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" \
        -o /tmp/vault.zip \
    && unzip /tmp/vault.zip -d /usr/local/bin/ \
    && rm /tmp/vault.zip

# gh CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Non-root runner user — gha-runner-scale-set runs as this UID by default.
RUN useradd -m -u 1001 -s /bin/bash runner \
    && echo 'runner ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

USER runner
WORKDIR /home/runner

# Sanity: every tool prints its version in build logs so a broken image fails
# loudly at build time, not when a workflow lands on the new pod.
RUN kubectl version --client \
    && terraform version \
    && vault version \
    && ansible --version \
    && gh --version \
    && python3 --version
