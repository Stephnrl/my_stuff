# Create the OS disk separately with private access
resource "azurerm_managed_disk" "os_disk" {
  name                 = "${var.vm_name}-osdisk"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Premium_LRS"
  create_option        = "FromImage"
  image_reference_id   = data.azurerm_platform_image.ubuntu.id
  disk_size_gb         = 30
  
  # Set network access policy to deny public access
  network_access_policy         = "DenyAll"
  public_network_access_enabled = false
}

# Create managed data disks with private access
resource "azurerm_managed_disk" "data_disk" {
  count                = var.data_disk_count # e.g., 2 for two data disks
  name                 = "${var.vm_name}-datadisk-${count.index}"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 100
  
  # Set network access policy to deny public access
  network_access_policy         = "DenyAll"
  public_network_access_enabled = false
}

# Data source for the platform image
data "azurerm_platform_image" "ubuntu" {
  location  = azurerm_resource_group.main.location
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-focal"
  sku       = "20_04-lts-gen2"
}

# Create VM with both OS and data disks attached
resource "azurerm_virtual_machine" "main" {
  name                = var.vm_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  vm_size            = "Standard_DS2_v2"

  # Attach the OS disk
  storage_os_disk {
    name              = azurerm_managed_disk.os_disk.name
    managed_disk_id   = azurerm_managed_disk.os_disk.id
    create_option     = "Attach"
    os_type          = "Linux"
  }

  # Attach the data disks
  dynamic "storage_data_disk" {
    for_each = azurerm_managed_disk.data_disk
    content {
      name              = storage_data_disk.value.name
      managed_disk_id   = storage_data_disk.value.id
      create_option     = "Attach"
      lun              = storage_data_disk.key
      disk_size_gb     = storage_data_disk.value.disk_size_gb
    }
  }

  # Since we're attaching a pre-existing OS disk, we don't specify 
  # storage_image_reference here

  # Network interface
  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  # Rest of your VM configuration...
  
  depends_on = [
    azurerm_managed_disk.os_disk,
    azurerm_managed_disk.data_disk
  ]
}
