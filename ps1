# ============================================================================
# PowerShell 7 Profile - Linux/Bash Compatibility Layer
# ============================================================================
# Installation:
#   1. Run: $PROFILE to find your profile path
#   2. Run: New-Item -Path $PROFILE -ItemType File -Force (if it doesn't exist)
#   3. Copy this content into that file
#   4. Restart PowerShell or run: . $PROFILE
# ============================================================================

# ----------------------------------------------------------------------------
# DIRECTORY NAVIGATION
# ----------------------------------------------------------------------------

# cd shortcuts
function .. { Set-Location .. }
function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }
function ..... { Set-Location ../../../.. }

# cd - (go to previous directory)
$global:LastLocation = $null
function cd {
    param([string]$Path = $HOME)
    
    if ($Path -eq '-') {
        if ($global:LastLocation) {
            $temp = $PWD.Path
            Set-Location $global:LastLocation
            $global:LastLocation = $temp
        }
    } else {
        $global:LastLocation = $PWD.Path
        Set-Location $Path
    }
}

# pwd is already aliased, but let's make sure
Set-Alias -Name pwd -Value Get-Location -Option AllScope

# pushd/popd (already exist in PowerShell)
Set-Alias -Name pushd -Value Push-Location -Option AllScope
Set-Alias -Name popd -Value Pop-Location -Option AllScope

# ----------------------------------------------------------------------------
# LISTING FILES (ls variants)
# ----------------------------------------------------------------------------

# Remove default ls alias to replace with our function
Remove-Alias -Name ls -Force -ErrorAction SilentlyContinue

function ls {
    param(
        [switch]$a,
        [switch]$l,
        [switch]$h,
        [switch]$la,
        [switch]$al,
        [switch]$lah,
        [switch]$lh,
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Path = "."
    )
    
    $showHidden = $a -or $la -or $al -or $lah
    $longFormat = $l -or $la -or $al -or $lah -or $lh
    
    $items = Get-ChildItem -Path $Path -Force:$showHidden
    
    if ($longFormat) {
        $items | Format-Table -AutoSize Mode, LastWriteTime, Length, Name
    } else {
        $items | Format-Wide -AutoSize Name
    }
}

function ll { Get-ChildItem -Force @args | Format-Table -AutoSize Mode, LastWriteTime, Length, Name }
function la { Get-ChildItem -Force @args }
function l { Get-ChildItem @args }
function lsa { Get-ChildItem -Force @args }

# tree (if not installed, use this basic version)
if (-not (Get-Command tree -ErrorAction SilentlyContinue)) {
    function tree {
        param([string]$Path = ".", [int]$Depth = 2)
        Get-ChildItem -Path $Path -Recurse -Depth $Depth | 
            ForEach-Object { 
                $indent = "  " * ($_.FullName.Split([IO.Path]::DirectorySeparatorChar).Count - $Path.Split([IO.Path]::DirectorySeparatorChar).Count)
                "$indent$($_.Name)"
            }
    }
}

# ----------------------------------------------------------------------------
# FILE OPERATIONS
# ----------------------------------------------------------------------------

# Remove existing aliases to replace with functions
Remove-Alias -Name cp -Force -ErrorAction SilentlyContinue
Remove-Alias -Name mv -Force -ErrorAction SilentlyContinue
Remove-Alias -Name rm -Force -ErrorAction SilentlyContinue

# cp with common flags
function cp {
    param(
        [switch]$r,
        [switch]$R,
        [switch]$f,
        [switch]$v,
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Paths
    )
    
    $recurse = $r -or $R
    $source = $Paths[0..($Paths.Count-2)]
    $dest = $Paths[-1]
    
    Copy-Item -Path $source -Destination $dest -Recurse:$recurse -Force:$f -Verbose:$v
}

# mv
function mv {
    param(
        [switch]$f,
        [switch]$v,
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Paths
    )
    
    $source = $Paths[0..($Paths.Count-2)]
    $dest = $Paths[-1]
    
    Move-Item -Path $source -Destination $dest -Force:$f -Verbose:$v
}

# rm with common flags
function rm {
    param(
        [switch]$r,
        [switch]$R,
        [switch]$f,
        [switch]$rf,
        [switch]$fr,
        [switch]$v,
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Paths
    )
    
    $recurse = $r -or $R -or $rf -or $fr
    $force = $f -or $rf -or $fr
    
    Remove-Item -Path $Paths -Recurse:$recurse -Force:$force -Verbose:$v
}

# touch - create file or update timestamp
function touch {
    param([Parameter(Mandatory)][string[]]$Paths)
    
    foreach ($Path in $Paths) {
        if (Test-Path $Path) {
            (Get-Item $Path).LastWriteTime = Get-Date
        } else {
            New-Item -ItemType File -Path $Path -Force | Out-Null
        }
    }
}

# mkdir -p (create parent directories)
function mkdirp {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force
}
Set-Alias -Name 'mkdir' -Value mkdirp -Option AllScope -Force

# ln (symlinks)
function ln {
    param(
        [switch]$s,
        [switch]$f,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Link
    )
    
    if ($f -and (Test-Path $Link)) {
        Remove-Item $Link -Force
    }
    
    if ($s) {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target
    } else {
        New-Item -ItemType HardLink -Path $Link -Target $Target
    }
}

# chmod (basic implementation)
function chmod {
    param(
        [string]$Mode,
        [string[]]$Path
    )
    
    Write-Warning "chmod has limited support on Windows. Use icacls for full ACL control."
    
    foreach ($p in $Path) {
        $item = Get-Item $p
        if ($Mode -match '\+x') {
            # Can't truly make executable, but can remove readonly
            $item.IsReadOnly = $false
        }
        if ($Mode -match '\-w' -or $Mode -eq '444') {
            $item.IsReadOnly = $true
        }
        if ($Mode -match '\+w' -or $Mode -eq '644' -or $Mode -eq '755') {
            $item.IsReadOnly = $false
        }
    }
}

# chown (placeholder - requires icacls on Windows)
function chown {
    param([string]$Owner, [string[]]$Path)
    Write-Warning "chown is not directly supported. Use: icacls `$Path /setowner `$Owner"
}

# ----------------------------------------------------------------------------
# FILE VIEWING & TEXT PROCESSING
# ----------------------------------------------------------------------------

# cat (Get-Content is already aliased, but add number lines option)
Remove-Alias -Name cat -Force -ErrorAction SilentlyContinue
function cat {
    param(
        [switch]$n,  # number lines
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Paths
    )
    
    foreach ($Path in $Paths) {
        if ($n) {
            $lineNum = 1
            Get-Content $Path | ForEach-Object { 
                "{0,6}  {1}" -f $lineNum++, $_ 
            }
        } else {
            Get-Content $Path
        }
    }
}

# head
function head {
    param(
        [int]$n = 10,
        [Parameter(ValueFromPipeline, ValueFromRemainingArguments)]
        [object]$InputObject
    )
    
    begin { $count = 0 }
    process {
        if ($InputObject -is [string] -and (Test-Path $InputObject)) {
            Get-Content $InputObject -Head $n
        } else {
            if ($count -lt $n) {
                $InputObject
                $count++
            }
        }
    }
}

# tail
function tail {
    param(
        [int]$n = 10,
        [switch]$f,  # follow
        [Parameter(ValueFromRemainingArguments)]
        [string]$Path
    )
    
    if ($f) {
        Get-Content $Path -Tail $n -Wait
    } else {
        Get-Content $Path -Tail $n
    }
}

# less/more
function less { 
    param([string]$Path)
    if ($Path) {
        Get-Content $Path | Out-Host -Paging
    } else {
        $input | Out-Host -Paging
    }
}
Set-Alias -Name more -Value less -Option AllScope -Force

# wc (word count)
function wc {
    param(
        [switch]$l,  # lines
        [switch]$w,  # words
        [switch]$c,  # bytes/chars
        [Parameter(ValueFromPipeline, ValueFromRemainingArguments)]
        [object]$InputObject
    )
    
    begin { 
        $lines = 0; $words = 0; $chars = 0 
        $fromPipeline = $false
    }
    process {
        if ($InputObject -is [string] -and (Test-Path $InputObject -ErrorAction SilentlyContinue)) {
            $content = Get-Content $InputObject -Raw
        } else {
            $content = $InputObject
            $fromPipeline = $true
        }
        
        $lines += ($content | Measure-Object -Line).Lines
        $words += ($content -split '\s+' | Where-Object { $_ }).Count
        $chars += $content.Length
    }
    end {
        if ($l -and -not $w -and -not $c) { $lines }
        elseif ($w -and -not $l -and -not $c) { $words }
        elseif ($c -and -not $l -and -not $w) { $chars }
        else { "{0,8} {1,8} {2,8}" -f $lines, $words, $chars }
    }
}

# grep
function grep {
    param(
        [switch]$i,  # case insensitive
        [switch]$v,  # invert match
        [switch]$n,  # line numbers
        [switch]$r,  # recursive
        [switch]$l,  # files with matches only
        [switch]$c,  # count only
        [string]$Pattern,
        [Parameter(ValueFromPipeline, ValueFromRemainingArguments)]
        [object]$InputObject
    )
    
    begin {
        $selectParams = @{ Pattern = $Pattern }
        if ($i) { $selectParams.CaseSensitive = $false } else { $selectParams.CaseSensitive = $true }
        if ($n) { $selectParams.AllMatches = $true }
    }
    process {
        $result = if ($InputObject -is [string] -and (Test-Path $InputObject -ErrorAction SilentlyContinue)) {
            if ($r -and (Test-Path $InputObject -PathType Container)) {
                Get-ChildItem $InputObject -Recurse -File | Select-String @selectParams
            } else {
                Select-String -Path $InputObject @selectParams
            }
        } else {
            $InputObject | Select-String @selectParams
        }
        
        if ($v) {
            $result = $result | Where-Object { -not $_.Matches }
        }
        
        if ($l) {
            $result | Select-Object -ExpandProperty Path -Unique
        } elseif ($c) {
            $result | Group-Object Path | Select-Object Name, Count
        } else {
            $result
        }
    }
}

# sed (basic implementation)
function sed {
    param(
        [switch]$i,  # in-place
        [string]$Expression,
        [Parameter(ValueFromPipeline, ValueFromRemainingArguments)]
        [object]$InputObject
    )
    
    process {
        # Parse s/pattern/replacement/flags format
        if ($Expression -match '^s/(.+)/(.*)/(g)?$') {
            $pattern = $Matches[1]
            $replacement = $Matches[2]
            $global = $Matches[3] -eq 'g'
            
            if ($InputObject -is [string] -and (Test-Path $InputObject -ErrorAction SilentlyContinue)) {
                $content = Get-Content $InputObject
                $newContent = if ($global) {
                    $content -replace $pattern, $replacement
                } else {
                    $content | ForEach-Object { 
                        if ($_ -match $pattern) {
                            $_ -replace $pattern, $replacement
                        } else { $_ }
                    }
                }
                
                if ($i) {
                    $newContent | Set-Content $InputObject
                } else {
                    $newContent
                }
            } else {
                if ($global) {
                    $InputObject -replace $pattern, $replacement
                } else {
                    $InputObject -replace $pattern, $replacement
                }
            }
        }
    }
}

# awk (very basic - use for simple field extraction)
function awk {
    param(
        [string]$F = '\s+',  # field separator
        [string]$Pattern,
        [Parameter(ValueFromPipeline)]
        [string]$InputObject
    )
    
    process {
        $fields = $InputObject -split $F
        
        # Handle print $1, $2, etc.
        if ($Pattern -match '^\{print\s+(.+)\}$') {
            $printFields = $Matches[1] -split '[,\s]+'
            $output = foreach ($pf in $printFields) {
                if ($pf -match '^\$(\d+)$') {
                    $idx = [int]$Matches[1]
                    if ($idx -eq 0) { $InputObject }
                    else { $fields[$idx - 1] }
                } else {
                    $pf -replace '"', ''
                }
            }
            $output -join ' '
        } else {
            $fields
        }
    }
}

# cut
function cut {
    param(
        [string]$d = "`t",  # delimiter
        [string]$f,         # fields
        [Parameter(ValueFromPipeline)]
        [string]$InputObject
    )
    
    process {
        $fields = $InputObject -split [regex]::Escape($d)
        $indices = $f -split ',' | ForEach-Object {
            if ($_ -match '(\d+)-(\d+)') {
                [int]$Matches[1]..[int]$Matches[2]
            } elseif ($_ -match '(\d+)-$') {
                [int]$Matches[1]..($fields.Count)
            } else {
                [int]$_
            }
        }
        ($indices | ForEach-Object { $fields[$_ - 1] }) -join $d
    }
}

# sort (enhance the default)
Remove-Alias -Name sort -Force -ErrorAction SilentlyContinue
function sort {
    param(
        [switch]$r,  # reverse
        [switch]$n,  # numeric
        [switch]$u,  # unique
        [Parameter(ValueFromPipeline)]
        [object]$InputObject
    )
    
    begin { $items = @() }
    process { $items += $InputObject }
    end {
        $result = if ($n) {
            $items | Sort-Object { [double]$_ } -Descending:$r
        } else {
            $items | Sort-Object -Descending:$r
        }
        
        if ($u) { $result | Get-Unique }
        else { $result }
    }
}

# uniq
function uniq {
    param(
        [switch]$c,  # count
        [switch]$d,  # only duplicates
        [switch]$u,  # only unique
        [Parameter(ValueFromPipeline)]
        [object]$InputObject
    )
    
    begin { $items = @() }
    process { $items += $InputObject }
    end {
        $grouped = $items | Group-Object
        
        $result = if ($d) {
            $grouped | Where-Object Count -gt 1
        } elseif ($u) {
            $grouped | Where-Object Count -eq 1
        } else {
            $grouped
        }
        
        if ($c) {
            $result | ForEach-Object { "{0,7} {1}" -f $_.Count, $_.Name }
        } else {
            $result | Select-Object -ExpandProperty Name
        }
    }
}

# tr (translate characters)
function tr {
    param(
        [switch]$d,  # delete
        [string]$Set1,
        [string]$Set2,
        [Parameter(ValueFromPipeline)]
        [string]$InputObject
    )
    
    process {
        if ($d) {
            $InputObject -replace "[$Set1]", ''
        } else {
            $output = $InputObject
            for ($i = 0; $i -lt [Math]::Min($Set1.Length, $Set2.Length); $i++) {
                $output = $output -replace [regex]::Escape($Set1[$i]), $Set2[$i]
            }
            $output
        }
    }
}

# diff
function diff {
    param(
        [string]$Path1,
        [string]$Path2
    )
    Compare-Object (Get-Content $Path1) (Get-Content $Path2)
}

# ----------------------------------------------------------------------------
# FIND & SEARCH
# ----------------------------------------------------------------------------

# find
function find {
    param(
        [string]$Path = ".",
        [string]$name,
        [string]$type,
        [string]$iname,
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Rest
    )
    
    $params = @{ Path = $Path; Recurse = $true }
    
    if ($name) { $params.Filter = $name }
    if ($iname) { $params.Filter = $iname }
    
    $results = Get-ChildItem @params -ErrorAction SilentlyContinue
    
    if ($type -eq 'd') {
        $results = $results | Where-Object { $_.PSIsContainer }
    } elseif ($type -eq 'f') {
        $results = $results | Where-Object { -not $_.PSIsContainer }
    }
    
    $results | Select-Object -ExpandProperty FullName
}

# which
function which {
    param([Parameter(Mandatory)][string]$Command)
    
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.CommandType -eq 'Alias') {
            Write-Output "$Command is aliased to $($cmd.Definition)"
            $cmd = Get-Command $cmd.Definition -ErrorAction SilentlyContinue
        }
        if ($cmd.Source) { $cmd.Source }
        elseif ($cmd.ScriptBlock) { "Function: $Command" }
    } else {
        Write-Error "$Command not found"
    }
}

# whereis
function whereis {
    param([Parameter(Mandatory)][string]$Command)
    Get-Command $Command -All -ErrorAction SilentlyContinue | 
        ForEach-Object { if ($_.Source) { $_.Source } else { $_.Name } }
}

# type (like bash type)
function type {
    param([Parameter(Mandatory)][string]$Command)
    Get-Command $Command | Format-List
}

# locate (uses Windows Search index)
function locate {
    param([Parameter(Mandatory)][string]$Pattern)
    Get-ChildItem -Path C:\ -Recurse -ErrorAction SilentlyContinue -Filter "*$Pattern*" | 
        Select-Object -ExpandProperty FullName -First 50
}

# ----------------------------------------------------------------------------
# PROCESS MANAGEMENT
# ----------------------------------------------------------------------------

# ps
Remove-Alias -Name ps -Force -ErrorAction SilentlyContinue
function ps {
    param(
        [switch]$aux,
        [switch]$ef,
        [string]$u
    )
    
    Get-Process | Select-Object Id, ProcessName, CPU, 
        @{N='MEM(MB)';E={[math]::Round($_.WorkingSet64/1MB,2)}},
        StartTime
}

# top/htop equivalent
function top {
    while ($true) {
        Clear-Host
        Get-Process | Sort-Object CPU -Descending | 
            Select-Object -First 20 Id, ProcessName, CPU, 
                @{N='MEM(MB)';E={[math]::Round($_.WorkingSet64/1MB,2)}} |
            Format-Table -AutoSize
        Start-Sleep -Seconds 2
    }
}
Set-Alias -Name htop -Value top

# kill
Remove-Alias -Name kill -Force -ErrorAction SilentlyContinue
function kill {
    param(
        [switch]$9,
        [Parameter(Mandatory)]
        [int[]]$Pid
    )
    
    foreach ($p in $Pid) {
        Stop-Process -Id $p -Force:$9
    }
}

# killall
function killall {
    param([Parameter(Mandatory)][string]$Name)
    Get-Process -Name $Name -ErrorAction SilentlyContinue | Stop-Process -Force
}

# pkill
function pkill {
    param([Parameter(Mandatory)][string]$Pattern)
    Get-Process | Where-Object { $_.ProcessName -match $Pattern } | Stop-Process -Force
}

# pgrep
function pgrep {
    param([Parameter(Mandatory)][string]$Pattern)
    Get-Process | Where-Object { $_.ProcessName -match $Pattern } | Select-Object -ExpandProperty Id
}

# jobs, bg, fg (PowerShell Jobs)
Set-Alias -Name jobs -Value Get-Job

# nohup equivalent (start detached process)
function nohup {
    param([Parameter(Mandatory)][string]$Command)
    Start-Process powershell -ArgumentList "-Command", $Command -WindowStyle Hidden
}

# ----------------------------------------------------------------------------
# SYSTEM INFORMATION
# ----------------------------------------------------------------------------

# uname
function uname {
    param([switch]$a, [switch]$r, [switch]$n, [switch]$m)
    
    $os = [Environment]::OSVersion
    $hostname = $env:COMPUTERNAME
    $arch = $env:PROCESSOR_ARCHITECTURE
    
    if ($a) {
        "Windows $($os.Version) $hostname $arch"
    } elseif ($r) {
        $os.Version.ToString()
    } elseif ($n) {
        $hostname
    } elseif ($m) {
        $arch
    } else {
        "Windows"
    }
}

# hostname
function hostname { $env:COMPUTERNAME }

# uptime
function uptime {
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    "up {0} days, {1}:{2:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
}

# whoami (already exists, but let's ensure it)
if (-not (Get-Command whoami -ErrorAction SilentlyContinue)) {
    function whoami { "$env:USERDOMAIN\$env:USERNAME" }
}

# id
function id {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    
    "uid=$($identity.User.Value) gid=$($identity.Groups[0].Value) groups=$($identity.Groups.Value -join ',')"
}

# df (disk free)
function df {
    param([switch]$h)
    
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $used = $_.Used
        $free = $_.Free
        $total = $used + $free
        
        if ($h -and $total -gt 0) {
            [PSCustomObject]@{
                Drive = $_.Root
                Size = "{0:N1}G" -f ($total / 1GB)
                Used = "{0:N1}G" -f ($used / 1GB)
                Avail = "{0:N1}G" -f ($free / 1GB)
                'Use%' = "{0:P0}" -f ($used / $total)
            }
        } elseif ($total -gt 0) {
            [PSCustomObject]@{
                Drive = $_.Root
                Size = $total
                Used = $used
                Avail = $free
                'Use%' = [math]::Round(($used / $total) * 100, 0)
            }
        }
    } | Format-Table -AutoSize
}

# du (disk usage)
function du {
    param(
        [switch]$h,
        [switch]$s,  # summary
        [string]$Path = "."
    )
    
    if ($s) {
        $size = (Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue | 
                 Measure-Object -Property Length -Sum).Sum
        if ($h) {
            "{0:N2} MB`t{1}" -f ($size / 1MB), $Path
        } else {
            "{0}`t{1}" -f $size, $Path
        }
    } else {
        Get-ChildItem $Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            if ($h) {
                "{0:N2} MB`t{1}" -f ($size / 1MB), $_.Name
            } else {
                "{0}`t{1}" -f $size, $_.Name
            }
        }
    }
}

# free (memory info)
function free {
    param([switch]$h, [switch]$m, [switch]$g)
    
    $os = Get-CimInstance Win32_OperatingSystem
    $total = $os.TotalVisibleMemorySize * 1KB
    $free = $os.FreePhysicalMemory * 1KB
    $used = $total - $free
    
    $div = 1
    $suffix = "B"
    if ($g) { $div = 1GB; $suffix = "G" }
    elseif ($m -or $h) { $div = 1MB; $suffix = "M" }
    
    [PSCustomObject]@{
        Total = "{0:N0}{1}" -f ($total / $div), $suffix
        Used = "{0:N0}{1}" -f ($used / $div), $suffix
        Free = "{0:N0}{1}" -f ($free / $div), $suffix
    } | Format-Table -AutoSize
}

# lscpu
function lscpu {
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
}

# lsblk (list block devices)
function lsblk {
    Get-Disk | Select-Object Number, FriendlyName, 
        @{N='Size(GB)';E={[math]::Round($_.Size/1GB,2)}}, 
        PartitionStyle, OperationalStatus
}

# dmesg equivalent (Windows Event Log)
function dmesg {
    Get-EventLog -LogName System -Newest 50 | 
        Select-Object TimeGenerated, EntryType, Source, Message
}

# ----------------------------------------------------------------------------
# NETWORKING
# ----------------------------------------------------------------------------

# ifconfig / ip addr
function ifconfig {
    Get-NetIPAddress | Select-Object InterfaceAlias, IPAddress, AddressFamily, PrefixLength |
        Format-Table -AutoSize
}
Set-Alias -Name 'ip' -Value ifconfig

# netstat
function netstat {
    param([switch]$tulpn, [switch]$an)
    Get-NetTCPConnection | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
        Format-Table -AutoSize
}

# ss
function ss {
    param([switch]$tulpn)
    Get-NetTCPConnection | Where-Object State -eq 'Listen' |
        Select-Object LocalAddress, LocalPort, OwningProcess |
        Format-Table -AutoSize
}

# ping (already exists)
# traceroute
Set-Alias -Name traceroute -Value tracert

# nslookup/dig/host
function dig {
    param([Parameter(Mandatory)][string]$Domain)
    Resolve-DnsName $Domain
}
Set-Alias -Name host -Value dig

# curl and wget (PowerShell has Invoke-WebRequest)
Remove-Alias -Name curl -Force -ErrorAction SilentlyContinue
Remove-Alias -Name wget -Force -ErrorAction SilentlyContinue

function curl {
    param(
        [switch]$O,
        [switch]$L,
        [string]$o,
        [Parameter(Mandatory)]
        [string]$Url
    )
    
    $params = @{ Uri = $Url; UseBasicParsing = $true }
    if ($L) { $params.MaximumRedirection = 10 }
    
    if ($O) {
        $filename = Split-Path $Url -Leaf
        Invoke-WebRequest @params -OutFile $filename
    } elseif ($o) {
        Invoke-WebRequest @params -OutFile $o
    } else {
        (Invoke-WebRequest @params).Content
    }
}

function wget {
    param(
        [string]$O,
        [Parameter(Mandatory)]
        [string]$Url
    )
    
    $filename = if ($O) { $O } else { Split-Path $Url -Leaf }
    Invoke-WebRequest -Uri $Url -OutFile $filename -UseBasicParsing
}

# scp (if OpenSSH is installed)
# ssh (if OpenSSH is installed)

# ----------------------------------------------------------------------------
# ARCHIVE & COMPRESSION
# ----------------------------------------------------------------------------

# tar
function tar {
    param(
        [switch]$x,   # extract
        [switch]$c,   # create
        [switch]$v,   # verbose
        [switch]$z,   # gzip
        [switch]$f,   # file
        [string]$File,
        [string[]]$Sources
    )
    
    if ($x) {
        if ($File -match '\.tar\.gz$|\.tgz$') {
            tar -xvzf $File  # Use native tar if available
        } else {
            Expand-Archive -Path $File -DestinationPath . -Verbose:$v
        }
    } elseif ($c) {
        Compress-Archive -Path $Sources -DestinationPath $File -Verbose:$v
    }
}

# gzip/gunzip
function gzip {
    param([Parameter(Mandatory)][string]$Path)
    Compress-Archive -Path $Path -DestinationPath "$Path.gz"
}

function gunzip {
    param([Parameter(Mandatory)][string]$Path)
    Expand-Archive -Path $Path -DestinationPath (Split-Path $Path)
}

# zip/unzip
function zip {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string[]]$Files
    )
    Compress-Archive -Path $Files -DestinationPath $Archive
}

function unzip {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [string]$Destination = "."
    )
    Expand-Archive -Path $Archive -DestinationPath $Destination
}

# ----------------------------------------------------------------------------
# ENVIRONMENT & SHELL
# ----------------------------------------------------------------------------

# export
function export {
    param([Parameter(Mandatory)][string]$Assignment)
    
    if ($Assignment -match '^(\w+)=(.*)$') {
        $name = $Matches[1]
        $value = $Matches[2] -replace '^["'']|["'']$', ''
        Set-Item -Path "Env:$name" -Value $value
    }
}

# env
function env { Get-ChildItem Env: | Format-Table Name, Value -AutoSize }

# printenv
function printenv {
    param([string]$Name)
    if ($Name) {
        [Environment]::GetEnvironmentVariable($Name)
    } else {
        Get-ChildItem Env: | ForEach-Object { "$($_.Name)=$($_.Value)" }
    }
}

# source
function source {
    param([Parameter(Mandatory)][string]$Path)
    . $Path
}

# alias (list or create)
function alias {
    param(
        [string]$Definition
    )
    
    if ($Definition) {
        if ($Definition -match '^(\w+)=[''"]?(.+?)[''"]?$') {
            Set-Alias -Name $Matches[1] -Value $Matches[2] -Scope Global
        }
    } else {
        Get-Alias | Format-Table Name, Definition -AutoSize
    }
}

# history
Set-Alias -Name history -Value Get-History -Option AllScope

# clear (already aliased but ensure it works)
Set-Alias -Name clear -Value Clear-Host -Option AllScope
Set-Alias -Name cls -Value Clear-Host -Option AllScope

# exit (already works)

# echo
function echo { Write-Output $args }

# printf (basic)
function printf {
    param([string]$Format, [object[]]$Arguments)
    $Format -f $Arguments
}

# xargs (basic implementation)
function xargs {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(ValueFromPipeline)]
        [string]$InputObject
    )
    
    begin { $items = @() }
    process { $items += $InputObject }
    end {
        & $Command $items
    }
}

# tee
function tee {
    param(
        [switch]$a,  # append
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(ValueFromPipeline)]
        [object]$InputObject
    )
    
    process {
        if ($a) {
            $InputObject | Add-Content $FilePath
        } else {
            $InputObject | Set-Content $FilePath
        }
        $InputObject
    }
}

# ----------------------------------------------------------------------------
# MISC UTILITIES
# ----------------------------------------------------------------------------

# date
function date {
    param([string]$Format)
    if ($Format) {
        Get-Date -Format $Format
    } else {
        Get-Date
    }
}

# cal (calendar)
function cal {
    param([int]$Month = (Get-Date).Month, [int]$Year = (Get-Date).Year)
    
    $firstDay = Get-Date -Year $Year -Month $Month -Day 1
    $daysInMonth = [DateTime]::DaysInMonth($Year, $Month)
    
    Write-Output ("{0,20}" -f $firstDay.ToString("MMMM yyyy"))
    Write-Output "Su Mo Tu We Th Fr Sa"
    
    $dayOfWeek = [int]$firstDay.DayOfWeek
    $line = "   " * $dayOfWeek
    
    for ($day = 1; $day -le $daysInMonth; $day++) {
        $line += "{0,2} " -f $day
        if (($dayOfWeek + $day) % 7 -eq 0) {
            Write-Output $line
            $line = ""
        }
    }
    if ($line) { Write-Output $line }
}

# bc (basic calculator)
function bc {
    param([Parameter(ValueFromPipeline)][string]$Expression)
    process {
        if ($Expression) {
            Invoke-Expression $Expression
        } else {
            while ($true) {
                $expr = Read-Host "bc"
                if ($expr -eq 'quit') { break }
                try { Invoke-Expression $expr } catch { Write-Error $_.Exception.Message }
            }
        }
    }
}

# sleep
function sleep {
    param([Parameter(Mandatory)][int]$Seconds)
    Start-Sleep -Seconds $Seconds
}

# yes
function yes {
    param([string]$Text = "y")
    while ($true) { Write-Output $Text }
}

# true/false
function true { $true }
function false { $false }

# basename
function basename {
    param([Parameter(Mandatory)][string]$Path)
    Split-Path $Path -Leaf
}

# dirname
function dirname {
    param([Parameter(Mandatory)][string]$Path)
    Split-Path $Path -Parent
}

# realpath
function realpath {
    param([Parameter(Mandatory)][string]$Path)
    (Resolve-Path $Path).Path
}

# readlink
function readlink {
    param([Parameter(Mandatory)][string]$Path)
    (Get-Item $Path).Target
}

# md5sum / sha256sum
function md5sum {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash $Path -Algorithm MD5).Hash.ToLower() + "  " + $Path
}

function sha256sum {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash $Path -Algorithm SHA256).Hash.ToLower() + "  " + $Path
}

function sha1sum {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash $Path -Algorithm SHA1).Hash.ToLower() + "  " + $Path
}

# file (get file type)
function file {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item $Path
    if ($item.PSIsContainer) {
        "$Path`: directory"
    } else {
        $ext = $item.Extension
        "$Path`: $ext file, $($item.Length) bytes"
    }
}

# stat
function stat {
    param([Parameter(Mandatory)][string]$Path)
    Get-Item $Path | Select-Object Name, Length, CreationTime, LastWriteTime, LastAccessTime, Attributes
}

# watch (run command repeatedly)
function watch {
    param(
        [int]$n = 2,
        [Parameter(Mandatory)]
        [string]$Command
    )
    
    while ($true) {
        Clear-Host
        Write-Output "Every ${n}s: $Command`n"
        Invoke-Expression $Command
        Start-Sleep -Seconds $n
    }
}

# timeout
function timeout {
    param(
        [Parameter(Mandatory)][int]$Seconds,
        [Parameter(Mandatory)][string]$Command
    )
    
    $job = Start-Job -ScriptBlock { param($cmd) Invoke-Expression $cmd } -ArgumentList $Command
    $completed = Wait-Job $job -Timeout $Seconds
    
    if ($completed) {
        Receive-Job $job
    } else {
        Stop-Job $job
        Write-Error "Command timed out after $Seconds seconds"
    }
    Remove-Job $job
}

# time (measure command execution)
function time {
    param([Parameter(Mandatory)][string]$Command)
    Measure-Command { Invoke-Expression $Command } | 
        Select-Object @{N='real';E={$_.TotalSeconds}}, 
                      @{N='user';E={'N/A'}}, 
                      @{N='sys';E={'N/A'}}
}

# ----------------------------------------------------------------------------
# SUDO EQUIVALENT (Run as Admin)
# ----------------------------------------------------------------------------

function sudo {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Command)
    
    $cmdString = $Command -join ' '
    Start-Process powershell -Verb RunAs -ArgumentList "-Command", $cmdString
}

# ----------------------------------------------------------------------------
# PACKAGE MANAGEMENT ALIASES (for common package managers)
# ----------------------------------------------------------------------------

# If using Chocolatey
if (Get-Command choco -ErrorAction SilentlyContinue) {
    function apt-get { choco $args }
    function apt { choco $args }
    function yum { choco $args }
}

# If using Scoop
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    function brew { scoop $args }
}

# If using winget
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Set-Alias -Name apt -Value winget -Option AllScope
}

# ----------------------------------------------------------------------------
# PROMPT CUSTOMIZATION (Optional - uncomment to use)
# ----------------------------------------------------------------------------

<#
function prompt {
    $location = (Get-Location).Path.Replace($HOME, '~')
    $branch = ""
    
    # Git branch (if in a git repo)
    if (Test-Path .git) {
        $branch = " ($(git branch --show-current 2>$null))"
    }
    
    # Color prompt like bash
    Write-Host "$env:USERNAME@$env:COMPUTERNAME" -ForegroundColor Green -NoNewline
    Write-Host ":" -NoNewline
    Write-Host $location -ForegroundColor Blue -NoNewline
    Write-Host $branch -ForegroundColor Cyan -NoNewline
    Write-Host "$" -NoNewline
    return " "
}
#>

# ----------------------------------------------------------------------------
# HELPFUL MESSAGES
# ----------------------------------------------------------------------------

Write-Host "Linux compatibility aliases loaded!" -ForegroundColor Green
Write-Host "Type 'alias' to see available aliases." -ForegroundColor DarkGray

# ============================================================================
# END OF PROFILE
# ============================================================================
