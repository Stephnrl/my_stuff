#!/bin/bash

# GHES Single Node Upgrade Script - Part 2 (Post-Reboot)
# Usage: ./ghes-upgrade-part2.sh
# 
# This script runs AFTER the system has rebooted from the upgrade.
# It will:
# 1. Wait for system to be ready
# 2. Monitor background upgrade jobs
# 3. Verify the upgrade
# 4. Disable maintenance mode
# 5. Complete the upgrade process

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

# Function to wait for system readiness
wait_for_system_ready() {
    log "Waiting for GHES system to be fully ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log "Checking system readiness (attempt $attempt/$max_attempts)..."
        
        # Check if basic GHES commands are responding
        if ghe-config --help >/dev/null 2>&1; then
            success "System appears ready"
            sleep 10  # Give it a bit more time
            return 0
        fi
        
        log "System not ready yet, waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done
    
    warning "System may not be fully ready, but proceeding anyway"
    warning "If you encounter errors, wait longer and try again"
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
        local max_wait_time=3600  # 1 hour max wait
        local elapsed_time=0
        local check_interval=30
        
        while [[ $elapsed_time -lt $max_wait_time ]]; do
            local job_output
            job_output=$(ghe-check-background-upgrade-jobs 2>/dev/null || echo "error")
            
            if [[ "$job_output" == *"No background jobs running"* ]]; then
                success "All background upgrade jobs completed"
                break
            elif [[ "$job_output" == "error" ]]; then
                warning "Unable to check background jobs status"
                log "This might be normal during early boot process"
            else
                log "Background jobs still running... (elapsed: ${elapsed_time}s)"
                log "Current status: $job_output"
            fi
            
            sleep $check_interval
            elapsed_time=$((elapsed_time + check_interval))
        done
        
        if [[ $elapsed_time -ge $max_wait_time ]]; then
            warning "Timeout waiting for background jobs to complete"
            warning "You may need to wait longer or check manually"
        fi
    else
        warning "Background job checker not available for this version"
        log "Please monitor /data/user/common/ghe-config.log manually"
        log "Waiting 5 minutes before proceeding..."
        sleep 300
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
    
    # Check if maintenance mode is still enabled (it should be)
    local maintenance_status
    maintenance_status=$(check_maintenance_status)
    log "Maintenance mode status: $maintenance_status"
    
    if [[ "$maintenance_status" != "enabled" ]]; then
        warning "Maintenance mode is not enabled - this is unexpected"
        warning "The upgrade process may have already completed"
    fi
    
    success "Basic upgrade verification completed"
    log "Please perform additional testing of your GHES functionality after maintenance mode is disabled"
}

# Function to disable maintenance mode
disable_maintenance_mode() {
    log "Disabling maintenance mode..."
    
    if ghe-maintenance -u >/dev/null 2>&1; then
        success "Maintenance mode disabled successfully"
        success "GHES is now available to users"
    else
        error "Failed to disable maintenance mode"
        error "You may need to disable it manually with: ghe-maintenance -u"
        return 1
    fi
}

# Function to cleanup reminder file
cleanup_reminder() {
    local reminder_file="/home/admin/ghes-upgrade-part2-reminder.txt"
    
    if [[ -f "$reminder_file" ]]; then
        rm -f "$reminder_file" 2>/dev/null || true
        log "Cleaned up reminder file"
    fi
}

# Function to display post-upgrade instructions
display_post_upgrade_instructions() {
    echo ""
    success "=== GHES upgrade completed successfully! ==="
    echo ""
    success "IMPORTANT: Please verify your GHES functionality:"
    log "1. Test user login via web interface"
    log "2. Verify Git operations (clone, push, pull)"
    log "3. Check API functionality"
    log "4. Test webhook deliveries"
    log "5. Review any custom integrations"
    log "6. Check system logs for any errors"
    echo ""
    log "Useful commands for verification:"
    log "- Check version: ghe-version"
    log "- Check maintenance status: ghe-maintenance -q"
    log "- View config logs: tail -f /data/user/common/ghe-config.log"
    log "- Check service status: sudo service --status-all"
    echo ""
    warning "If you notice any issues, check /var/log/ for error logs"
    success "Upgrade process completed!"
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error "Post-upgrade script failed with exit code $exit_code"
        warning "Your GHES may still be in maintenance mode"
        warning "Check the status with: ghe-maintenance -q"
        warning "You may need to manually disable maintenance mode: ghe-maintenance -u"
    fi
    
    exit $exit_code
}

# Main function
main() {
    # Set up error handling
    trap cleanup EXIT
    
    echo ""
    log "=== GHES Single Node Upgrade Script - Part 2 (Post-Reboot) ==="
    echo ""
    
    # Preliminary checks
    check_admin_user
    
    # Display current status
    local current_version
    current_version=$(get_current_version)
    local maintenance_status
    maintenance_status=$(check_maintenance_status)
    
    log "Current GHES version: $current_version"
    log "Current maintenance mode: $maintenance_status"
    echo ""
    
    # Confirm this is the right time to run
    if [[ "$maintenance_status" != "enabled" ]]; then
        warning "Maintenance mode is not currently enabled"
        warning "This script should be run after an upgrade when maintenance mode is still active"
        read -p "Do you want to continue anyway? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Script cancelled by user"
            exit 0
        fi
    fi
    
    log "Starting post-upgrade process..."
    echo ""
    
    # Step 1: Wait for system readiness
    wait_for_system_ready
    
    # Step 2: Monitor upgrade progress
    monitor_upgrade
    
    # Step 3: Verify upgrade
    verify_upgrade
    
    # Step 4: Disable maintenance mode
    disable_maintenance_mode
    
    # Step 5: Cleanup
    cleanup_reminder
    
    # Step 6: Display final instructions
    display_post_upgrade_instructions
}

# Run main function
main "$@"
