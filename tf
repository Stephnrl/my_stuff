# Assuming $startDateTime and $endDateTime are strings like "2023-10-25 14:30:00"

# Define the style flags (combining them with -bor)
$style = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal

# Fixed: Changed ;; to ::, added missing ), changed yyy to yyyy
$startTimeUtc = [DateTime]::ParseExact($startDateTime, 'yyyy-MM-dd HH:mm:ss', $null, $style)
$endTimeUtc   = [DateTime]::ParseExact($endDateTime, 'yyyy-MM-dd HH:mm:ss', $null, $style)

$currentTimeUtc = (Get-Date).ToUniversalTime()

$isValid = (
      $changeAllowed -eq $true -and 
      $currentTimeUtc -gt $startTimeUtc -and 
      $currentTimeUtc -lt $endTimeUtc
)
