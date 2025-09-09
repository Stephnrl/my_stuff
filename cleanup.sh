#!/bin/bash
set -e

echo "Starting cleanup process..."

# Clean package manager cache
echo "Cleaning package manager cache..."
sudo dnf clean all
sudo rm -rf /var/cache/dnf/*

# Clean logs
echo "Cleaning logs..."
sudo journalctl --vacuum-time=1d
sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
sudo rm -rf /var/log/audit/*.log
sudo rm -rf /var/log/messages*
sudo rm -rf /var/log/secure*

# Clean temporary files
echo "Cleaning temporary files..."
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Clean SSH host keys (will be regenerated on first boot)
echo "Removing SSH host keys..."
sudo rm -f /etc/ssh/ssh_host_*

# Clean cloud-init
echo "Cleaning cloud-init..."
sudo cloud-init clean --logs --seed

# Remove Ansible staging
echo "Removing Ansible staging files..."
sudo rm -rf /tmp/ansible*
sudo rm -rf /root/.ansible

# Clean bash history
echo "Cleaning bash history..."
history -c
cat /dev/null > ~/.bash_history

# Remove machine-id (will be regenerated)
echo "Removing machine-id..."
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

# Clean network configuration
echo "Cleaning network configuration..."
sudo rm -f /etc/udev/rules.d/70-persistent-net.rules
sudo find /etc/sysconfig/network-scripts/ -name "ifcfg-*" -not -name "ifcfg-lo" -exec rm -f {} \;

# RHEL specific cleanup
echo "RHEL specific cleanup..."
sudo rm -rf /root/.ssh/authorized_keys
sudo rm -rf /home/*/.ssh/authorized_keys
sudo rm -f /etc/sysconfig/network-scripts/ifcfg-eth0

echo "Cleanup complete!"
