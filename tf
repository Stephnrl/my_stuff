#!/usr/bin/env bash
set -euo pipefail

JFROG_MIRROR="${TFVM_MIRROR:-https://releases.hashicorp.com}"  # Replace with your JFrog URL
INSTALL_DIR="${TFVM_ROOT:-${HOME}/.tfvm}"
BIN_DIR="${HOME}/.local/bin"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"

mkdir -p "${INSTALL_DIR}" "${BIN_DIR}"

install_version() {
    local version="$1"
    local dest="${INSTALL_DIR}/${version}"
    
    if [[ -x "${dest}/terraform" ]]; then
        echo "Terraform ${version} already installed"
        return 0
    fi
    
    echo "Installing Terraform ${version}..."
    mkdir -p "${dest}"
    
    local url="${JFROG_MIRROR}/terraform/${version}/terraform_${version}_${OS}_${ARCH}.zip"
    if ! curl -fsSL "${url}" -o "/tmp/terraform_${version}.zip"; then
        echo "ERROR: Failed to download ${url}" >&2
        rm -rf "${dest}"
        return 1
    fi
    
    unzip -q -o "/tmp/terraform_${version}.zip" -d "${dest}"
    rm "/tmp/terraform_${version}.zip"
    chmod +x "${dest}/terraform"
    echo "Installed Terraform ${version}"
}

use_version() {
    local version="$1"
    local src="${INSTALL_DIR}/${version}/terraform"
    
    if [[ ! -x "${src}" ]]; then
        echo "ERROR: Terraform ${version} not installed. Run: $0 install ${version}" >&2
        return 1
    fi
    
    ln -sfn "${src}" "${BIN_DIR}/terraform"
    echo "${version}" > "${INSTALL_DIR}/.active"
    echo "Now using Terraform ${version}"
}

list_versions() {
    echo "Installed versions:"
    local active=""
    [[ -f "${INSTALL_DIR}/.active" ]] && active="$(cat "${INSTALL_DIR}/.active")"
    
    for dir in "${INSTALL_DIR}"/*/; do
        [[ -d "${dir}" ]] || continue
        local ver="$(basename "${dir}")"
        if [[ "${ver}" == "${active}" ]]; then
            echo "  * ${ver} (active)"
        else
            echo "    ${ver}"
        fi
    done
}

case "${1:-help}" in
    install)
        shift
        for v in "$@"; do
            install_version "$v"
        done
        ;;
    use)
        use_version "$2"
        ;;
    list)
        list_versions
        ;;
    *)
        echo "Usage: $0 {install <version>...|use <version>|list}"
        echo ""
        echo "Examples:"
        echo "  $0 install 1.5.7 1.10.0 1.14.3"
        echo "  $0 use 1.5.7"
        echo "  $0 list"
        echo ""
        echo "Environment:"
        echo "  TFVM_MIRROR  - Base URL for downloads (default: releases.hashicorp.com)"
        echo "  TFVM_ROOT    - Install location (default: ~/.tfvm)"
        ;;
esac
