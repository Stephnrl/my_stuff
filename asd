FROM ghcr.io/actions/actions-runner:2.319.1

USER root
ENV DEBIAN_FRONTEND=noninteractive

ARG NODE_VERSIONS="20.20.2 22.22.2 24.15.0"
ARG NODE_DEFAULT="20.20.2"
ARG NVM_VERSION="0.40.4"
ARG JAVA_VERSION="17"
ARG PACKER_VERSION="1.14.3"
ARG EKSCTL_VERSION="0.225.0"
ARG HELM_VERSION="4.1.4"
ARG KUBECTL_VERSION="1.33.10"
ARG TFENV_VERSION="3.0.0"
ARG TF_VERSIONS="0.12.31 1.5.7 1.8.5 1.9.8 1.10.5"
ARG TF_DEFAULT="1.5.7"

# --- System packages from PUBLIC ubuntu mirrors (bootstrap only) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg unzip git jq \
      openjdk-${JAVA_VERSION}-jdk-headless \
      apt-transport-https software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# --- PowerShell ---
RUN . /etc/os-release && \
    wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && apt-get install -y powershell && \
    rm -rf /var/lib/apt/lists/*

# --- nvm + Node versions (installed system-wide under /opt/nvm) ---
ENV NVM_DIR=/opt/nvm
RUN mkdir -p $NVM_DIR && \
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash && \
    bash -c "source $NVM_DIR/nvm.sh && \
      for v in ${NODE_VERSIONS}; do nvm install \$v; done && \
      nvm alias default ${NODE_DEFAULT} && \
      nvm use default"

# Make node/npm available on PATH for all users
RUN echo 'export NVM_DIR=/opt/nvm' > /etc/profile.d/nvm.sh && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> /etc/profile.d/nvm.sh && \
    ln -s $NVM_DIR/versions/node/v${NODE_DEFAULT}/bin/node /usr/local/bin/node && \
    ln -s $NVM_DIR/versions/node/v${NODE_DEFAULT}/bin/npm /usr/local/bin/npm && \
    ln -s $NVM_DIR/versions/node/v${NODE_DEFAULT}/bin/npx /usr/local/bin/npx

# --- Packer ---
RUN curl -fsSL -o /tmp/packer.zip \
      "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" && \
    unzip /tmp/packer.zip -d /usr/local/bin && rm /tmp/packer.zip && \
    packer version

# --- eksctl ---
RUN curl -fsSL -o /tmp/eksctl.tar.gz \
      "https://github.com/eksctl-io/eksctl/releases/download/v${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz" && \
    tar -xzf /tmp/eksctl.tar.gz -C /usr/local/bin && rm /tmp/eksctl.tar.gz && \
    eksctl version

# --- helm ---
RUN curl -fsSL -o /tmp/helm.tar.gz \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" && \
    tar -xzf /tmp/helm.tar.gz -C /tmp && \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 && \
    helm version

# --- kubectl ---
RUN curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x /usr/local/bin/kubectl && \
    kubectl version --client

# --- tfenv + Terraform versions ---
ENV TFENV_ROOT=/opt/tfenv
ENV PATH="${TFENV_ROOT}/bin:${PATH}"
RUN git clone --depth 1 --branch v${TFENV_VERSION} \
      https://github.com/tfutils/tfenv.git $TFENV_ROOT && \
    for v in ${TF_VERSIONS}; do tfenv install $v; done && \
    tfenv use ${TF_DEFAULT}

# --- PowerShell modules from PSGallery (public) ---
RUN pwsh -Command " \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module Az -Scope AllUsers -Force -AcceptLicense; \
    Install-Module Pester -Scope AllUsers -Force -AcceptLicense \
"

USER runner
