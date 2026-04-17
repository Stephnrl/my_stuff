az appservice ase list --query "[?kind=='ASEV3'].{Name:name, ResourceGroup:resourceGroup}" --output table
az appservice ase show --name <ase-name> --resource-group <rg> --query "{Name:name, DnsSuffix:properties.dnsSuffix, InternalIP:properties.networkingConfiguration.internalIpAddress}" --output table
az appservice ase list --query "[?kind=='ASEV3'].{Name:name, RG:resourceGroup, DnsSuffix:properties.dnsSuffix}" --output table
