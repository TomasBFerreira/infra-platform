# arc-runner

Custom container image used by the GitHub Actions Runner Controller (ARC) for
ephemeral runner pods. Replaces the per-env LXC runners (`github-runner-{dev,qa,prod}`)
once the migration in [`docs/arc-migration.md`](../../docs/arc-migration.md) lands.

## Why a custom image
The upstream `ghcr.io/actions/actions-runner` image is minimal — every tool a
workflow needs (kubectl, terraform, ansible, vault, gh, jq, python3) gets
installed on every job by the workflow itself. On a long-lived LXC that's a
one-time cost; on an ephemeral pod it's repeated every run. Pre-baking the tools
into this image removes ~15-30s of cold start per job.

## What's in it
See the comments in [`Dockerfile`](Dockerfile) for the tool list and the
rationale for each.

## How it gets built
The [`arc-runner-image.yml`](../../.github/workflows/arc-runner-image.yml)
workflow builds + pushes `ghcr.io/tomasbferreira/arc-runner` on changes to
`docker/arc-runner/**`. Tags: the commit SHA + `latest`.

## How to test locally
```
docker build -t arc-runner:dev docker/arc-runner/
docker run --rm -it arc-runner:dev bash
```
The `RUN` chain at the end of the Dockerfile prints every tool's version, so a
build failure here means the image is broken — caught before it hits a runner.
