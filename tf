# MyActionModule.psm1

# 1. Define the paths
$subFolders = @('Private', 'Public')

# 2. Loop through folders in order (Private first, then Public)
foreach ($folder in $subFolders) {
    $path = Join-Path -Path $PSScriptRoot -ChildPath $folder
    
    if (Test-Path -Path $path) {
        $scripts = Get-ChildItem -Path $path -Filter *.ps1
        foreach ($script in $scripts) {
            Write-Debug "Dot-sourcing: $($script.FullName)"
            . $script.FullName
        }
    }
}

# 3. Final Step: Export ONLY what is in the Public folder
$publicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | Select-Object -ExpandProperty BaseName
Export-ModuleMember -Function $publicFunctions
