FROM ghcr.io/actions/actions-runner:2.319.1

ARG JFROG_PS_URL
ARG NODE_VERSIONS="18.20.4 20.17.0 22.9.0"
ARG JAVA_VERSION="17"
ARG PACKER_VERSION="1.11.2"
ARG EKSCTL_VERSION="0.193.0"
ARG HELM_VERSION="3.16.1"

USER root

# Base apt tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg apt-transport-https git git-lfs \
        unzip zip jq xz-utils \
        software-properties-common lsb-release \
        build-essential \
        python3 python3-pip python3-venv pipx \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

# Microsoft feed: PowerShell + Az CLI (NOT .NET — that's per-variant)
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
        https://packages.microsoft.com/ubuntu/22.04/prod jammy main" \
        > /etc/apt/sources.list.d/microsoft-prod.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        powershell \
        azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Java (Temurin)
RUN curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] \
        https://packages.adoptium.net/artifactory/deb jammy main" \
        > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        temurin-${JAVA_VERSION}-jdk \
    && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/temurin-${JAVA_VERSION}-jdk-amd64

# Node (multi-version via tool cache)
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache
RUN mkdir -p $RUNNER_TOOL_CACHE && \
    for v in $NODE_VERSIONS; do \
        mkdir -p $RUNNER_TOOL_CACHE/node/${v}/x64 && \
        curl -fsSL "https://nodejs.org/dist/v${v}/node-v${v}-linux-x64.tar.xz" \
            | tar -xJ -C $RUNNER_TOOL_CACHE/node/${v}/x64 --strip-components=1 && \
        touch $RUNNER_TOOL_CACHE/node/${v}/x64.complete; \
    done && \
    DEFAULT_NODE=$(echo $NODE_VERSIONS | tr ' ' '\n' | sort -V | tail -1) && \
    ln -sf $RUNNER_TOOL_CACHE/node/${DEFAULT_NODE}/x64/bin/node /usr/local/bin/node && \
    ln -sf $RUNNER_TOOL_CACHE/node/${DEFAULT_NODE}/x64/bin/npm /usr/local/bin/npm && \
    ln -sf $RUNNER_TOOL_CACHE/node/${DEFAULT_NODE}/x64/bin/npx /usr/local/bin/npx

# Helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
        | tar -xz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && rm -rf /tmp/linux-amd64

# kubectl
RUN curl -fsSL https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Docker CLI + buildx (daemon comes from DinD sidecar at job time)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu jammy stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# eksctl
RUN curl -fsSL "https://github.com/eksctl-io/eksctl/releases/download/v${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz" \
        | tar -xz -C /tmp \
    && mv /tmp/eksctl /usr/local/bin/eksctl \
    && chmod +x /usr/local/bin/eksctl

# Packer
RUN curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
        -o /tmp/packer.zip \
    && unzip -q /tmp/packer.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/packer \
    && rm /tmp/packer.zip

# Ansible (pipx, isolated from system Python)
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin
RUN pipx install --global ansible-core

# PowerShell modules from JFrog
COPY shared/install-modules.ps1 /tmp/install-modules.ps1
RUN pwsh -NoProfile -File /tmp/install-modules.ps1 -JFrogUrl "${JFROG_PS_URL}" \
    && rm /tmp/install-modules.ps1

# Permissions on tool cache
RUN chown -R 1001:121 $RUNNER_TOOL_CACHE

USER runner
ENV PATH="/usr/local/bin:/home/runner/.local/bin:${PATH}"
