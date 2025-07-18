param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRegistry,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetRegistry,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "./images.json"
)

# Function to write timestamped log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Function to handle errors and continue processing
function Handle-Error {
    param([string]$Operation, [string]$Image)
    Write-Log "Failed to $Operation for image: $Image" "ERROR"
    Write-Log "Error: $($Error[0].Exception.Message)" "ERROR"
}

try {
    # Validate that az CLI is available
    if (!(Get-Command "az" -ErrorAction SilentlyContinue)) {
        throw "Azure CLI (az) is not installed or not in PATH"
    }

    # Validate that docker is available
    if (!(Get-Command "docker" -ErrorAction SilentlyContinue)) {
        throw "Docker is not installed or not in PATH"
    }

    Write-Log "Starting ACR image transfer process..."
    Write-Log "Source Registry: $SourceRegistry"
    Write-Log "Target Registry: $TargetRegistry"
    Write-Log "Config File: $ConfigFile"

    # Check if config file exists
    if (!(Test-Path $ConfigFile)) {
        throw "Configuration file not found: $ConfigFile"
    }

    # Parse JSON configuration
    Write-Log "Loading image configuration..."
    $imagesConfig = Get-Content $ConfigFile | ConvertFrom-Json

    if (!$imagesConfig.images -or $imagesConfig.images.Count -eq 0) {
        throw "No images found in configuration file"
    }

    Write-Log "Found $($imagesConfig.images.Count) image(s) to transfer"

    # Login to source ACR
    Write-Log "Logging into source registry: $SourceRegistry"
    az acr login --name $SourceRegistry
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to login to source registry: $SourceRegistry"
    }

    # Login to target ACR
    Write-Log "Logging into target registry: $TargetRegistry"
    az acr login --name $TargetRegistry
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to login to target registry: $TargetRegistry"
    }

    # Initialize counters
    $successCount = 0
    $failureCount = 0
    $totalImages = $imagesConfig.images.Count

    # Process each image
    foreach ($image in $imagesConfig.images) {
        $sourceImage = "$SourceRegistry.azurecr.io/$($image.target)"
        $targetImage = "$TargetRegistry.azurecr.io/$($image.target)"
        
        Write-Log "Processing image ($($successCount + $failureCount + 1)/$totalImages): $($image.target)"
        
        try {
            # Pull from source registry
            Write-Log "Pulling: $sourceImage"
            docker pull $sourceImage
            if ($LASTEXITCODE -ne 0) {
                throw "Docker pull failed"
            }

            # Tag for target registry
            Write-Log "Tagging: $sourceImage -> $targetImage"
            docker tag $sourceImage $targetImage
            if ($LASTEXITCODE -ne 0) {
                throw "Docker tag failed"
            }

            # Push to target registry
            Write-Log "Pushing: $targetImage"
            docker push $targetImage
            if ($LASTEXITCODE -ne 0) {
                throw "Docker push failed"
            }

            # Clean up local images to save space
            Write-Log "Cleaning up local images"
            docker rmi $sourceImage -f | Out-Null
            docker rmi $targetImage -f | Out-Null

            $successCount++
            Write-Log "Successfully transferred: $($image.target)" "SUCCESS"
        }
        catch {
            Handle-Error "transfer image" $image.target
            $failureCount++
        }
        
        Write-Host "" # Empty line for readability
    }

    # Final summary
    Write-Log "=== Transfer Summary ===" "INFO"
    Write-Log "Total images: $totalImages" "INFO"
    Write-Log "Successful: $successCount" "SUCCESS"
    Write-Log "Failed: $failureCount" $(if ($failureCount -gt 0) { "ERROR" } else { "INFO" })
    Write-Log "Transfer process completed" "INFO"

    if ($failureCount -gt 0) {
        exit 1
    }
}
catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
