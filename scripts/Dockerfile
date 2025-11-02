FROM alpine:3.21

# Install CI/automation tools and Python with pip
RUN apk update && apk add --no-cache \
  bash \
  openssl \
  openssh \
  curl \
  wget \
  unzip \
  python3 \
  py3-pip

# Create pip symlink
RUN ln -s /usr/bin/pip3 /usr/bin/pip

# Optional: Install Ansible system package for faster CI if preferred
# RUN apk add --no-cache ansible

WORKDIR /app

# Default shell for scripts
SHELL ["/bin/bash", "-c"]
