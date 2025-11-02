FROM alpine:3.21

RUN apk update && apk add --no-cache \
  bash \
  openssl \
  openssh \
  curl \
  wget \
  unzip \
  python3

RUN python3 -m ensurepip && \
    ln -s /usr/bin/pip3 /usr/bin/pip || true

WORKDIR /app
SHELL ["/bin/bash", "-c"]
