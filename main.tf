{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vmName": {
      "type": "string",
      "metadata": {
        "description": "Name of the virtual machine"
      }
    },
    "location": {
      "type": "string",
      "metadata": {
        "description": "Location for all resources"
      }
    },
    "vmSize": {
      "type": "string",
      "defaultValue": "Standard_D4s_v5",
      "metadata": {
        "description": "Size of the virtual machine"
      }
    },
    "adminUsername": {
      "type": "string",
      "metadata": {
        "description": "Admin username for the VM"
      }
    },
    "adminPassword": {
      "type": "securestring",
      "defaultValue": "",
      "metadata": {
        "description": "Admin password (if not using SSH)"
      }
    },
    "sshKey": {
      "type": "string",
      "defaultValue": "",
      "metadata": {
        "description": "SSH public key for authentication"
      }
    },
    "subnetId": {
      "type": "string",
      "metadata": {
        "description": "Resource ID of the subnet"
      }
    },
    "imageId": {
      "type": "string",
      "metadata": {
        "description": "Resource ID of the Compute Gallery Image Version"
      }
    },
    "osDiskName": {
      "type": "string",
      "metadata": {
        "description": "Name of the OS disk"
      }
    },
    "osDiskSizeGB": {
      "type": "int",
      "defaultValue": 128,
      "metadata": {
        "description": "Size of the OS disk in GB"
      }
    },
    "osDiskType": {
      "type": "string",
      "defaultValue": "Premium_LRS",
      "allowedValues": [
        "Standard_LRS",
        "Premium_LRS",
        "StandardSSD_LRS",
        "Premium_ZRS",
        "StandardSSD_ZRS"
      ],
      "metadata": {
        "description": "Storage account type for OS disk"
      }
    },
    "dataDisks": {
      "type": "array",
      "defaultValue": [],
      "metadata": {
        "description": "Array of data disk configurations"
      }
    },
    "enableAcceleratedNetworking": {
      "type": "bool",
      "defaultValue": true,
      "metadata": {
        "description": "Enable accelerated networking"
      }
    },
    "tags": {
      "type": "object",
      "defaultValue": {},
      "metadata": {
        "description": "Tags to apply to all resources"
      }
    },
    "usePublicIP": {
      "type": "bool",
      "defaultValue": false,
      "metadata": {
        "description": "Whether to create a public IP"
      }
    },
    "availabilityZone": {
      "type": "string",
      "defaultValue": "",
      "metadata": {
        "description": "Availability zone (1, 2, 3, or empty for no zone)"
      }
    }
  },
  "variables": {
    "nicName": "[concat(parameters('vmName'), '-nic')]",
    "publicIPName": "[concat(parameters('vmName'), '-pip')]",
    "useSSHAuthentication": "[not(empty(parameters('sshKey')))]",
    "linuxConfiguration": {
      "disablePasswordAuthentication": "[variables('useSSHAuthentication')]",
      "ssh": {
        "publicKeys": [
          {
            "path": "[concat('/home/', parameters('adminUsername'), '/.ssh/authorized_keys')]",
            "keyData": "[parameters('sshKey')]"
          }
        ]
      }
    },
    "zones": "[if(empty(parameters('availabilityZone')), json('null'), array(parameters('availabilityZone')))]"
  },
  "resources": [
    {
      "condition": "[parameters('usePublicIP')]",
      "type": "Microsoft.Network/publicIPAddresses",
      "apiVersion": "2023-05-01",
      "name": "[variables('publicIPName')]",
      "location": "[parameters('location')]",
      "zones": "[variables('zones')]",
      "sku": {
        "name": "Standard"
      },
      "properties": {
        "publicIPAllocationMethod": "Static"
      },
      "tags": "[parameters('tags')]"
    },
    {
      "type": "Microsoft.Network/networkInterfaces",
      "apiVersion": "2023-05-01",
      "name": "[variables('nicName')]",
      "location": "[parameters('location')]",
      "dependsOn": [
        "[resourceId('Microsoft.Network/publicIPAddresses', variables('publicIPName'))]"
      ],
      "properties": {
        "ipConfigurations": [
          {
            "name": "ipconfig1",
            "properties": {
              "privateIPAllocationMethod": "Dynamic",
              "publicIPAddress": "[if(parameters('usePublicIP'), json(concat('{\"id\": \"', resourceId('Microsoft.Network/publicIPAddresses', variables('publicIPName')), '\"}')), json('null'))]",
              "subnet": {
                "id": "[parameters('subnetId')]"
              }
            }
          }
        ],
        "enableAcceleratedNetworking": "[parameters('enableAcceleratedNetworking')]"
      },
      "tags": "[parameters('tags')]"
    },
    {
      "type": "Microsoft.Compute/disks",
      "apiVersion": "2023-04-02",
      "name": "[parameters('osDiskName')]",
      "location": "[parameters('location')]",
      "zones": "[variables('zones')]",
      "sku": {
        "name": "[parameters('osDiskType')]"
      },
      "properties": {
        "osType": "Linux",
        "hyperVGeneration": "V2",
        "creationData": {
          "createOption": "FromImage",
          "imageReference": {
            "id": "[parameters('imageId')]"
          }
        },
        "diskSizeGB": "[parameters('osDiskSizeGB')]",
        "networkAccessPolicy": "DenyAll",
        "publicNetworkAccess": "Disabled",
        "securityProfile": {
          "securityType": "TrustedLaunch"
        }
      },
      "tags": "[parameters('tags')]"
    },
    {
      "copy": {
        "name": "dataDiskCopy",
        "count": "[length(parameters('dataDisks'))]"
      },
      "type": "Microsoft.Compute/disks",
      "apiVersion": "2023-04-02",
      "name": "[concat(parameters('vmName'), '-datadisk-', parameters('dataDisks')[copyIndex()].name)]",
      "location": "[parameters('location')]",
      "zones": "[variables('zones')]",
      "sku": {
        "name": "[parameters('dataDisks')[copyIndex()].storageAccountType]"
      },
      "properties": {
        "creationData": {
          "createOption": "Empty"
        },
        "diskSizeGB": "[parameters('dataDisks')[copyIndex()].diskSizeGB]",
        "networkAccessPolicy": "DenyAll",
        "publicNetworkAccess": "Disabled"
      },
      "tags": "[parameters('tags')]"
    },
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2023-09-01",
      "name": "[parameters('vmName')]",
      "location": "[parameters('location')]",
      "zones": "[variables('zones')]",
      "dependsOn": [
        "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]",
        "[resourceId('Microsoft.Compute/disks', parameters('osDiskName'))]",
        "dataDiskCopy"
      ],
      "properties": {
        "hardwareProfile": {
          "vmSize": "[parameters('vmSize')]"
        },
        "storageProfile": {
          "imageReference": {
            "id": "[parameters('imageId')]"
          },
          "osDisk": {
            "osType": "Linux",
            "name": "[parameters('osDiskName')]",
            "createOption": "Attach",
            "managedDisk": {
              "id": "[resourceId('Microsoft.Compute/disks', parameters('osDiskName'))]"
            }
          },
          "copy": [
            {
              "name": "dataDisks",
              "count": "[length(parameters('dataDisks'))]",
              "input": {
                "lun": "[parameters('dataDisks')[copyIndex('dataDisks')].lun]",
                "name": "[concat(parameters('vmName'), '-datadisk-', parameters('dataDisks')[copyIndex('dataDisks')].name)]",
                "createOption": "Attach",
                "managedDisk": {
                  "id": "[resourceId('Microsoft.Compute/disks', concat(parameters('vmName'), '-datadisk-', parameters('dataDisks')[copyIndex('dataDisks')].name))]"
                }
              }
            }
          ]
        },
        "osProfile": {
          "computerName": "[parameters('vmName')]",
          "adminUsername": "[parameters('adminUsername')]",
          "adminPassword": "[if(variables('useSSHAuthentication'), json('null'), parameters('adminPassword'))]",
          "linuxConfiguration": "[if(variables('useSSHAuthentication'), variables('linuxConfiguration'), json('null'))]"
        },
        "networkProfile": {
          "networkInterfaces": [
            {
              "id": "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]"
            }
          ]
        },
        "securityProfile": {
          "uefiSettings": {
            "secureBootEnabled": true,
            "vTpmEnabled": true
          },
          "securityType": "TrustedLaunch"
        }
      },
      "tags": "[parameters('tags')]"
    }
  ],
  "outputs": {
    "vmId": {
      "type": "string",
      "value": "[resourceId('Microsoft.Compute/virtualMachines', parameters('vmName'))]"
    },
    "privateIpAddress": {
      "type": "string",
      "value": "[reference(resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))).ipConfigurations[0].properties.privateIPAddress]"
    },
    "publicIpAddress": {
      "condition": "[parameters('usePublicIP')]",
      "type": "string",
      "value": "[reference(resourceId('Microsoft.Network/publicIPAddresses', variables('publicIPName'))).ipAddress]"
    },
    "nicId": {
      "type": "string",
      "value": "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]"
    },
    "osDiskId": {
      "type": "string",
      "value": "[resourceId('Microsoft.Compute/disks', parameters('osDiskName'))]"
    }
  }
}
