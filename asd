# Variables
ASE_NAME="<ase-name>"
ILB_IP="10.174.21.11"
VNET_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet-name>"
ZONE_NAME="${ASE_NAME}.appserviceenvironment.us"

# Create the private DNS zone
az network private-dns zone create \
  --resource-group <dns-rg> \
  --name $ZONE_NAME

# Link it to the VNet
az network private-dns link vnet create \
  --resource-group <dns-rg> \
  --zone-name $ZONE_NAME \
  --name "${ASE_NAME}-link" \
  --virtual-network $VNET_ID \
  --registration-enabled false

# Wildcard record for all apps
az network private-dns record-set a add-record \
  --resource-group <dns-rg> \
  --zone-name $ZONE_NAME \
  --record-set-name "*" \
  --ipv4-address $ILB_IP

# @ record for the ASE root
az network private-dns record-set a add-record \
  --resource-group <dns-rg> \
  --zone-name $ZONE_NAME \
  --record-set-name "@" \
  --ipv4-address $ILB_IP

# SCM wildcard for Kudu access
az network private-dns record-set a add-record \
  --resource-group <dns-rg> \
  --zone-name $ZONE_NAME \
  --record-set-name "*.scm" \
  --ipv4-address $ILB_IP
