#!/bin/bash
set -e

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root or with sudo"
    exit 1
fi

# Confirm the data disk exists
if [ ! -b /dev/sdc ]; then
    echo "Error: /dev/sdc not found"
    exit 1
fi

# Check if the disk is already partitioned
if lsblk | grep -q "sdc1"; then
    echo "Warning: /dev/sdc already has partitions. This script will not continue."
    exit 1
fi

echo "Creating partition on /dev/sdc..."
# Create a new partition using the entire disk
parted /dev/sdc --script mklabel gpt
parted /dev/sdc --script mkpart primary 0% 100%

# Wait for partition to be recognized by the system
sleep 3
echo "Partition created."

# Set up LVM
echo "Setting up LVM..."
pvcreate /dev/sdc1
vgcreate github_vg /dev/sdc1
# Use 100% of the available space in the volume group
lvcreate -l 100%FREE -n github_lv github_vg

# Format the logical volume
echo "Formatting the logical volume..."
mkfs.ext4 /dev/github_vg/github_lv

# Create the mount directory if it doesn't exist
echo "Creating mount point..."
mkdir -p /data/github-backups

# Update fstab to automatically mount on boot
echo "Updating /etc/fstab..."
echo "/dev/github_vg/github_lv /data/github-backups ext4 defaults,nofail 0 2" >> /etc/fstab

# Mount the filesystem
echo "Mounting the filesystem..."
mount /data/github-backups

# Create the subdirectories for each GHES instance
echo "Creating backup directories..."
mkdir -p /data/github-backups/backup-ghes-abc
mkdir -p /data/github-backups/backup-ghes-def
mkdir -p /data/github-backups/backup-ghes-ghi

# Set appropriate permissions
echo "Setting permissions..."
chmod 755 /data/github-backups
chmod 750 /data/github-backups/backup-ghes-abc
chmod 750 /data/github-backups/backup-ghes-def
chmod 750 /data/github-backups/backup-ghes-ghi

echo "Setup complete! Your github backup directories are ready at /data/github-backups/"
echo "Disk usage:"
