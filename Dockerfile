FROM node:24-bookworm-slim

ARG DSH_VERSION=0.2.1-rc.5

LABEL org.opencontainers.image.title="dsh-anywhere" \
      org.opencontainers.image.description="DeepSeek Harness in a container with a persistent home" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl file git jq procps python3 ripgrep unzip \
 && rm -rf /var/lib/apt/lists/* \
 && npm install --global "@deepseek-ai/dsh@${DSH_VERSION}" \
 && npm cache clean --force \
 && mkdir -p /dsh && chmod 1777 /dsh

# A shared credentials volume (mounted by dsh-anywhere) keeps one API key for
# every project. /dsh-defaults/deepseek-harness/default-workspace points at the
# mounted project, so a fresh project volume registers /workspace automatically
# instead of falling back to the Documents lookup (which needs xdg-user-dir).
RUN mkdir -p /dsh-credentials /dsh-defaults/deepseek-harness /workspace \
 && chmod 1777 /dsh-credentials \
 && ln -s /workspace /dsh-defaults/deepseek-harness/default-workspace

COPY profile.yml /usr/local/share/dsh-anywhere/profile.yml
COPY entrypoint.sh /usr/local/bin/dsh-web
RUN chmod 0755 /usr/local/bin/dsh-web \
 && chmod 0755 /usr/local/share/dsh-anywhere \
 && chmod 0644 /usr/local/share/dsh-anywhere/profile.yml

ENV HOME=/dsh/home \
    DSH_HOME=/dsh/home \
    NARB_NATIVE_CACHE_DIR=/dsh/home/native-cache \
    NPM_CONFIG_CACHE=/tmp/npm-cache \
    PIP_NO_CACHE_DIR=1

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/dsh-web"]
