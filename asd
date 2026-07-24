$cs = Get-CimInstance Win32_ComputerSystem
[PSCustomObject]@{
  DomainJoined  = $cs.PartOfDomain
  DnsDomain     = $cs.Domain
  KerberosRealm = $cs.Domain.ToUpper()
  NetBiosDomain = $env:USERDOMAIN
  ComputerName  = $cs.Name
  FQDN          = "$($cs.Name).$($cs.Domain)"
} | Format-List
