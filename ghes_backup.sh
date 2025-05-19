#!/bin/bash
#
# GitHub Enterprise Server Backup Utilities Setup Script
# This script sets up backup-utils for multiple GHES instances
# Compatible with GHES 3.11.x
#
# Usage: ./setup-backup-utils.sh

set -e

# Configuration - Edit these variables
BACKUP_UTILS_VERSION="3.11.3"
BACKUP_ROOT="/opt/github-backup-utils"
BACKUP_DATA_DIR="/data/github-backups"

# Add GHES instances here
# FORMAT: "hostname:port:name:backup_dir:ssh_key_name:backup_user"
GHES_INSTANCES=(
  "ghes1.example.com:122:ghes1:${BACKUP_DATA_DIR}/ghes1:id_rsa_ghes1:backup-ghes1"
  "ghes2.example.com:122:ghes2:${BACKUP_DATA_DIR}/ghes2:id_rsa_ghes2:backup-ghes2"
  # Add more instances as needed
)

# Number of snapshots to keep for each instance
NUM_SNAPSHOTS=10

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  print_message "$RED" "This script must be run as root"
  exit 1
fi

# Banner
echo "=================================================="
print_message "$GREEN" "GitHub Enterprise Server Backup Utilities Setup"
print_message "$GREEN" "Version: $BACKUP_UTILS_VERSION"
echo "=================================================="

# Install dependencies
print_message "$YELLOW" "Installing dependencies..."
apt-get update
apt-get install -y \
  bash \
  git \
  openssh-client \
  rsync \
  jq \
  bc \
  gawk \
  moreutils

# Check rsync version
RSYNC_VERSION=$(rsync --version | head -n1 | grep -oP '[\d\.]+' | head -1)
print_message "$YELLOW" "Installed rsync version: $RSYNC_VERSION"

# Check if rsync version is affected by CVE-2022-29154 performance issue
if dpkg --compare-versions "$RSYNC_VERSION" lt "3.2.5"; then
  print_message "$YELLOW" "Warning: Your rsync version is older than 3.2.5."
  print_message "$YELLOW" "It may have performance issues if the fix for CVE-2022-29154 was backported without the --trust-sender flag."
  print_message "$YELLOW" "Consider upgrading rsync if you experience slow backups."
  
  read -p "Do you want to attempt to install a newer version of rsync? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_message "$YELLOW" "Attempting to install a newer version of rsync..."
    # Backup the current rsync
    if [ -f /usr/bin/rsync ]; then
      mv /usr/bin/rsync /usr/bin/rsync.bak
    fi
    
    # Install build dependencies
    apt-get install -y build-essential libssl-dev
    
    # Download and build rsync 3.2.7
    cd /tmp
    wget https://download.samba.org/pub/rsync/src/rsync-3.2.7.tar.gz
    tar xvf rsync-3.2.7.tar.gz
    cd rsync-3.2.7
    ./configure
    make
    make install
    
    # Check new version
    rsync --version
    print_message "$GREEN" "Rsync upgraded. If there are issues, you can restore the backup from /usr/bin/rsync.bak"
  fi
fi

# Create the backup data directory if it doesn't exist
print_message "$YELLOW" "Creating backup data directory: $BACKUP_DATA_DIR"
mkdir -p "$BACKUP_DATA_DIR"

# Download and install backup-utils
print_message "$YELLOW" "Downloading backup-utils $BACKUP_UTILS_VERSION..."
cd /tmp
wget "https://github.com/github/backup-utils/releases/download/v${BACKUP_UTILS_VERSION}/github-backup-utils-v${BACKUP_UTILS_VERSION}.tar.gz"
tar xvf "github-backup-utils-v${BACKUP_UTILS_VERSION}.tar.gz"
mkdir -p "$BACKUP_ROOT"
cp -r "github-backup-utils-v${BACKUP_UTILS_VERSION}/"* "$BACKUP_ROOT"

# Now set up each GHES instance
for instance in "${GHES_INSTANCES[@]}"; do
  # Parse the instance configuration
  IFS=':' read -r hostname port name backup_dir ssh_key_name backup_user <<< "$instance"
  
  print_message "$GREEN" "Setting up backup for $name ($hostname:$port)"
  
  # Create backup user if it doesn't exist
  if ! id -u "$backup_user" >/dev/null 2>&1; then
    print_message "$YELLOW" "Creating user $backup_user"
    useradd -m -s /bin/bash "$backup_user"
  fi
  
  # Create backup directory for this instance
  mkdir -p "$backup_dir"
  chown -R "$backup_user":"$backup_user" "$backup_dir"
  
  # Create SSH directory for the backup user
  USER_HOME=$(eval echo ~"$backup_user")
  SSH_DIR="$USER_HOME/.ssh"
  mkdir -p "$SSH_DIR"
  
  # Generate SSH key if it doesn't exist
  if [ ! -f "$SSH_DIR/$ssh_key_name" ]; then
    print_message "$YELLOW" "Generating SSH key for $backup_user"
    sudo -u "$backup_user" ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/$ssh_key_name" -N "" -C "$backup_user@$(hostname)"
    print_message "$GREEN" "SSH key generated: $SSH_DIR/$ssh_key_name"
    print_message "$YELLOW" "Public key (add this to your GHES instance):"
    cat "$SSH_DIR/$ssh_key_name.pub"
    echo
  fi
  
  # Create SSH config for this GHES instance
  cat << EOF > "$SSH_DIR/config"
Host $hostname
  HostName $hostname
  User admin
  Port $port
  IdentityFile $SSH_DIR/$ssh_key_name
  StrictHostKeyChecking no
EOF
  
  # Create backup config for this instance
  CONFIG_FILE="$USER_HOME/backup-$name.config"
  cat << EOF > "$CONFIG_FILE"
# GitHub Enterprise Server Backup Configuration for $name
GHE_HOSTNAME="$hostname"
GHE_DATA_DIR="$backup_dir"
GHE_NUM_SNAPSHOTS="$NUM_SNAPSHOTS"
GHE_SSH_PORT="$port"
GHE_EXTRA_SSH_OPTS="-i $SSH_DIR/$ssh_key_name"
EOF
  
  # Create backup script for this instance
  BACKUP_SCRIPT="$USER_HOME/backup-$name.sh"
  cat << EOF > "$BACKUP_SCRIPT"
#!/bin/bash
# Backup script for GHES instance: $name

# Export backup configuration
export GHE_BACKUP_CONFIG="$CONFIG_FILE"

# Run backup with proper logging
LOG_DIR="$USER_HOME/logs"
mkdir -p "\$LOG_DIR"
LOG_FILE="\$LOG_DIR/backup-$name-\$(date +%Y%m%d-%H%M%S).log"

echo "Starting backup of $name at \$(date)" | tee -a "\$LOG_FILE"
$BACKUP_ROOT/bin/ghe-backup -v 2>&1 | tee -a "\$LOG_FILE"
BACKUP_EXIT=\${PIPESTATUS[0]}
echo "Backup completed with exit code \$BACKUP_EXIT at \$(date)" | tee -a "\$LOG_FILE"

# Cleanup old logs (keep 20 most recent)
find "\$LOG_DIR" -name "backup-$name-*.log" -type f -printf '%T@ %p\n' | sort -n | head -n -20 | cut -d ' ' -f 2- | xargs -r rm

exit \$BACKUP_EXIT
EOF
  
  chmod +x "$BACKUP_SCRIPT"
  
  # Create cronjob for this instance
  # Stagger the runs to avoid overlap
  # Different instances will run at different hours
  CRON_HOUR=$((RANDOM % 24))
  CRON_MINUTE=$((RANDOM % 60))
  
  CRON_FILE="/etc/cron.d/github-backup-$name"
  cat << EOF > "$CRON_FILE"
# GitHub Enterprise Server Backup for $name
# Run daily at $CRON_HOUR:$CRON_MINUTE
$CRON_MINUTE $CRON_HOUR * * * $backup_user $BACKUP_SCRIPT
EOF
  
  # Set proper permissions
  chown -R "$backup_user":"$backup_user" "$SSH_DIR" "$CONFIG_FILE" "$BACKUP_SCRIPT"
  chmod 600 "$SSH_DIR/config" "$CONFIG_FILE"
  
  print_message "$GREEN" "Setup completed for $name"
  print_message "$YELLOW" "Backup will run daily at $CRON_HOUR:$CRON_MINUTE"
  print_message "$YELLOW" "You can run a manual backup with: sudo -u $backup_user $BACKUP_SCRIPT"
  echo
  
  # Instructions for adding SSH key to GHES
  print_message "$YELLOW" "IMPORTANT: Add this SSH public key to your GHES instance $name:"
  print_message "$NC" "$(cat "$SSH_DIR/$ssh_key_name.pub")"
  echo
  print_message "$YELLOW" "You can add this key in the GHES Management Console under 'Settings' > 'Authorized SSH Keys'"
  echo
done

# Final instructions
print_message "$GREEN" "GitHub Enterprise Server Backup Utilities setup completed!"
print_message "$YELLOW" "Please ensure you add the SSH public keys to your GHES instances"
print_message "$YELLOW" "You can check the backup configs in each user's home directory"
print_message "$YELLOW" "Test the backups manually before relying on the cron jobs"
echo "=================================================="
