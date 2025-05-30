#!/usr/bin/env python3

# inventory_plugins/azure_cli.py

DOCUMENTATION = '''
    name: azure_cli
    plugin_type: inventory
    short_description: Azure inventory source using Azure CLI
    description:
        - Get inventory from Azure using az cli commands
        - Uses existing az login session, no additional auth required
        - Groups VMs by resource group, location, and tags
    options:
        subscriptions:
            description: List of subscription IDs to query (optional)
            type: list
            default: []
        resource_groups:
            description: List of resource group names to filter (optional)
            type: list
            default: []
        locations:
            description: List of locations to filter (optional)
            type: list
            default: []
        include_powerstate:
            description: Include VM power state information
            type: bool
            default: true
        tag_filters:
            description: Dictionary of tag key-value pairs to filter VMs
            type: dict
            default: {}
        compose:
            description: Create vars from jinja2 expressions
            type: dict
            default: {}
        groups:
            description: Add hosts to group based on Jinja2 conditionals
            type: dict
            default: {}
        keyed_groups:
            description: Add hosts to group based on the values of a variable
            type: list
            default: []
'''

EXAMPLES = '''
# inventory_azure_cli.yml
plugin: azure_cli

# Parse specific subscription with all resource groups
subscriptions:
  - "12345678-1234-1234-1234-123456789012"
resource_groups:
  - "*"  # This will get ALL resource groups in the subscription

# Or parse multiple subscriptions with all their resource groups
subscriptions:
  - "subscription-id-1"
  - "subscription-id-2"
resource_groups: ["*"]

# Parse all subscriptions and all resource groups (if not specified)
# subscriptions: []  # Empty or omitted = all accessible subscriptions
# resource_groups: [] # Empty or omitted = all resource groups

# Filter by specific resource groups in specific subscription
subscriptions:
  - "12345678-1234-1234-1234-123456789012"
resource_groups:
  - myapp-prod-rg
  - myapp-staging-rg

# Filter by locations (applied after getting VMs)
locations:
  - eastus
  - westus2

# Filter by tags (applied after getting VMs)
tag_filters:
  Environment: production
  Application: myapp

# Create custom groups
groups:
  production: "'production' in (tags.Environment | default(''))"
  webservers: "'web' in (tags.Role | default(''))"
  databases: "'db' in (tags.Role | default(''))"

# Create keyed groups from variables
keyed_groups:
  - key: location
    prefix: location
  - key: resource_group
    prefix: rg
  - key: tags.Environment | default('untagged')
    prefix: env

# Compose additional variables
compose:
  ansible_host: public_ip | default(private_ip)
  vm_size_family: vm_size.split('_')[0] if vm_size else 'unknown'
  is_production: tags.Environment == 'production'
'''

import json
import subprocess
import sys
from ansible.plugins.inventory import BaseInventoryPlugin, Constructable
from ansible.errors import AnsibleError, AnsibleParserError


class InventoryModule(BaseInventoryPlugin, Constructable):
    NAME = 'azure_cli'

    def verify_file(self, path):
        """Verify that the source file can be processed by this plugin."""
        return (
            super(InventoryModule, self).verify_file(path) and
            path.endswith(('azure_cli.yml', 'azure_cli.yaml'))
        )

    def _run_az_command(self, command):
        """Execute an Azure CLI command and return JSON output."""
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout) if result.stdout.strip() else []
        except subprocess.CalledProcessError as e:
            raise AnsibleError(f"Azure CLI command failed: {e.stderr}")
        except json.JSONDecodeError as e:
            raise AnsibleError(f"Failed to parse Azure CLI JSON output: {e}")

    def _check_az_login(self):
        """Check if user is logged into Azure CLI."""
        try:
            subprocess.run(
                'az account show',
                shell=True,
                capture_output=True,
                check=True
            )
        except subprocess.CalledProcessError:
            raise AnsibleError(
                "Not logged into Azure CLI. Please run 'az login' first."
            )

    def _get_subscriptions(self, subscription_filter=None):
        """Get list of subscriptions."""
        if subscription_filter:
            subscriptions = []
            for sub_id in subscription_filter:
                try:
                    sub_info = self._run_az_command(f'az account show --subscription {sub_id}')
                    subscriptions.append(sub_info)
                except AnsibleError:
                    self.display.warning(f"Subscription {sub_id} not found or accessible")
            return subscriptions
        else:
            return self._run_az_command('az account list --all')

    def _get_vms_for_subscription(self, subscription_id, filters):
        """Get VMs for a specific subscription with filters."""
        resource_groups = filters.get('resource_groups', [])
        
        # If resource_groups contains '*' or is empty, get all VMs in subscription
        if not resource_groups or '*' in resource_groups:
            self.display.vvv(f"Getting all VMs in subscription {subscription_id}")
            command = f'az vm list --subscription {subscription_id} --show-details --output json'
            vms = self._run_az_command(command)
        else:
            # Get VMs from specific resource groups
            all_vms = []
            for rg in resource_groups:
                self.display.vvv(f"Getting VMs from resource group: {rg}")
                try:
                    command = f'az vm list --subscription {subscription_id} --resource-group "{rg}" --show-details --output json'
                    rg_vms = self._run_az_command(command)
                    all_vms.extend(rg_vms)
                except AnsibleError as e:
                    self.display.warning(f"Could not get VMs from resource group {rg}: {e}")
                    continue
            vms = all_vms
        
        # Apply additional filters
        filtered_vms = []
        for vm in vms:
            # Location filter
            if filters.get('locations') and vm.get('location') not in filters['locations']:
                continue
            
            # Tag filters
            vm_tags = vm.get('tags') or {}
            tag_match = True
            for key, value in filters.get('tag_filters', {}).items():
                if vm_tags.get(key) != value:
                    tag_match = False
                    break
            
            if tag_match:
                filtered_vms.append(vm)
        
        return filtered_vms

    def _extract_vm_info(self, vm):
        """Extract relevant information from VM data."""
        vm_info = {
            'name': vm.get('name'),
            'resource_group': vm.get('resourceGroup'),
            'location': vm.get('location'),
            'vm_size': vm.get('hardwareProfile', {}).get('vmSize'),
            'os_type': vm.get('storageProfile', {}).get('osDisk', {}).get('osType'),
            'tags': vm.get('tags') or {},
            'private_ip': None,
            'public_ip': None,
            'fqdns': [],
            'power_state': None,
            'provisioning_state': vm.get('provisioningState'),
            'vm_id': vm.get('vmId'),
            'subscription_id': vm.get('subscriptionId'),
        }
        
        # Extract network information
        if 'networkProfile' in vm:
            for nic in vm['networkProfile'].get('networkInterfaces', []):
                nic_name = nic['id'].split('/')[-1]
                # Note: Getting detailed NIC info would require additional az commands
                # For simplicity, we'll extract what's available in the VM details
        
        # Extract IP addresses from the show-details output
        if 'publicIps' in vm:
            vm_info['public_ip'] = vm['publicIps']
        if 'privateIps' in vm:
            vm_info['private_ip'] = vm['privateIps']
        if 'fqdns' in vm:
            vm_info['fqdns'] = vm['fqdns'].split(',') if vm['fqdns'] else []
        
        # Power state
        if 'powerState' in vm:
            vm_info['power_state'] = vm['powerState']
        
        return vm_info

    def _add_host_to_groups(self, hostname, vm_info):
        """Add host to various groups based on VM properties."""
        # Add to all group
        self.inventory.add_host(hostname, group='all')
        
        # Add to resource group
        rg_group = f"rg_{vm_info['resource_group'].replace('-', '_')}"
        self.inventory.add_group(rg_group)
        self.inventory.add_host(hostname, group=rg_group)
        
        # Add to location group
        location_group = f"location_{vm_info['location'].replace('-', '_')}"
        self.inventory.add_group(location_group)
        self.inventory.add_host(hostname, group=location_group)
        
        # Add to OS type group
        if vm_info['os_type']:
            os_group = f"os_{vm_info['os_type'].lower()}"
            self.inventory.add_group(os_group)
            self.inventory.add_host(hostname, group=os_group)
        
        # Add to VM size family group
        if vm_info['vm_size']:
            size_family = vm_info['vm_size'].split('_')[0] if '_' in vm_info['vm_size'] else vm_info['vm_size']
            size_group = f"size_{size_family.lower()}"
            self.inventory.add_group(size_group)
            self.inventory.add_host(hostname, group=size_group)
        
        # Add to tag-based groups
        for key, value in vm_info['tags'].items():
            safe_key = key.replace('-', '_').replace(' ', '_').lower()
            safe_value = str(value).replace('-', '_').replace(' ', '_').lower()
            tag_group = f"tag_{safe_key}_{safe_value}"
            self.inventory.add_group(tag_group)
            self.inventory.add_host(hostname, group=tag_group)

    def parse(self, inventory, loader, path, cache=True):
        """Parse the inventory file and populate inventory."""
        super(InventoryModule, self).parse(inventory, loader, path, cache)
        
        # Read configuration
        self._read_config_data(path)
        
        # Check Azure CLI login
        self._check_az_login()
        
        # Get configuration options
        subscription_filter = self.get_option('subscriptions')
        filters = {
            'resource_groups': self.get_option('resource_groups'),
            'locations': self.get_option('locations'),
            'tag_filters': self.get_option('tag_filters'),
        }
        
        # Get subscriptions to query
        subscriptions = self._get_subscriptions(subscription_filter)
        
        if not subscriptions:
            self.display.warning("No subscriptions found")
            return
        
        # Process each subscription
        for subscription in subscriptions:
            sub_id = subscription.get('id')
            sub_name = subscription.get('name', sub_id)
            
            self.display.vvv(f"Processing subscription: {sub_name}")
            
            try:
                vms = self._get_vms_for_subscription(sub_id, filters)
                
                for vm in vms:
                    vm_info = self._extract_vm_info(vm)
                    hostname = vm_info['name']
                    
                    # Add host to inventory
                    self.inventory.add_host(hostname)
                    
                    # Set host variables
                    for key, value in vm_info.items():
                        self.inventory.set_variable(hostname, key, value)
                    
                    # Set ansible_host
                    ansible_host = vm_info['public_ip'] or vm_info['private_ip'] or hostname
                    self.inventory.set_variable(hostname, 'ansible_host', ansible_host)
                    
                    # Add to groups
                    self._add_host_to_groups(hostname, vm_info)
                    
                    # Apply constructable features
                    self._set_composite_vars(
                        self.get_option('compose'), 
                        vm_info, 
                        hostname, 
                        strict=False
                    )
                    
                    self._add_host_to_composed_groups(
                        self.get_option('groups'), 
                        vm_info, 
                        hostname, 
                        strict=False
                    )
                    
                    self._add_host_to_keyed_groups(
                        self.get_option('keyed_groups'), 
                        vm_info, 
                        hostname, 
                        strict=False
                    )
                    
            except AnsibleError as e:
                self.display.warning(f"Error processing subscription {sub_name}: {e}")
                continue


---
# ansible.cfg - Add this to enable the custom plugin

[inventory]
enable_plugins = host_list, script, auto, yaml, ini, toml, azure_cli

[defaults]
inventory_plugins = ./inventory_plugins

---
# Example inventory configuration files

# inventory_all_rgs.yml - Get ALL resource groups in specific subscription
plugin: azure_cli

subscriptions:
  - "12345678-1234-1234-1234-123456789012"  # Your subscription ID

resource_groups:
  - "*"  # Wildcard - gets ALL resource groups

# Optional filters (applied after getting all VMs)
locations:
  - eastus
  - westus2

tag_filters:
  Environment: production

groups:
  production: "tags.Environment == 'production'"
  webservers: "'web' in (tags.Role | default(''))"

keyed_groups:
  - key: location
    prefix: location
  - key: resource_group  
    prefix: rg

---
# inventory_multiple_subs_all_rgs.yml - Multiple subscriptions, all RGs each
plugin: azure_cli

subscriptions:
  - "subscription-id-1"
  - "subscription-id-2"
  - "subscription-id-3"

resource_groups: ["*"]  # All resource groups in each subscription

---
# inventory_everything.yml - All accessible subscriptions and resource groups
plugin: azure_cli

# Empty/omitted subscriptions = all accessible subscriptions
# Empty/omitted resource_groups = all resource groups
# This is the most comprehensive discovery

groups:
  production: "tags.Environment == 'production'"
  development: "tags.Environment == 'development'"

keyed_groups:
  - key: subscription_id
    prefix: sub
  - key: location
    prefix: loc
  - key: resource_group
    prefix: rg

---
# Usage examples:

# Test the inventory
# ansible-inventory -i inventory_azure_cli.yml --list

# Use with playbooks
# ansible-playbook -i inventory_azure_cli.yml site.yml

# Target specific groups
# ansible-playbook -i inventory_azure_cli.yml -l production site.yml
# ansible-playbook -i inventory_azure_cli.yml -l webservers site.yml
# ansible-playbook -i inventory_azure_cli.yml -l "rg_myapp_prod_rg" site.yml
