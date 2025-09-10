# Run as Administrator - Check failed logons in the last hour
Get-WinEvent -FilterHashtable @{LogName='Security'; ID=4625; StartTime=(Get-Date).AddHours(-1)} | 
  Select-Object TimeCreated, 
    @{Name='User';Expression={$_.Properties[5].Value}}, 
    @{Name='Domain';Expression={$_.Properties[6].Value}},
    @{Name='SourceIP';Expression={$_.Properties[19].Value}},
    @{Name='LogonType';Expression={$_.Properties[10].Value}} | 
  Format-Table -AutoSize

# Check WinRM operational log for authentication issues
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WinRM/Operational'; ID=91,142,161} -MaxEvents 20 | 
  Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List

# Check WinRM service and configuration
Get-Service WinRM
winrm get winrm/config/service
winrm enumerate winrm/config/listener

# If it's a local account
Get-LocalUser | Where-Object {$_.Name -like "*your-github-user*"} | 
  Select Name, Enabled, LastLogon, PasswordExpired

# If it's a domain account, replace "YourDomain" and "YourUser"
Get-ADUser -Filter "Name -like '*your-github-user*'" -Properties LastLogonDate, LockedOut, PasswordExpired
