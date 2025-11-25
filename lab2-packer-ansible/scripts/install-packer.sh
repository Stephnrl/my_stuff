#!/bin/bash
# =============================================================================
# Packer Installation Script for Lab Environment
# =============================================================================
# This script installs HashiCorp Packer on Amazon Linux 2
# =============================================================================

set -e

PACKER_VERSION="${1:-1.10.3}"
INSTALL_DIR="/usr/local/bin"

echo "============================================"
echo "Installing Packer v${PACKER_VERSION}"
echo "============================================"

# Check if Packer is already installed
if command -v packer &> /dev/null; then
    CURRENT_VERSION=$(packer version | head -n1 | awk '{print $2}' | tr -d 'v')
    echo "Packer is already installed (version: ${CURRENT_VERSION})"
    read -p "Do you want to reinstall/upgrade? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping installation."
        exit 0
    fi
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "${TEMP_DIR}"

echo "Downloading Packer v${PACKER_VERSION}..."

# Download Packer
curl -sLO "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"

# Download checksums
curl -sLO "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS"

echo "Verifying checksum..."

# Verify checksum
if ! sha256sum -c --ignore-missing "packer_${PACKER_VERSION}_SHA256SUMS"; then
    echo "ERROR: Checksum verification failed!"
    exit 1
fi

echo "Installing Packer..."

# Unzip and install
unzip -q "packer_${PACKER_VERSION}_linux_amd64.zip"
sudo mv packer "${INSTALL_DIR}/packer"
sudo chmod +x "${INSTALL_DIR}/packer"

# Cleanup
cd /
rm -rf "${TEMP_DIR}"

echo "============================================"
echo "Packer installation complete!"
echo "============================================"

# Verify installation
echo ""
packer version
echo ""

echo "To get started, run: packer init ."
