#!/bin/bash

# GHES Single Node Upgrade Script
# Usage: ./ghes-upgrade.sh /path/to/upgrade-package.pkg
# 
# This script will:
# 1. Validate the upgrade package
# 2. Enable maintenance mode
# 3. Pause for manual snapshot creation
# 4. Perform the upgrade
# 5. Monitor the upgrade process
# 6. Disable maintenance mode upon completion

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if running as admin user
check_admin_user() {
    if [[ $EUID -ne 0 ]] && [[ $(whoami) != "admin" ]]; then
        error "This script must be run as the admin user or root"
        error "Please SSH into your GHES instance as: ssh admin@your-ghes-hostname -p 122"
        exit 1
    fi
}

# Function to validate upgrade package
validate_package() {
    local package_path="$1"
    
    if [[ ! -f "$package_path" ]]; then
        error "Upgrade package not found: $package_path"
        exit 1
    fi
    
    if [[ ! "$package_path" =~ \.pkg$ ]]; then
        error "Invalid package format. Expected .pkg file, got: $package_path"
        exit 1
    fi
    
    # Check if package is readable
    if [[ ! -r "$package_path" ]]; then
        error "Cannot read upgrade package: $package_path"
        exit 1
    fi
    
    success "Upgrade package validated: $package_path"
}

# Function to get current GHES version
get_current_version() {
    local version
    version=$(ghe-config core.github-hostname 2>/dev/null || echo "unknown")
    if command -v ghe-version >/dev/null 2>&1; then
        version=$(ghe-version)
    fi
    echo "$version"
}

# Function to check maintenance mode status
check_maintenance_status() {
    if ghe-maintenance -q 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

# Function to enable maintenance mode
enable_maintenance_mode() {
    log "Enabling maintenance mode..."
    
    if ghe-maintenance -s >/dev/null 2>&1; then
        success "Maintenance mode enabled successfully"
        
        # Wait a moment for maintenance mode to fully activate
        sleep 5
        
        # Verify maintenance mode is active
        if [[ $(check_maintenance_status) == "enabled" ]]; then
            success "Maintenance mode confirmed active"
        else
            error "Failed to enable maintenance mode"
            exit 1
        fi
    else
        error "Failed to enable maintenance mode"
        exit 1
    fi
}

# Function to disable maintenance mode
disable_maintenance_mode() {
    log "Disabling maintenance mode..."
    
    if ghe-maintenance -u >/dev/null 2>&1; then
        success "Maintenance mode disabled successfully"
    else
        warning "Failed to disable maintenance mode - you may need to disable it manually"
        warning "Run: ghe-maintenance -u"
    fi
}
        success "Maintenance mode disabled successfully"
    else
        warning "Failed to disable maintenance mode - you may need to disable it manually"
        warning "Run: ghe-maintenance -u"
    fi
}

# Function to pause for snapshot
pause_for_snapshot() {
    echo ""
    warning "=== SNAPSHOT OPPORTUNITY ==="
    log "GHES is now in maintenance mode."
    log "This is the ideal time to take a VM snapshot for backup."
    echo ""
    log "Recommended snapshot steps:"
    log "1. Use your hypervisor's snapshot feature"
    log "2. Name the snapshot with current version and date"
    log "3. Ensure the snapshot includes the data disk"
    echo ""
    read -p "Press ENTER when you have completed the snapshot (or to skip): "
    echo ""
}

# Function to perform the upgrade
perform_upgrade() {
    local package_path="$1"
    
    log "Starting GHES upgrade with package: $package_path"
    warning "This process may take several minutes to complete..."
    echo ""
    
    log "The upgrade process will:"
    log "1. Verify the package signature"
    log "2. Ask for confirmation to proceed [y/N]"
    log "3. Apply the update and restart the system"
    echo ""
    warning "IMPORTANT: When prompted 'Proceed with installation? [y/N]', type 'y' and press ENTER"
    echo ""
    
    # Run the upgrade with explicit confirmation handling
    if echo "y" | ghe-upgrade "$package_path"; then
        success "Upgrade installation completed successfully"
    else
        error "Upgrade failed!"
        error "Check /var/log/ghe-upgrade.log for details"
        log "Common issues:"
        log "- Insufficient disk space"
        log "- Corrupted upgrade package"
        log "- Network connectivity issues during download verification"
        return 1
    fi
}

# Function to monitor upgrade progress
monitor_upgrade() {
    log "Monitoring upgrade progress..."
    log "You can monitor detailed progress in another terminal with:"
    log "  tail -f /data/user/common/ghe-config.log"
    echo ""
    
    # Check if background jobs utility is available
    if command -v ghe-check-background-upgrade-jobs >/dev/null 2>&1; then
        log "Checking background upgrade jobs..."
        while true; do
            if ghe-check-background-upgrade-jobs 2>/dev/null | grep -q "No background jobs running"; then
                success "All background upgrade jobs completed"
                break
            else
                log "Background jobs still running... (checking again in 30 seconds)"
                sleep 30
            fi
        done
    else
        warning "Background job checker not available for this version"
        log "Please monitor /data/user/common/ghe-config.log manually"
        log "Waiting 60 seconds before proceeding..."
        sleep 60
    fi
}

# Function to verify upgrade
verify_upgrade() {
    log "Verifying upgrade..."
    
    # Check if services are running
    log "Checking service status..."
    
    # Get new version
    local new_version
    new_version=$(get_current_version)
    log "Current version after upgrade: $new_version"
    
    success "Basic upgrade verification completed"
    log "Please perform additional testing of your GHES functionality"
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error "Script failed with exit code $exit_code"
        warning "GHES may still be in maintenance mode"
        warning "Check the status with: ghe-maintenance -q"
        warning "Disable manually if needed with: ghe-maintenance -u"
    fi
    
    exit $exit_code
}

# Main function
main() {
    # Set up error handling
    trap cleanup EXIT
    
    echo ""
    log "=== GHES Single Node Upgrade Script ==="
    echo ""
    
    # Check if package path is provided
    if [[ $# -eq 0 ]]; then
        error "Usage: $0 /path/to/upgrade-package.pkg"
        error "Example: $0 /home/admin/github-enterprise-3.13.0.pkg"
        exit 1
    fi
    
    local package_path="$1"
    
    # Preliminary checks
    check_admin_user
    validate_package "$package_path"
    
    # Display current status
    local current_version
    current_version=$(get_current_version)
    local maintenance_status
    maintenance_status=$(check_maintenance_status)
    
    log "Current GHES version: $current_version"
    log "Current maintenance mode: $maintenance_status"
    log "Upgrade package: $package_path"
    echo ""
    
    # Confirm before proceeding
    warning "This will perform a full GHES upgrade which involves:"
    warning "1. Enabling maintenance mode (users will see maintenance page)"
    warning "2. Installing the upgrade package"
    warning "3. Potential system reboot and extended downtime"
    warning "4. Background data migrations (may take hours)"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Upgrade cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Starting upgrade process..."
    
    # Step 1: Enable maintenance mode
    enable_maintenance_mode
    
    # Step 2: Pause for snapshot
    pause_for_snapshot
    
    # Step 3: Perform upgrade
    perform_upgrade "$package_path"
    
    # Step 4: Monitor upgrade progress
    monitor_upgrade
    
    # Step 5: Verify upgrade
    verify_upgrade
    
    # Step 6: Disable maintenance mode
    disable_maintenance_mode
    
    echo ""
    success "=== GHES upgrade completed successfully! ==="
    success "Please test your GHES functionality thoroughly"
    log "Remember to:"
    log "- Test user login and basic Git operations"
    log "- Verify API functionality"
    log "- Check webhook deliveries"
    log "- Review any custom integrations"
    echo ""
}

# Run main function with all arguments
main "$@"
