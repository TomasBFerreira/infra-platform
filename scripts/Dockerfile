FROM alpine:3.21

# Install CI/automation tools
RUN apk update && apk add --no-cache \
  bash \
  openssl \
  openssh \
  curl \
  wget \
  unzip

WORKDIR /app

# Default shell for scripts
SHELL ["/bin/bash", "-c"]
