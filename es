#!/bin/bash

#############################################
# Microsoft Defender for Endpoint (MDE) Installation Script for RHEL 9
# Downloads, installs, configures, and onboards MDE
#############################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
MDE_INSTALLER_URL="https://github.com/microsoft/mdatp-xplat/raw/master/linux/installation/mde_installer.sh"
MDE_INSTALLER="/tmp/mde_installer.sh"
MANAGED_CONFIG_DIR="/etc/opt/microsoft/mdatp/managed"
MANAGED_CONFIG_FILE="${MANAGED_CONFIG_DIR}/mdatp_managed.json"

# Onboarding configuration (set these before running or pass as environment variables)
ONBOARDING_SCRIPT="${ONBOARDING_SCRIPT:-}"  # Path to MicrosoftDefenderATPOnboardingLinuxServer.py

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

# Check RHEL version
check_rhel_version() {
    if [[ ! -f /etc/redhat-release ]]; then
        log_error "This script is designed for RHEL systems"
        exit 1
    fi
    
    RHEL_VERSION=$(grep -oP 'release \K[0-9]+' /etc/redhat-release || echo "unknown")
    log_info "Detected RHEL version: ${RHEL_VERSION}"
    
    if [[ "${RHEL_VERSION}" != "9" ]]; then
        log_warn "This script is optimized for RHEL 9, you are running RHEL ${RHEL_VERSION}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Download MDE installer
download_installer() {
    log_info "Downloading MDE installer from GitHub..."
    
    if ! curl -L -o "${MDE_INSTALLER}" "${MDE_INSTALLER_URL}"; then
        log_error "Failed to download MDE installer"
        exit 1
    fi
    
    chmod +x "${MDE_INSTALLER}"
    log_info "MDE installer downloaded successfully"
}

# Install MDE
install_mde() {
    log_info "Installing Microsoft Defender for Endpoint..."
    
    # Check if already installed
    if command -v mdatp &>/dev/null; then
        log_warn "MDE appears to be already installed"
        CURRENT_VERSION=$(mdatp version 2>/dev/null || echo "unknown")
        log_info "Current version: ${CURRENT_VERSION}"
        
        read -p "Do you want to reinstall/upgrade? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping installation"
            return 0
        fi
    fi
    
    # Install with production channel
    log_info "Running installer with production channel..."
    if "${MDE_INSTALLER}" --install --channel prod --min_req -y; then
        log_info "MDE installed successfully!"
    else
        log_error "Failed to install MDE"
        exit 1
    fi
    
    # Fix permissions (correcting the typo from the old script)
    log_info "Setting correct permissions..."
    if [[ -d /etc/opt/microsoft/mdatp ]]; then
        chgrp -R mdatp /etc/opt/microsoft/mdatp
        log_info "Permissions set successfully"
    else
        log_warn "MDE directory not found, skipping permission fix"
    fi
}

# Create managed configuration file
create_managed_config() {
    log_info "Creating managed configuration file..."
    
    # Create managed directory if it doesn't exist
    mkdir -p "${MANAGED_CONFIG_DIR}"
    
    # Create mdatp_managed.json with recommended settings
    cat > "${MANAGED_CONFIG_FILE}" << 'EOF'
{
  "cloudService": "prod",
  "antivirusEngine": {
    "enableRealTimeProtection": true,
    "scanAfterDefinitionUpdate": true,
    "scanArchives": true,
    "maximumOnDemandScanThreads": 2,
    "exclusions": [
      {
        "comment": "Elastic Agent exclusions",
        "$type": "excludedPath",
        "path": "/opt/Elastic/Agent",
        "isDirectory": true
      }
    ],
    "allowedThreats": [],
    "disallowedThreatActions": [],
    "threatTypeSettings": [
      {
        "key": "potentially_unwanted_application",
        "value": "block"
      },
      {
        "key": "archive_bomb",
        "value": "audit"
      }
    ],
    "threatTypeSettingsMergePolicy": "merge"
  },
  "behaviorMonitoring": "enabled",
  "networkProtection": {
    "enforcementLevel": "block"
  }
}
EOF
    
    log_info "Managed configuration file created at: ${MANAGED_CONFIG_FILE}"
    log_info "You can customize this file later for your organization's needs"
}

# Configure MDE settings via CLI (fallback if not using managed config)
configure_mde_cli() {
    log_info "Configuring MDE settings via CLI..."
    
    # Network protection
    log_info "Enabling network protection (block mode)..."
    mdatp config network-protection enforcement-level --value block
    
    # Real-time protection
    log_info "Enabling real-time protection..."
    mdatp config real-time-protection --value enabled
    
    # Behavior monitoring
    log_info "Enabling behavior monitoring..."
    mdatp config behavior-monitoring --value enabled
    
    log_info "CLI configuration complete"
}

# Onboard to Defender for Cloud
onboard_mde() {
    if [[ -z "${ONBOARDING_SCRIPT}" ]]; then
        log_warn "No onboarding script provided - skipping onboarding"
        log_info ""
        log_info "To onboard manually:"
        log_info "  1. Download onboarding package from Defender portal"
        log_info "  2. Run: sudo python3 MicrosoftDefenderATPOnboardingLinuxServer.py"
        log_info "  OR"
        log_info "  3. Set ONBOARDING_SCRIPT=/path/to/script.py and re-run this installer"
        return 0
    fi
    
    if [[ ! -f "${ONBOARDING_SCRIPT}" ]]; then
        log_error "Onboarding script not found: ${ONBOARDING_SCRIPT}"
        exit 1
    fi
    
    log_info "Running onboarding script..."
    if python3 "${ONBOARDING_SCRIPT}"; then
        log_info "Onboarding completed successfully!"
    else
        log_error "Onboarding failed"
        exit 1
    fi
}

# Verify installation and health
verify_installation() {
    log_info "Verifying MDE installation..."
    
    # Check if mdatp command is available
    if ! command -v mdatp &>/dev/null; then
        log_error "mdatp command not found - installation may have failed"
        exit 1
    fi
    
    # Check version
    log_info "MDE Version: $(mdatp version)"
    
    # Check health
    log_info "Checking MDE health status..."
    mdatp health
    
    # Check if managed config is being used
    if [[ -f "${MANAGED_CONFIG_FILE}" ]]; then
        log_info "Managed configuration detected at: ${MANAGED_CONFIG_FILE}"
    fi
    
    # Show current configuration
    log_info ""
    log_info "Current Configuration:"
    log_info "  Real-time Protection: $(mdatp config real-time-protection --value show 2>/dev/null || echo 'N/A')"
    log_info "  Behavior Monitoring: $(mdatp config behavior-monitoring --value show 2>/dev/null || echo 'N/A')"
    log_info "  Network Protection: $(mdatp config network-protection enforcement-level --value show 2>/dev/null || echo 'N/A')"
}

# Print useful commands
print_useful_commands() {
    log_info ""
    log_info "==================================="
    log_info "Useful MDE Commands:"
    log_info "==================================="
    log_info "Check health:           mdatp health"
    log_info "Check connectivity:     mdatp connectivity test"
    log_info "Run scan:               mdatp scan quick"
    log_info "View definitions:       mdatp definitions statistics"
    log_info "Update definitions:     mdatp definitions update"
    log_info "View logs:              journalctl -u mdatp"
    log_info "Check config:           mdatp config list-all"
    log_info "View threats:           mdatp threat list"
    log_info ""
    log_info "Configuration files:"
    log_info "  Managed config:       ${MANAGED_CONFIG_FILE}"
    log_info "  Log directory:        /var/log/microsoft/mdatp/"
    log_info "==================================="
}

# Cleanup
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f "${MDE_INSTALLER}"
}

# Main execution
main() {
    log_info "Starting Microsoft Defender for Endpoint installation for RHEL 9"
    
    check_root
    check_rhel_version
    download_installer
    install_mde
    
    # Ask user about configuration preference
    log_info ""
    read -p "Use managed configuration file (mdatp_managed.json)? Recommended for enterprise (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Using CLI configuration..."
        configure_mde_cli
    else
        log_info "Using managed configuration..."
        create_managed_config
        log_warn "Note: Managed config may require service restart to take effect"
        read -p "Restart mdatp service now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            systemctl restart mdatp
            log_info "Service restarted"
        fi
    fi
    
    onboard_mde
    verify_installation
    cleanup
    print_useful_commands
    
    log_info ""
    log_info "Installation complete!"
}

# Run main function
main "$@"
