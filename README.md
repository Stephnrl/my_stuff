# Adding Zscaler Certificate to Windows for Azure CLI

## Exporting the Zscaler Certificate from Chrome

1. Export the Zscaler root certificate from Chrome:
   * Click on the padlock icon in the address bar
   * Select "Connection is secure" or similar text
   * Click on "Certificate"
   * Go to the "Certification Path" or "Certificate Path" tab
   * Select the root certificate (typically at the top of the chain, usually named "Zscaler" or similar)
   * Click on "View Certificate"
   * Go to the "Details" tab
   * Click "Copy to File..." button
   * Follow the Certificate Export Wizard
   * Choose "DER encoded binary X.509 (.CER)" format
   * Save the file to a location you can easily access

## Installing the Certificate in Windows

2. Install the certificate in Windows:
   * Double-click the exported .cer file
   * Click "Install Certificate"
   * Select "Local Machine" (requires admin) or "Current User"
   * Choose "Place all certificates in the following store"
   * Click "Browse" and select "Trusted Root Certification Authorities"
   * Click "Next" and then "Finish"

## Configuring Azure CLI

3. Configure Azure CLI to use the system certificate store:

```powershell
$env:NODE_EXTRA_CA_CERTS="C:\path\to\your\zscaler-cert.cer"
```

4. For a permanent solution, set a system environment variable:
   * Press Windows key + R
   * Type "sysdm.cpl" and press Enter
   * Go to the "Advanced" tab
   * Click "Environment Variables"
   * Under "System variables" click "New"
   * Variable name: NODE_EXTRA_CA_CERTS
   * Variable value: path to your saved certificate

5. Restart your command prompt or PowerShell after making these changes.

## Verifying It's Working

To verify the environment variable is working correctly:

1. Check if the environment variable is set correctly:
```powershell
echo $env:NODE_EXTRA_CA_CERTS
```

2. Test Azure CLI with a simple command:
```powershell
az login
# Or any other basic command like
az account list
```

3. Run Azure CLI with verbose logging:
```powershell
az --debug login
```

4. Verify the certificate is in the Windows certificate store:
   * Press Windows key + R
   * Type "certmgr.msc" and press Enter
   * Navigate to "Trusted Root Certification Authorities" > "Certificates"
   * Look for your Zscaler certificate in the list

If you still encounter certificate issues, you might also need to set:
```powershell
$env:AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=0
$env:ADAL_PYTHON_SSL_NO_VERIFY=0
```
