# Set your environment variables
$BITWARDEN_URL = "https://your-bitwarden-url.com"
$ADMIN_CLIENT_ID = "your-admin-client-id"
$ADMIN_CLIENT_SECRET = "your-admin-client-secret"

# First, get an admin access token
$tokenBody = @{
    grant_type = "client_credentials"
    scope = "api"
    client_id = $ADMIN_CLIENT_ID
    client_secret = $ADMIN_CLIENT_SECRET
}

$tokenResponse = Invoke-RestMethod -Uri "$BITWARDEN_URL/identity/connect/token" `
    -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $tokenBody

$ACCESS_TOKEN = $tokenResponse.access_token
Write-Host "Access token obtained: $($ACCESS_TOKEN.Substring(0,20))..."

# List users to get their IDs
$headers = @{
    "Authorization" = "Bearer $ACCESS_TOKEN"
    "Content-Type" = "application/json"
}

$users = Invoke-RestMethod -Uri "$BITWARDEN_URL/api/users" `
    -Method Get `
    -Headers $headers

Write-Host "Found $($users.Count) users:"
$users | Select-Object Id, Email, CreationDate | Format-Table

# Delete specific users by ID
$USER_ID = "12345678-1234-1234-1234-123456789012"  # Replace with actual user ID

$deleteResponse = Invoke-RestMethod -Uri "$BITWARDEN_URL/api/users/$USER_ID" `
    -Method Delete `
    -Headers $headers

Write-Host "User $USER_ID deleted successfully"
