#!/usr/bin/env python3

"""
Azure Dynamic Inventory Script for GitHub VMs
Requires: Azure CLI (az) to be installed and logged in

Usage: 
  ./azure_github_inventory.py --list    (for Ansible)
  ./azure_github_inventory.py --host <hostname>  (for Ansible)
  ./azure_github_inventory.py --save    (save to file)
"""

import json
import subprocess
import sys
import argparse
import os
from typing import Dict, List, Any, Optional

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    NC = '\033[0m'  # No Color

class AzureInventory:
    def __init__(self, silent_mode=False):
        self.silent_mode = silent_mode
        self.inventory = {
            "github_enterprise": {
                "hosts": {},
                "vars": {
                    "group_description": "GitHub Enterprise VMs"
                }
            },
            "github_backup": {
                "hosts": {},
                "vars": {
                    "group_description": "GitHub Backup VMs"
                }
            },
            "_meta": {
                "hostvars": {}
            }
        }

    def log(self, message: str):
        """Log informational messages"""
        if not self.silent_mode:
            print(f"{Colors.GREEN}[INFO]{Colors.NC} {message}", file=sys.stderr)

    def error(self, message: str):
        """Log error messages"""
        print(f"{Colors.RED}[ERROR]{Colors.NC} {message}", file=sys.stderr)

    def warn(self, message: str):
        """Log warning messages"""
        if not self.silent_mode:
            print(f"{Colors.YELLOW}[WARN]{Colors.NC} {message}", file=sys.stderr)

    def run_az_command(self, command: List[str]) -> Optional[Dict]:
        """Run Azure CLI command and return JSON result"""
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout) if result.stdout.strip() else None
        except subprocess.CalledProcessError as e:
            self.error(f"Azure CLI command failed: {' '.join(command)}")
            self.error(f"Error: {e.stderr}")
            return None
        except json.JSONDecodeError as e:
            self.error(f"Failed to parse JSON output from Azure CLI")
            self.error(f"Error: {e}")
            return None

    def check_prerequisites(self) -> bool:
        """Check if Azure CLI is installed and user is logged in"""
        # Check if az is installed
        try:
            subprocess.run(['az', '--version'], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.error("Azure CLI (az) is not installed. Please install it first.")
            return False

        # Check if user is logged in
        account_info = self.run_az_command(['az', 'account', 'show'])
        if account_info is None:
            self.error("You are not logged in to Azure. Please run 'az login' first.")
            return False

        subscription_id = account_info.get('id', 'Unknown')
        subscription_name = account_info.get('name', 'Unknown')
        self.log(f"Using subscription: {subscription_name} ({subscription_id})")
        
        return True

    def get_github_vms(self) -> List[Dict]:
        """Get all VMs with 'github' in name"""
        self.log("Searching for VMs with 'github' in name...")
        
        vms = self.run_az_command(['az', 'vm', 'list', '--show-details', '--output', 'json'])
        if vms is None:
            return []

        # Filter VMs with 'github' in name (case insensitive)
        github_vms = [vm for vm in vms if 'github' in vm.get('name', '').lower()]
        
        if not github_vms:
            self.warn("No VMs found with 'github' in the name.")
        
        return github_vms

    def get_vm_details(self, vm_id: str) -> Optional[Dict]:
        """Get detailed VM information"""
        return self.run_az_command(['az', 'vm', 'show', '--ids', vm_id, '--output', 'json'])

    def process_vm(self, vm: Dict):
        """Process a single VM and add to inventory"""
        vm_name = vm.get('name')
        vm_id = vm.get('id')
        resource_group = vm.get('resourceGroup')
        location = vm.get('location')
        power_state = vm.get('powerState', 'Unknown')
        
        self.log(f"Processing VM: {vm_name}")
        
        # Get private IP address
        private_ips = vm.get('privateIps')
        if isinstance(private_ips, list) and private_ips:
            private_ip = private_ips[0]
        elif isinstance(private_ips, str):
            private_ip = private_ips
        else:
            private_ip = None

        if not private_ip:
            self.warn(f"No private IP found for {vm_name}, skipping...")
            return

        # Get detailed VM info to check image publisher
        vm_details = self.get_vm_details(vm_id)
        if vm_details is None:
            self.warn(f"Could not get detailed info for {vm_name}, skipping...")
            return

        storage_profile = vm_details.get('storageProfile', {})
        image_reference = storage_profile.get('imageReference', {})
        
        image_publisher = image_reference.get('publisher', 'unknown')
        image_offer = image_reference.get('offer', 'unknown')
        image_sku = image_reference.get('sku', 'unknown')
        vm_size = vm_details.get('hardwareProfile', {}).get('vmSize', 'unknown')

        # Determine group based on image publisher
        if image_publisher == "GitHub":
            group = "github_enterprise"
            self.log(f"  → Adding to github_enterprise group (Publisher: {image_publisher})")
        else:
            group = "github_backup"
            self.log(f"  → Adding to github_backup group (Publisher: {image_publisher})")

        # Create host variables
        host_vars = {
            'ansible_host': private_ip,
            'ansible_user': 'azureuser',
            'vm_name': vm_name,
            'vm_id': vm_id,
            'resource_group': resource_group,
            'location': location,
            'power_state': power_state,
            'private_ip': private_ip,
            'image_publisher': image_publisher,
            'image_offer': image_offer,
            'image_sku': image_sku,
            'vm_size': vm_size
        }

        # Add to inventory
        self.inventory[group]['hosts'][vm_name] = private_ip
        self.inventory['_meta']['hostvars'][vm_name] = host_vars

    def generate_inventory(self) -> Dict:
        """Generate the complete inventory"""
        if not self.check_prerequisites():
            return self.inventory

        github_vms = self.get_github_vms()
        
        for vm in github_vms:
            self.process_vm(vm)

        if not self.silent_mode:
            self.log("Inventory generation complete!")
        
        return self.inventory

    def save_inventory(self, filename: str = "azure_github_inventory.json"):
        """Save inventory to file"""
        inventory = self.generate_inventory()
        with open(filename, 'w') as f:
            json.dump(inventory, f, indent=2)
        self.log(f"Inventory saved to {filename}")

def main():
    parser = argparse.ArgumentParser(
        description='Azure Dynamic Inventory Script for GitHub VMs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --list              # Return full inventory (for Ansible)
  %(prog)s --host vm-name      # Return host variables (for Ansible)  
  %(prog)s --save              # Generate inventory and save to file
        """
    )
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--list', action='store_true',
                      help='Return full inventory (for Ansible)')
    group.add_argument('--host', metavar='HOSTNAME',
                      help='Return host variables (for Ansible)')
    group.add_argument('--save', action='store_true',
                      help='Generate inventory and save to file')

    args = parser.parse_args()

    if args.host:
        # For --host, return empty JSON as we include all host vars in --list
        print(json.dumps({}))
        return

    # Determine if we should run in silent mode (for --list)
    silent_mode = args.list
    
    inventory = AzureInventory(silent_mode=silent_mode)
    
    if args.save:
        inventory.save_inventory()
    else:
        result = inventory.generate_inventory()
        print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
