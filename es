#!/bin/bash

#############################################
# Elastic Agent Installation Script for RHEL 9
# Downloads, verifies, installs, and enrolls Elastic Agent
#############################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
ELASTIC_VERSION="8.19.3"
ELASTIC_ARCH="x86_64"
RPM_URL="https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_VERSION}-${ELASTIC_ARCH}.rpm"
SHA512_URL="${RPM_URL}.sha512"
DOWNLOAD_DIR="/tmp/elastic-agent-install"
RPM_FILE="${DOWNLOAD_DIR}/elastic-agent-${ELASTIC_VERSION}-${ELASTIC_ARCH}.rpm"
SHA512_FILE="${RPM_FILE}.sha512"

# Fleet configuration (set these before running or pass as environment variables)
FLEET_URL="${FLEET_URL:-}"
ENROLLMENT_TOKEN="${ENROLLMENT_TOKEN:-}"

# Logging functions
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Create download directory
setup_download_dir() {
    log_info "Setting up download directory: ${DOWNLOAD_DIR}"
    mkdir -p "${DOWNLOAD_DIR}"
    cd "${DOWNLOAD_DIR}"
}

# Download files
download_files() {
    log_info "Downloading Elastic Agent RPM..."
    if ! curl -L -o "${RPM_FILE}" "${RPM_URL}"; then
        log_error "Failed to download Elastic Agent RPM"
        exit 1
    fi

    log_info "Downloading SHA512 checksum file..."
    if ! curl -L -o "${SHA512_FILE}" "${SHA512_URL}"; then
        log_error "Failed to download SHA512 checksum"
        exit 1
    fi
}

# Verify checksum
verify_checksum() {
    log_info "Verifying SHA512 checksum..."
    
    # Extract the checksum from the .sha512 file
    EXPECTED_CHECKSUM=$(awk '{print $1}' "${SHA512_FILE}")
    
    # Calculate actual checksum
    ACTUAL_CHECKSUM=$(sha512sum "${RPM_FILE}" | awk '{print $1}')
    
    if [[ "${EXPECTED_CHECKSUM}" == "${ACTUAL_CHECKSUM}" ]]; then
        log_info "Checksum verification successful!"
        log_info "Expected: ${EXPECTED_CHECKSUM}"
        log_info "Actual:   ${ACTUAL_CHECKSUM}"
    else
        log_error "Checksum verification failed!"
        log_error "Expected: ${EXPECTED_CHECKSUM}"
        log_error "Actual:   ${ACTUAL_CHECKSUM}"
        exit 1
    fi
}

# Install Elastic Agent
install_agent() {
    log_info "Installing Elastic Agent..."
    
    # Check if already installed
    if rpm -q elastic-agent &>/dev/null; then
        log_warn "Elastic Agent is already installed"
        CURRENT_VERSION=$(rpm -q elastic-agent --queryformat '%{VERSION}')
        log_info "Current version: ${CURRENT_VERSION}"
        
        read -p "Do you want to reinstall/upgrade? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping installation"
            return 0
        fi
    fi
    
    # Install the RPM
    if dnf install -y "${RPM_FILE}"; then
        log_info "Elastic Agent installed successfully!"
    else
        log_error "Failed to install Elastic Agent"
        exit 1
    fi
}

# Enroll agent to Fleet
enroll_agent() {
    if [[ -z "${FLEET_URL}" ]] || [[ -z "${ENROLLMENT_TOKEN}" ]]; then
        log_warn "Fleet enrollment skipped - FLEET_URL or ENROLLMENT_TOKEN not set"
        log_info "To enroll manually, run:"
        log_info "  elastic-agent enroll --url=<FLEET_URL> --enrollment-token=<TOKEN>"
        log_info "  systemctl enable elastic-agent"
        log_info "  systemctl start elastic-agent"
        return 0
    fi
    
    log_info "Enrolling agent to Fleet..."
    log_info "Fleet URL: ${FLEET_URL}"
    
    # Enroll the agent
    if elastic-agent enroll --url="${FLEET_URL}" --enrollment-token="${ENROLLMENT_TOKEN}"; then
        log_info "Agent enrolled successfully!"
        
        # Enable and start the service
        log_info "Enabling and starting elastic-agent service..."
        systemctl enable elastic-agent
        systemctl start elastic-agent
        
        # Check status
        sleep 3
        if systemctl is-active --quiet elastic-agent; then
            log_info "Elastic Agent is running!"
        else
            log_warn "Elastic Agent service may not be running properly"
            log_info "Check status with: systemctl status elastic-agent"
        fi
    else
        log_error "Failed to enroll agent to Fleet"
        log_info "You can enroll manually later using the command above"
        exit 1
    fi
}

# Cleanup
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "${DOWNLOAD_DIR}"
}

# Main execution
main() {
    log_info "Starting Elastic Agent installation for RHEL 9"
    log_info "Version: ${ELASTIC_VERSION}"
    
    check_root
    setup_download_dir
    download_files
    verify_checksum
    install_agent
    enroll_agent
    cleanup
    
    log_info "Installation complete!"
    log_info "Agent version: $(elastic-agent version 2>/dev/null || echo 'Run: elastic-agent version')"
}

# Run main function
main "$@"
