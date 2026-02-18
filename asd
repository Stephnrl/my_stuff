That error message is Az PowerShell explicitly saying "I have no context" — so the session is definitely not carrying over into your composite action.
The most likely cause is that AzContextAutosave isn't loading the saved context automatically in the new pwsh process that the composite action spins up. You need to explicitly import it.
Fix — add this as the first step in your composite action:
yaml- shell: pwsh
  run: |
    $contextPath = Join-Path $env:USERPROFILE ".Azure\AzureRmContext.json"
    if (Test-Path $contextPath) {
      Import-AzContext -Path $contextPath
      Write-Host "Az context imported successfully"
    } else {
      Write-Error "No saved Az context found at $contextPath"
    }
On Linux runners the path is different:
yaml- shell: pwsh
  run: |
    $contextPath = Join-Path $env:HOME ".Azure/AzureRmContext.json"
    Import-AzContext -Path $contextPath
Or handle both in one step:
yaml- shell: pwsh
  run: |
    $base = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    $contextPath = Join-Path $base ".Azure/AzureRmContext.json"
    if (Test-Path $contextPath) {
      Import-AzContext -Path $contextPath
      Write-Host "Logged in as: $((Get-AzContext).Account)"
    } else {
      Write-Error "Context file not found: $contextPath"
    }
Why this happens
azure/login@v2 calls Save-AzContext which writes the context to disk. But each new pwsh process in a composite action step doesn't automatically call Import-AzContext — it only works automatically if Enable-AzContextAutosave was set in the same process. Since composite action steps each spin up a fresh pwsh process, you need to explicitly import it.
