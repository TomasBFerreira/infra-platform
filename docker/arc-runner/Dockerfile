# ARC runner image — extends the upstream actions-runner image with the tools
# every infra-platform / ops-portal workflow reaches for.
#
# Why FROM actions-runner: the gha-runner-scale-set chart's default container
# command is /home/runner/run.sh, which is part of the upstream image. A
# from-scratch debian image with the tools but no run.sh deadlocks in
# CrashLoopBackOff (caught on first real pod scheduling — see PR history).
#
# Tools layered here, with rationale (matches what workflows install on
# demand on the legacy LXC runner):
#   - vault CLI         — vault kv get in many playbooks/workflows
#   - kubectl           — every ops-portal-* deploy.yml installs on demand
#   - terraform         — run-terraform.sh's no-docker fallback path
#   - ansible           — ansible-playbook invoked directly by infra workflows
#   - gh                — sync-gh-pat-to-vault.yml + several others
#   - python3-yaml      — registered-repos.yml parsers
#   - jq                — table stakes
# (curl, git, unzip, openssh-client are already in the upstream image.)

# Bump in lockstep with GitHub's runner-version deprecation cadence. They
# block versions ~6 months old: a deprecated runner connects to the broker
# but every message-poll returns 403 with "Runner version vX.Y.Z is
# deprecated and cannot receive messages." (caught 2026-05-13 on 2.321.0;
# bumped to 2.334.0). Check https://github.com/actions/runner/releases
# before bumping if you don't know the current floor.
ARG ACTIONS_RUNNER_VERSION=2.334.0
FROM ghcr.io/actions/actions-runner:${ACTIONS_RUNNER_VERSION}

ARG TERRAFORM_VERSION=1.9.8
ARG KUBECTL_VERSION=1.32.0
ARG VAULT_VERSION=1.18.2
ARG KUSTOMIZE_VERSION=5.4.3
ARG CRANE_VERSION=0.19.1

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        jq unzip ca-certificates gnupg lsb-release \
        gettext-base \
        python3 python3-pip python3-yaml \
        ansible \
    && rm -rf /var/lib/apt/lists/*
# gettext-base gives us envsubst, used by traefik-gitops's deploy.yml to
# render OTLP endpoint into the Traefik config before SCP'ing to network-vm.
# Add any further missing tools alongside this line; don't sprinkle apt-get
# install steps across the workflow files themselves.

# kubectl
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# kustomize — used by ops-portal-* + landing-page deploys via `kubectl apply -k`.
# The self-install step in those workflows tries to write to /usr/local/bin
# without sudo and fails as the non-root `runner` user; bake it in instead.
RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin kustomize \
    && chmod +x /usr/local/bin/kustomize

# crane — used by landing-page deploy to `crane pull --format=tarball` the
# built image from GHCR before `k3s ctr images import` on the worker.
RUN curl -fsSL "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
        | tar -xz -C /usr/local/bin crane \
    && chmod +x /usr/local/bin/crane

# terraform — extract only the binary; the zip ships a LICENSE.txt that
# collides with vault's LICENSE.txt below if both are extracted whole, and
# unzip prompts interactively in a non-TTY build (caught in initial build).
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
        -o /tmp/terraform.zip \
    && unzip -o /tmp/terraform.zip terraform -d /usr/local/bin/ \
    && rm /tmp/terraform.zip

# vault CLI — extract only the binary (see terraform note).
RUN curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" \
        -o /tmp/vault.zip \
    && unzip -o /tmp/vault.zip vault -d /usr/local/bin/ \
    && rm /tmp/vault.zip

# gh CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Sanity check at build time — broken image fails the build, not the
# first pod scheduling.
RUN kubectl version --client \
    && kustomize version \
    && crane version \
    && terraform version \
    && vault version \
    && ansible --version | head -1 \
    && gh --version | head -1 \
    && python3 --version \
    && test -x /home/runner/run.sh && echo "run.sh present"

# Drop back to the upstream image's default user. ARC chart's listener
# does NOT override command, so the default /home/runner/run.sh entrypoint
# from the upstream image is what gets invoked.
USER runner
WORKDIR /home/runner
