#!/bin/bash

# Azure Dynamic Inventory Script for GitHub VMs
# Requires: Azure CLI (az) to be installed and logged in
# Usage: 
#   ./azure_github_inventory.sh --list    (for Ansible)
#   ./azure_github_inventory.sh --host <hostname>  (for Ansible)
#   ./azure_github_inventory.sh --save    (save to file)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages (only when not in --list mode for Ansible)
log() {
    if [ "$1" != "--list" ]; then
        echo -e "${GREEN}[INFO]${NC} $1" >&2
    fi
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    if [ "$1" != "--list" ]; then
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    fi
}

# Handle Ansible dynamic inventory arguments
case "$1" in
    --list)
        # Continue with inventory generation
        ;;
    --host)
        if [ -z "$2" ]; then
            error "Host name required for --host option"
            exit 1
        fi
        # For --host, we'll return empty JSON as we include all host vars in --list
        echo "{}"
        exit 0
        ;;
    --save)
        # Continue with inventory generation and save
        ;;
    *)
        echo "Usage: $0 [--list|--host <hostname>|--save]"
        echo "  --list: Return full inventory (for Ansible)"
        echo "  --host: Return host variables (for Ansible)"
        echo "  --save: Generate inventory and save to file"
        exit 1
        ;;
esac

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI (az) is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

log "Fetching Azure account information..."
ACCOUNT_INFO=$(az account show --output json)
SUBSCRIPTION_ID=$(echo "$ACCOUNT_INFO" | jq -r '.id')
SUBSCRIPTION_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.name')

log "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Initialize inventory structure
INVENTORY='{
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
}'

log "Searching for VMs with 'github' in name..."

# Get all VMs with 'github' in name (case insensitive)
VMS=$(az vm list --show-details --output json | jq -r '.[] | select(.name | test("github"; "i"))')

if [ -z "$VMS" ] || [ "$VMS" = "null" ]; then
    warn "No VMs found with 'github' in the name."
    echo "$INVENTORY" | jq .
    exit 0
fi

# Process each VM
echo "$VMS" | jq -c '.' | while read -r vm; do
    VM_NAME=$(echo "$vm" | jq -r '.name')
    VM_ID=$(echo "$vm" | jq -r '.id')
    RESOURCE_GROUP=$(echo "$vm" | jq -r '.resourceGroup')
    LOCATION=$(echo "$vm" | jq -r '.location')
    POWER_STATE=$(echo "$vm" | jq -r '.powerState')
    
    log "Processing VM: $VM_NAME"
    
    # Get private IP address
    PRIVATE_IP=$(echo "$vm" | jq -r '.privateIps // empty | if type == "array" then .[0] else . end')
    
    if [ -z "$PRIVATE_IP" ] || [ "$PRIVATE_IP" = "null" ]; then
        warn "No private IP found for $VM_NAME, skipping..."
        continue
    fi
    
    # Get detailed VM info to check image publisher
    VM_DETAILS=$(az vm show --ids "$VM_ID" --output json)
    IMAGE_PUBLISHER=$(echo "$VM_DETAILS" | jq -r '.storageProfile.imageReference.publisher // "unknown"')
    IMAGE_OFFER=$(echo "$VM_DETAILS" | jq -r '.storageProfile.imageReference.offer // "unknown"')
    IMAGE_SKU=$(echo "$VM_DETAILS" | jq -r '.storageProfile.imageReference.sku // "unknown"')
    VM_SIZE=$(echo "$VM_DETAILS" | jq -r '.hardwareProfile.vmSize')
    
    # Determine group based on image publisher
    if [ "$IMAGE_PUBLISHER" = "GitHub" ]; then
        GROUP="github_enterprise"
        log "  → Adding to github_enterprise group (Publisher: $IMAGE_PUBLISHER)"
    else
        GROUP="github_backup"
        log "  → Adding to github_backup group (Publisher: $IMAGE_PUBLISHER)"
    fi
    
    # Create host variables
    HOST_VARS=$(jq -n \
        --arg vm_name "$VM_NAME" \
        --arg vm_id "$VM_ID" \
        --arg resource_group "$RESOURCE_GROUP" \
        --arg location "$LOCATION" \
        --arg power_state "$POWER_STATE" \
        --arg private_ip "$PRIVATE_IP" \
        --arg image_publisher "$IMAGE_PUBLISHER" \
        --arg image_offer "$IMAGE_OFFER" \
        --arg image_sku "$IMAGE_SKU" \
        --arg vm_size "$VM_SIZE" \
        '{
            ansible_host: $private_ip,
            ansible_user: "azureuser",
            vm_name: $vm_name,
            vm_id: $vm_id,
            resource_group: $resource_group,
            location: $location,
            power_state: $power_state,
            private_ip: $private_ip,
            image_publisher: $image_publisher,
            image_offer: $image_offer,
            image_sku: $image_sku,
            vm_size: $vm_size
        }')
    
    # Update inventory using temporary file approach
    TEMP_FILE=$(mktemp)
    echo "$INVENTORY" | jq \
        --arg group "$GROUP" \
        --arg vm_name "$VM_NAME" \
        --arg private_ip "$PRIVATE_IP" \
        --argjson host_vars "$HOST_VARS" \
        '.[$group].hosts[$vm_name] = $private_ip | ._meta.hostvars[$vm_name] = $host_vars' > "$TEMP_FILE"
    
    INVENTORY=$(cat "$TEMP_FILE")
    rm "$TEMP_FILE"
    
done

# Output final inventory
if [ "$COMMAND" != "--list" ]; then
    log "Inventory generation complete!"
fi

echo "$INVENTORY" | jq .

# Optional: Save to file
if [ "$COMMAND" = "--save" ]; then
    OUTPUT_FILE="azure_github_inventory.json"
    echo "$INVENTORY" | jq . > "$OUTPUT_FILE"
    log "Inventory saved to $OUTPUT_FILE"
fi
