# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# Custom GitHub Actions runner image for ARC scale sets
# Base: ghcr.io/actions/actions-runner (Ubuntu 22.04, runs as uid 1001 `runner`)
# Parameterised by DOTNET_VERSION so one Dockerfile feeds the bake matrix.
# ---------------------------------------------------------------------------
ARG RUNNER_VERSION=latest
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

ARG DOTNET_VERSION=8.0
ARG PACKER_VERSION=1.14.3
ARG TFENV_TERRAFORM_VERSIONS="0.12.31 1.5.7 1.8.5 1.9.8 1.10.5"
ARG TFENV_DEFAULT_VERSION=1.10.5
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin \
    TFENV_ROOT=/opt/tfenv \
    PATH="/opt/tfenv/bin:/home/runner/.dotnet/tools:${PATH}"

USER root

# ---------------------------------------------------------------------------
# 1. Base OS packages + Microsoft prod repo + git-lfs
#    (stable layer — shared across every dotnet variant, heavy cache hit)
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release \
        unzip zip tar jq git git-lfs \
        build-essential software-properties-common apt-transport-https \
        libicu-dev libssl-dev libffi-dev \
        python3 python3-pip python3-venv python3-dev \
        bash-completion; \
    git lfs install --system --skip-repo; \
    . /etc/os-release; \
    curl -fsSLO "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"; \
    dpkg -i packages-microsoft-prod.deb; \
    rm packages-microsoft-prod.deb; \
    apt-get update

# ---------------------------------------------------------------------------
# 2. PowerShell 7  (PowerShell 5 is Windows-only and cannot be installed here)
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get install -y --no-install-recommends powershell

# ---------------------------------------------------------------------------
# 3. PowerShell modules
#    Installing `Az` pulls Az.Accounts + Az.ApiManagement + all other Az.*
# ---------------------------------------------------------------------------
RUN pwsh -NoLogo -NonInteractive -Command "\
    \$ErrorActionPreference='Stop'; \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module -Name Az             -Scope AllUsers -AcceptLicense -AllowClobber -Force; \
    Install-Module -Name MSAL.PS        -Scope AllUsers -AcceptLicense -AllowClobber -Force; \
    Install-Module -Name Microsoft.Graph -Scope AllUsers -AcceptLicense -AllowClobber -Force"

# ---------------------------------------------------------------------------
# 4. Python ecosystem: pip libs + pipx for CLI tools
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install --upgrade --break-system-packages \
        pip setuptools wheel pipx pyyaml pytest botocore boto3 msal

# Install azure-cli isolated via pipx (avoids clashing with system python libs)
RUN --mount=type=cache,target=/root/.cache/pip \
    pipx install azure-cli

# ---------------------------------------------------------------------------
# 5. Azure CLI extensions
# ---------------------------------------------------------------------------
RUN az config set extension.use_dynamic_install=yes_without_prompt \
 && az extension add --name datafactory      --yes \
 && az extension add --name account          --yes \
 && az extension add --name fleet            --yes \
 && az extension add --name storage-preview  --yes

# ---------------------------------------------------------------------------
# 6. Bicep (installed via az — gives you `az bicep` + standalone binary)
# ---------------------------------------------------------------------------
RUN az bicep install

# ---------------------------------------------------------------------------
# 7. Helm (latest)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
      | DESIRED_VERSION= bash \
 && helm version --short

# ---------------------------------------------------------------------------
# 8. JFrog CLI
# ---------------------------------------------------------------------------
RUN curl -fL https://install-cli.jfrog.io | sh \
 && jf --version

# ---------------------------------------------------------------------------
# 9. AWS CLI v2  (arch-aware)
# ---------------------------------------------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64)  AWS_ARCH=x86_64 ;; \
        arm64)  AWS_ARCH=aarch64 ;; \
        *) echo "Unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/awscliv2.zip /tmp/aws; \
    aws --version

# ---------------------------------------------------------------------------
# 10. eksctl (latest)
# ---------------------------------------------------------------------------
RUN set -eux; \
    ARCH="${TARGETARCH:-amd64}"; \
    curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin; \
    eksctl version

# ---------------------------------------------------------------------------
# 11. Packer (pinned version)
# ---------------------------------------------------------------------------
RUN set -eux; \
    ARCH="${TARGETARCH:-amd64}"; \
    curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_${ARCH}.zip" -o /tmp/packer.zip; \
    unzip -q /tmp/packer.zip -d /usr/local/bin; \
    rm /tmp/packer.zip; \
    packer --version

# ---------------------------------------------------------------------------
# 12. tfenv + Terraform versions (default set via TFENV_DEFAULT_VERSION)
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone --depth 1 https://github.com/tfutils/tfenv.git ${TFENV_ROOT}; \
    chmod -R a+rx ${TFENV_ROOT}; \
    for v in ${TFENV_TERRAFORM_VERSIONS}; do tfenv install "$v"; done; \
    tfenv use "${TFENV_DEFAULT_VERSION}"; \
    terraform version

# ---------------------------------------------------------------------------
# 13. .NET SDK  (varies per bake target — this is the "split point")
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get install -y --no-install-recommends "dotnet-sdk-${DOTNET_VERSION}" \
 && dotnet --info

# ---------------------------------------------------------------------------
# 14. dotnet tool manifest + docfx (as the runner user so the manifest lives
#     in /home/runner/.config and tools resolve correctly at job runtime)
# ---------------------------------------------------------------------------
RUN mkdir -p /home/runner/tools \
 && chown -R runner:runner /home/runner

USER runner
WORKDIR /home/runner/tools
RUN dotnet new tool-manifest --name "runner-manifest" \
 && dotnet tool install docfx

# ---------------------------------------------------------------------------
# Final: drop back to the runner user at its home directory.
# ARC's listener expects uid 1001 — do NOT leave this as root.
# ---------------------------------------------------------------------------
WORKDIR /home/runner
