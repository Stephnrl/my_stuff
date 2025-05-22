#!/bin/bash

# GHES Single Node Upgrade Script - Part 1 (Pre-Reboot)
# Usage: ./ghes-upgrade-part1.sh /path/to/upgrade-package.pkg
# 
# This script will:
# 1. Validate the upgrade package
# 2. Enable maintenance mode
# 3. Pause for manual snapshot creation
# 4. Perform the upgrade (system will reboot automatically)
# 
# After reboot, run ghes-upgrade-part2.sh to complete the process

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

# Function to create post-reboot reminder file
create_post_reboot_reminder() {
    local reminder_file="/home/admin/ghes-upgrade-part2-reminder.txt"
    
    cat > "$reminder_file" << 'EOF'
====================================================================
GHES UPGRADE - POST-REBOOT INSTRUCTIONS
====================================================================

Your GHES upgrade has completed the installation phase and rebooted.

NEXT STEPS:
1. Wait for the system to fully boot up
2. SSH back into your GHES instance:
   ssh -p 122 admin@your-ghes-hostname

3. Run the post-upgrade script:
   ./ghes-upgrade-part2.sh

The post-upgrade script will:
- Monitor background upgrade jobs
- Verify the upgrade
- Disable maintenance mode
- Complete the upgrade process

DO NOT manually disable maintenance mode until running part 2!

====================================================================
EOF

    success "Post-reboot reminder created: $reminder_file"
}

# Function to perform the upgrade
perform_upgrade() {
    local package_path="$1"
    
    log "Starting GHES upgrade with package: $package_path"
    warning "This process will:"
    warning "1. Verify the package signature"
    warning "2. Install the upgrade"
    warning "3. AUTOMATICALLY REBOOT the system"
    echo ""
    warning "IMPORTANT: After reboot, you MUST run ghes-upgrade-part2.sh"
    warning "Your SSH session will be terminated when the system reboots!"
    echo ""
    
    read -p "Are you ready for the system to reboot? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Upgrade cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Starting upgrade process (system will reboot automatically)..."
    
    # Run the upgrade with explicit confirmation handling
    echo "y" | ghe-upgrade "$package_path"
    
    # This line should never be reached due to reboot, but just in case
    warning "If you see this message, the upgrade may have failed"
    error "Check /var/log/ghe-upgrade.log for details"
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
    log "=== GHES Single Node Upgrade Script - Part 1 (Pre-Reboot) ==="
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
    warning "This will perform a GHES upgrade which involves:"
    warning "1. Enabling maintenance mode (users will see maintenance page)"
    warning "2. Installing the upgrade package"
    warning "3. AUTOMATIC SYSTEM REBOOT"
    warning "4. You MUST run ghes-upgrade-part2.sh after reboot"
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
    
    # Step 3: Create post-reboot reminder
    create_post_reboot_reminder
    
    # Step 4: Perform upgrade (this will reboot the system)
    perform_upgrade "$package_path"
}

# Run main function with all arguments
main "$@"
