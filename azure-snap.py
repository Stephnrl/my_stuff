#!/usr/bin/env python3

import os
import sys
import argparse
import datetime
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.resource import ResourceManagementClient

def create_secured_snapshots(resource_group, vm_name, snapshot_prefix=None):
    """Create secured snapshots of all disks attached to a VM"""
    
    # Initialize credentials and clients
    credential = DefaultAzureCredential()
    compute_client = ComputeManagementClient(credential, subscription_id)
    resource_client = ResourceManagementClient(credential, subscription_id)
    
    # Get VM details
    print(f"Getting details for VM '{vm_name}' in resource group '{resource_group}'...")
    vm = compute_client.virtual_machines.get(resource_group, vm_name)
    location = vm.location
    
    # Set snapshot prefix
    if not snapshot_prefix:
        snapshot_prefix = "snap"
    timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M")
    
    # Get OS disk info
    print("Getting OS disk information...")
    os_disk_id = vm.storage_profile.os_disk.managed_disk.id
    os_disk_name = os_disk_id.split('/')[-1]
    
    # Get OS disk encryption details
    os_disk = compute_client.disks.get(resource_group, os_disk_name)
    encryption_type = os_disk.encryption.type if os_disk.encryption else None
    encryption_set_id = os_disk.encryption.disk_encryption_set.id if os_disk.encryption and hasattr(os_disk.encryption, 'disk_encryption_set') else None
    
    # Create OS disk snapshot
    os_snapshot_name = f"{snapshot_prefix}-{vm_name}-osdisk-{timestamp}"
    print(f"Creating secured snapshot of OS disk: {os_snapshot_name}")
    
    snapshot_creation = {
        'location': location,
        'creation_data': {
            'create_option': 'Copy',
            'source_resource_id': os_disk_id
        },
        'network_access_policy': 'AllowPrivate',
        'public_network_access': 'Disabled',
        'tags': {
            'SourceVM': vm_name,
            'SourceDisk': os_disk_name,
            'DiskType': 'OS',
            'CreatedOn': datetime.datetime.now().strftime("%Y-%m-%d"),
            'Secured': 'true'
        }
    }
    
    # Add encryption settings
    if encryption_type in ['EncryptionAtRestWithPlatformAndCustomerKeys', 'EncryptionAtRestWithCustomerKey'] and encryption_set_id:
        print(f"Using encryption set from source disk: {encryption_set_id}")
        snapshot_creation['encryption'] = {
            'type': 'EncryptionAtRestWithCustomerKey',
            'disk_encryption_set_id': encryption_set_id
        }
    else:
        snapshot_creation['encryption'] = {
            'type': 'EncryptionAtRestWithPlatformKey'
        }
    
    # Create the OS disk snapshot
    async_snapshot_creation = compute_client.snapshots.begin_create_or_update(
        resource_group,
        os_snapshot_name,
        snapshot_creation
    )
    os_snapshot = async_snapshot_creation.result()
    print(f"OS disk snapshot created: {os_snapshot.name}")
    
    # Get data disks info
    data_disks = vm.storage_profile.data_disks
    if data_disks:
        for disk_index, disk in enumerate(data_disks, 1):
            data_disk_id = disk.managed_disk.id
            data_disk_name = data_disk_id.split('/')[-1]
            
            # Get data disk encryption details
            data_disk = compute_client.disks.get(resource_group, data_disk_name)
            data_encryption_type = data_disk.encryption.type if data_disk.encryption else None
            data_encryption_set_id = data_disk.encryption.disk_encryption_set.id if data_disk.encryption and hasattr(data_disk.encryption, 'disk_encryption_set') else None
            
            # Create data disk snapshot
            data_snapshot_name = f"{snapshot_prefix}-{vm_name}-datadisk{disk_index}-{timestamp}"
            print(f"Creating secured snapshot of data disk {disk_index}: {data_snapshot_name}")
            
            data_snapshot_creation = {
                'location': location,
                'creation_data': {
                    'create_option': 'Copy',
                    'source_resource_id': data_disk_id
                },
                'network_access_policy': 'AllowPrivate',
                'public_network_access': 'Disabled',
                'tags': {
                    'SourceVM': vm_name,
                    'SourceDisk': data_disk_name,
                    'DiskType': 'Data',
                    'DiskIndex': str(disk_index),
                    'CreatedOn': datetime.datetime.now().strftime("%Y-%m-%d"),
                    'Secured': 'true'
                }
            }
            
            # Add encryption settings for data disk
            if data_encryption_type in ['EncryptionAtRestWithPlatformAndCustomerKeys', 'EncryptionAtRestWithCustomerKey'] and data_encryption_set_id:
                print(f"Using encryption set from data disk: {data_encryption_set_id}")
                data_snapshot_creation['encryption'] = {
                    'type': 'EncryptionAtRestWithCustomerKey',
                    'disk_encryption_set_id': data_encryption_set_id
                }
            else:
                data_snapshot_creation['encryption'] = {
                    'type': 'EncryptionAtRestWithPlatformKey'
                }
            
            # Create the data disk snapshot
            async_data_snapshot_creation = compute_client.snapshots.begin_create_or_update(
                resource_group,
                data_snapshot_name,
                data_snapshot_creation
            )
            data_snapshot = async_data_snapshot_creation.result()
            print(f"Data disk snapshot created: {data_snapshot.name}")
    else:
        print(f"No data disks found for VM '{vm_name}'")
    
    # Verify security settings
    print("\nVerifying security settings of created snapshots...")
    snapshots = compute_client.snapshots.list_by_resource_group(resource_group)
    created_snapshots = [s for s in snapshots if 
                         s.tags and 
                         s.tags.get('SourceVM') == vm_name and 
                         s.name.startswith(snapshot_prefix)]
    
    for snapshot in created_snapshots:
        print(f"\nSnapshot: {snapshot.name}")
        print(f"  Network Access Policy: {snapshot.network_access_policy}")
        print(f"  Public Network Access: {snapshot.public_network_access}")
        print(f"  Encryption Type: {snapshot.encryption.type if snapshot.encryption else 'None'}")
    
    print("\nSecured snapshot creation completed!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Create secured snapshots of all disks attached to an Azure VM')
    parser.add_argument('resource_group', help='Resource group of the VM')
    parser.add_argument('vm_name', help='Name of the VM')
    parser.add_argument('--snapshot-prefix', help='Prefix for snapshot names (default: snap)')
    parser.add_argument('--subscription', help='Azure subscription ID')
    
    args = parser.parse_args()
    
    # Get subscription ID from args or environment variable
    subscription_id = args.subscription or os.environ.get('AZURE_SUBSCRIPTION_ID')
    if not subscription_id:
        print("Error: Subscription ID must be provided via --subscription or AZURE_SUBSCRIPTION_ID environment variable")
        sys.exit(1)
    
    create_secured_snapshots(args.resource_group, args.vm_name, args.snapshot_prefix)
