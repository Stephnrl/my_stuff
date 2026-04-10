# Check by file — grab the thumbprint from the import output, then:
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*Zscaler*" } | Format-List Subject, Thumbprint, NotAfter
