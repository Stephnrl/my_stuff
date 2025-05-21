#!/bin/bash

# Script to create secured snapshots of all disks attached to an Azure VM
# Usage: ./snapshot-vm-disks.sh <resource-group> <vm-name> [snapshot-prefix]

# Check if required parameters are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <resource-group> <vm-name> [snapshot-prefix]"
    exit 1
fi

# Set variables
RESOURCE_GROUP=$1
VM_NAME=$2
SNAPSHOT_PREFIX=${3:-"snap"}
TIMESTAMP=$(date +%Y%m%d%H%M)
LOCATION=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query location -o tsv)

echo "Creating secured snapshots for VM '$VM_NAME' in resource group '$RESOURCE_GROUP'..."

# Get OS disk info
echo "Getting OS disk information..."
OS_DISK_ID=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query storageProfile.osDisk.managedDisk.id -o tsv)
OS_DISK_NAME=$(echo $OS_DISK_ID | awk -F/ '{print $NF}')

# Get encryption settings from the source disk (if available)
ENCRYPTION_TYPE=$(az disk show --ids $OS_DISK_ID --query encryption.type -o tsv 2>/dev/null)
ENCRYPTION_SET_ID=$(az disk show --ids $OS_DISK_ID --query encryption.diskEncryptionSetId -o tsv 2>/dev/null)

# Create snapshot of OS disk with encryption and private access
OS_SNAPSHOT_NAME="${SNAPSHOT_PREFIX}-${VM_NAME}-osdisk-${TIMESTAMP}"
echo "Creating secured snapshot of OS disk: $OS_SNAPSHOT_NAME"

SNAPSHOT_CMD="az snapshot create \
    --resource-group $RESOURCE_GROUP \
    --name $OS_SNAPSHOT_NAME \
    --source $OS_DISK_ID \
    --location $LOCATION \
    --network-access-policy AllowPrivateAccess \
    --public-network-access Disabled \
    --tags \"SourceVM=$VM_NAME\" \"SourceDisk=$OS_DISK_NAME\" \"DiskType=OS\" \"CreatedOn=$(date +%Y-%m-%d)\" \"Secured=true\""

# Add encryption parameters if the source disk is encrypted
if [ "$ENCRYPTION_TYPE" == "EncryptionAtRestWithPlatformAndCustomerKeys" ] || [ "$ENCRYPTION_TYPE" == "EncryptionAtRestWithCustomerKey" ]; then
    if [ -n "$ENCRYPTION_SET_ID" ]; then
        echo "Using encryption set from source disk: $ENCRYPTION_SET_ID"
        SNAPSHOT_CMD="$SNAPSHOT_CMD --encryption-type EncryptionAtRestWithCustomerKey --disk-encryption-set $ENCRYPTION_SET_ID"
    fi
else
    # Default to platform encryption if no custom encryption is used
    SNAPSHOT_CMD="$SNAPSHOT_CMD --encryption-type EncryptionAtRestWithPlatformKey"
fi

# Execute the snapshot creation command
eval $SNAPSHOT_CMD --output table

# Get data disks info
echo "Getting data disks information..."
DATA_DISK_IDS=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query storageProfile.dataDisks[].managedDisk.id -o tsv)

# Create snapshot of each data disk
if [ -n "$DATA_DISK_IDS" ]; then
    DISK_INDEX=0
    echo "$DATA_DISK_IDS" | while read -r DISK_ID; do
        if [ -n "$DISK_ID" ]; then
            DISK_INDEX=$((DISK_INDEX + 1))
            DISK_NAME=$(echo $DISK_ID | awk -F/ '{print $NF}')
            DATA_SNAPSHOT_NAME="${SNAPSHOT_PREFIX}-${VM_NAME}-datadisk${DISK_INDEX}-${TIMESTAMP}"
            
            # Get encryption settings from this data disk
            DISK_ENCRYPTION_TYPE=$(az disk show --ids $DISK_ID --query encryption.type -o tsv 2>/dev/null)
            DISK_ENCRYPTION_SET_ID=$(az disk show --ids $DISK_ID --query encryption.diskEncryptionSetId -o tsv 2>/dev/null)
            
            echo "Creating secured snapshot of data disk $DISK_INDEX: $DATA_SNAPSHOT_NAME"
            
            DATA_SNAPSHOT_CMD="az snapshot create \
                --resource-group $RESOURCE_GROUP \
                --name $DATA_SNAPSHOT_NAME \
                --source $DISK_ID \
                --location $LOCATION \
                --network-access-policy AllowPrivateAccess \
                --public-network-access Disabled \
                --tags \"SourceVM=$VM_NAME\" \"SourceDisk=$DISK_NAME\" \"DiskType=Data\" \"DiskIndex=$DISK_INDEX\" \"CreatedOn=$(date +%Y-%m-%d)\" \"Secured=true\""
            
            # Add encryption parameters if the source disk is encrypted
            if [ "$DISK_ENCRYPTION_TYPE" == "EncryptionAtRestWithPlatformAndCustomerKeys" ] || [ "$DISK_ENCRYPTION_TYPE" == "EncryptionAtRestWithCustomerKey" ]; then
                if [ -n "$DISK_ENCRYPTION_SET_ID" ]; then
                    echo "Using encryption set from data disk: $DISK_ENCRYPTION_SET_ID"
                    DATA_SNAPSHOT_CMD="$DATA_SNAPSHOT_CMD --encryption-type EncryptionAtRestWithCustomerKey --disk-encryption-set $DISK_ENCRYPTION_SET_ID"
                fi
            else
                # Default to platform encryption if no custom encryption is used
                DATA_SNAPSHOT_CMD="$DATA_SNAPSHOT_CMD --encryption-type EncryptionAtRestWithPlatformKey"
            fi
            
            # Execute the data disk snapshot creation command
            eval $DATA_SNAPSHOT_CMD --output table
        fi
    done
else
    echo "No data disks found for VM '$VM_NAME'"
fi

# Verify security settings of created snapshots
echo -e "\nVerifying security settings of created snapshots..."
SNAPSHOTS=$(az snapshot list --resource-group $RESOURCE_GROUP --query "[?tags.SourceVM=='$VM_NAME' && starts_with(name, '$SNAPSHOT_PREFIX')].[name]" -o tsv)

for SNAPSHOT in $SNAPSHOTS; do
    echo -e "\nSnapshot: $SNAPSHOT"
    az snapshot show --resource-group $RESOURCE_GROUP --name $SNAPSHOT --query "{Name:name, NetworkAccessPolicy:networkAccessPolicy, PublicNetworkAccess:publicNetworkAccess, EncryptionType:encryption.type}" -o table
done

echo -e "\nSecured snapshot creation completed!"
