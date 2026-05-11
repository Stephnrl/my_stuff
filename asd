<#
.SYNOPSIS
    Audits an AKS cluster against NIST 800-171 Rev 2 / CMMC Level 2 controls
    most relevant to shared-resource isolation and FIPS-validated cryptography.

.DESCRIPTION
    Read-only audit. Does not modify the cluster. Emits a colored console
    report and writes a Markdown file suitable for inclusion in an SSP or
    POA&M evidence package.

    Controls touched (NIST 800-171 r2 / CMMC L2):
      AC.L2-3.1.1   Authorized system access
      AC.L2-3.1.5   Least privilege
      IA.L2-3.5.2   Authenticator management (workload identity / OIDC)
      SC.L2-3.13.4  Shared system resources
      SC.L2-3.13.8  Transmission confidentiality
      SC.L2-3.13.11 FIPS-validated cryptography
      SC.L2-3.13.16 CUI at rest

    Required tools on PATH: az, kubectl.
    PowerShell 5.1 or later. PowerShell 7+ recommended.

.PARAMETER ClusterName
    Name of the AKS cluster.

.PARAMETER ResourceGroup
    Resource group containing the cluster.

.PARAMETER SubscriptionId
    Optional. Azure subscription ID. Defaults to current az context.

.PARAMETER OutputPath
    Optional. Path for the Markdown report.
    Defaults to ./aks-audit-<cluster>-<timestamp>.md

.PARAMETER SkipPolicyChecks
    Skip Azure Policy / Defender queries. Useful on large subscriptions
    where these queries are slow.

.EXAMPLE
    ./Audit-AksCompliance.ps1 -ClusterName myaks -ResourceGroup myrg

.EXAMPLE
    ./Audit-AksCompliance.ps1 -ClusterName myaks -ResourceGroup myrg `
        -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -OutputPath ./evidence/audit.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $ClusterName,
    [Parameter(Mandatory=$true)] [string] $ResourceGroup,
    [Parameter(Mandatory=$false)][string] $SubscriptionId,
    [Parameter(Mandatory=$false)][string] $OutputPath,
    [Parameter(Mandatory=$false)][switch] $SkipPolicyChecks
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

if (-not $OutputPath) {
    $OutputPath = "./aks-audit-$ClusterName-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
}

# ---------- State ----------
$script:report   = New-Object System.Collections.Generic.List[string]
$script:counts   = @{ PASS = 0; WARN = 0; FAIL = 0; INFO = 0 }
$script:topFails = New-Object System.Collections.Generic.List[string]

# ---------- Helpers ----------
function Write-Section {
    param([string]$Title, [string]$Control = '')
    $heading = if ($Control) { "$Title  ($Control)" } else { $Title }
    Write-Host ""
    Write-Host "=== $heading ===" -ForegroundColor Cyan
    [void]$script:report.Add("`n## $heading`n")
}

function Write-Check {
    param(
        [string] $Name,
        [ValidateSet('PASS','WARN','FAIL','INFO')][string] $Status,
        [string] $Detail = ''
    )
    $color  = @{ PASS='Green'; WARN='Yellow'; FAIL='Red'; INFO='Gray' }[$Status]
    $tag    = "[$Status]"
    Write-Host ("{0,-6} " -f $tag) -ForegroundColor $color -NoNewline
    Write-Host $Name
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray }

    $script:counts[$Status]++

    $line = "- **$tag** $Name"
    if ($Detail) { $line += "`n  - $Detail" }
    [void]$script:report.Add($line)

    if ($Status -eq 'FAIL') {
        $entry = $Name
        if ($Detail) { $entry += " — $Detail" }
        [void]$script:topFails.Add($entry)
    }
}

function Invoke-AzJson {
    param([string[]] $Args)
    try {
        $raw = & az @Args -o json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
        return ($raw | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue)
    } catch { return $null }
}

function Invoke-KubectlJson {
    param([string[]] $Args)
    try {
        $raw = & kubectl @Args -o json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
        return ($raw | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue)
    } catch { return $null }
}

function As-Array { param($v) if ($null -eq $v) { @() } elseif ($v -is [array]) { $v } else { ,$v } }

# ---------- Prereqs ----------
function Test-Prerequisites {
    Write-Section "Prerequisites"
    $ok = $true
    foreach ($tool in @('az','kubectl')) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            Write-Check "$tool installed" 'PASS'
        } else {
            Write-Check "$tool installed" 'FAIL' "Install $tool and retry"
            $ok = $false
        }
    }
    if (-not $ok) { throw "Missing prerequisites" }

    if ($SubscriptionId) {
        & az account set --subscription $SubscriptionId 2>$null | Out-Null
    }
    $ctx = Invoke-AzJson @('account','show')
    if (-not $ctx) { throw "Not logged in. Run: az login" }
    Write-Check "Azure context" 'INFO' "$($ctx.name) ($($ctx.id))"

    & az aks get-credentials -g $ResourceGroup -n $ClusterName --overwrite-existing 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not fetch credentials for $ClusterName" }
    Write-Check "kubectl context for $ClusterName" 'PASS'
}

# ---------- Cluster posture ----------
function Test-ClusterPosture {
    Write-Section "Cluster Security Profile" "multiple controls"
    $aks = Invoke-AzJson @('aks','show','-g',$ResourceGroup,'-n',$ClusterName)
    if (-not $aks) { Write-Check "Read cluster config" 'FAIL' "az aks show failed"; return $null }

    if ($aks.diskEncryptionSetID) {
        Write-Check "Node disk encryption (customer-managed key)" 'PASS' "DES: $($aks.diskEncryptionSetID)"
    } else {
        Write-Check "Node disk encryption (customer-managed key)" 'WARN' "No DES configured. Platform-managed key is FIPS-validated but assessor may want CMK for CUI."
    }

    $kms = $aks.securityProfile.azureKeyVaultKms
    if ($kms -and $kms.enabled) {
        Write-Check "etcd KMS encryption" 'PASS' "Key: $($kms.keyId)"
    } else {
        Write-Check "etcd KMS encryption" 'FAIL' "Cluster secrets in etcd are not encrypted with a customer key. Enable Azure KMS plugin."
    }

    $defender = $aks.securityProfile.defender.securityMonitoring.enabled
    if ($defender) { Write-Check "Defender for Containers" 'PASS' }
    else           { Write-Check "Defender for Containers" 'WARN' "Off. Reduces continuous-monitoring evidence." }

    $polEnabled = $aks.addonProfiles.azurepolicy.enabled
    if ($polEnabled) { Write-Check "Azure Policy add-on" 'PASS' }
    else             { Write-Check "Azure Policy add-on" 'FAIL' "Required for cluster-wide policy enforcement." }

    $wi = $aks.securityProfile.workloadIdentity.enabled
    $oi = $aks.oidcIssuerProfile.enabled
    if ($wi -and $oi) {
        Write-Check "Workload Identity + OIDC issuer" 'PASS' "Federation available (IA.L2-3.5.2)"
    } elseif ($oi) {
        Write-Check "Workload Identity + OIDC issuer" 'WARN' "OIDC issuer on, Workload Identity disabled."
    } else {
        Write-Check "Workload Identity + OIDC issuer" 'WARN' "Disabled. Required if pods need federated Azure auth."
    }

    $apiAccess = $aks.apiServerAccessProfile
    if ($apiAccess.enablePrivateCluster) {
        Write-Check "Private API server" 'PASS'
    } elseif ($apiAccess.authorizedIpRanges -and $apiAccess.authorizedIpRanges.Count -gt 0) {
        Write-Check "API server access" 'WARN' "Public with allowlist: $($apiAccess.authorizedIpRanges -join ', ')"
    } else {
        Write-Check "API server access" 'FAIL' "Public API server with no IP allowlist."
    }

    if ($aks.securityProfile.imageCleaner.enabled) {
        Write-Check "Image Cleaner (Eraser) enabled" 'PASS'
    } else {
        Write-Check "Image Cleaner (Eraser) enabled" 'INFO' "Optional but reduces stale-image surface on nodes."
    }

    return $aks
}

# ---------- Node pools ----------
function Test-NodePools {
    Write-Section "Node Pools" "SC.L2-3.13.4 / SC.L2-3.13.11"
    $pools = As-Array (Invoke-AzJson @('aks','nodepool','list','--cluster-name',$ClusterName,'-g',$ResourceGroup))
    if ($pools.Count -eq 0) { Write-Check "Read node pools" 'FAIL'; return }

    Write-Check "Node pool count" 'INFO' "$($pools.Count)"
    if ($pools.Count -eq 1) {
        Write-Check "Workload segregation by pool" 'FAIL' "Single node pool — cannot segregate CUI from non-CUI."
    }

    $fipsCount = 0
    foreach ($p in $pools) {
        $name = $p.name

        if ($p.enableFIPS) {
            Write-Check "Pool '$name' FIPS-enabled" 'PASS'
            $fipsCount++
        } else {
            Write-Check "Pool '$name' FIPS-enabled" 'FAIL' "enableFIPS=false. SC.L2-3.13.11 requires validated crypto on pools handling CUI."
        }

        $taints = As-Array $p.nodeTaints
        if ($taints.Count -gt 0) {
            Write-Check "Pool '$name' taints" 'PASS' ($taints -join '; ')
        } else {
            Write-Check "Pool '$name' taints" 'WARN' "No taints. Any pod can land here."
        }

        $labelNames = if ($p.nodeLabels) { $p.nodeLabels.PSObject.Properties.Name } else { @() }
        $sens = $labelNames | Where-Object { $_ -match '(?i)workload|sensitivity|cui|env|tier' }
        if ($sens) {
            Write-Check "Pool '$name' sensitivity labels" 'PASS' ($sens -join ', ')
        } else {
            Write-Check "Pool '$name' sensitivity labels" 'WARN' "No labels distinguish workload type."
        }
    }

    if ($fipsCount -eq 0) {
        Write-Check "Any FIPS-enabled pool" 'FAIL' "Zero FIPS-enabled pools cluster-wide."
    }
}

# ---------- Nodes ----------
function Test-Nodes {
    Write-Section "Node Runtime Status"
    $nodes = Invoke-KubectlJson @('get','nodes')
    $items = As-Array $nodes.items
    if ($items.Count -eq 0) { Write-Check "Read nodes" 'FAIL'; return }

    $fipsKernels = 0
    foreach ($n in $items) {
        if ($n.status.nodeInfo.kernelVersion -match 'fips') { $fipsKernels++ }
    }

    if ($fipsKernels -eq $items.Count) {
        Write-Check "All nodes on FIPS kernel" 'PASS' "$fipsKernels/$($items.Count)"
    } elseif ($fipsKernels -gt 0) {
        Write-Check "FIPS kernel coverage" 'WARN' "$fipsKernels of $($items.Count) nodes report FIPS kernel"
    } else {
        Write-Check "Any node on FIPS kernel" 'FAIL' "0 of $($items.Count) nodes report a FIPS kernel"
    }

    $sample = $items[0]
    Write-Check "Sample node detail" 'INFO' "OS: $($sample.status.nodeInfo.osImage)  |  Kernel: $($sample.status.nodeInfo.kernelVersion)  |  Runtime: $($sample.status.nodeInfo.containerRuntimeVersion)"
}

# ---------- Pod Security Admission ----------
function Test-PodSecurityAdmission {
    Write-Section "Pod Security Admission" "workload isolation"
    $ns = Invoke-KubectlJson @('get','namespaces')
    $items = As-Array $ns.items
    if ($items.Count -eq 0) { Write-Check "Read namespaces" 'FAIL'; return }

    $systemNs = @('kube-system','kube-public','kube-node-lease','gatekeeper-system','calico-system','tigera-operator','azure-arc','azure-extensions-usage-system','aks-command')
    $userNs = $items | Where-Object {
        $_.metadata.name -notin $systemNs -and $_.metadata.name -notmatch '^kube-'
    }

    if ($userNs.Count -eq 0) {
        Write-Check "User namespaces present" 'INFO' "Only system namespaces detected"
        return
    }

    $enforced = 0
    foreach ($n in $userNs) {
        $labels  = $n.metadata.labels
        $enforce = $null
        if ($labels) { $enforce = $labels.'pod-security.kubernetes.io/enforce' }

        if ($enforce -in @('baseline','restricted')) {
            Write-Check "Namespace '$($n.metadata.name)' PSA" 'PASS' "enforce=$enforce"
            $enforced++
        } else {
            Write-Check "Namespace '$($n.metadata.name)' PSA" 'WARN' "No enforce label. Privileged workloads permitted."
        }
    }

    if ($enforced -eq 0) {
        Write-Check "Any user namespace with PSA enforcement" 'FAIL' "0 of $($userNs.Count) user namespaces enforce Pod Security Standards."
    }
}

# ---------- NetworkPolicy ----------
function Test-NetworkPolicies {
    Write-Section "NetworkPolicies" "SC.L2-3.13.4 (network paths)"
    $netProfile = Invoke-AzJson @('aks','show','-g',$ResourceGroup,'-n',$ClusterName,'--query','networkProfile')
    if ($netProfile) {
        $policy = $netProfile.networkPolicy
        if ($policy -in @('azure','calico','cilium')) {
            Write-Check "CNI NetworkPolicy plugin" 'PASS' "Plugin: $policy"
        } else {
            Write-Check "CNI NetworkPolicy plugin" 'FAIL' "networkPolicy='$policy'. NetworkPolicies will not be enforced."
            return
        }
    }

    $netpols = Invoke-KubectlJson @('get','networkpolicy','-A')
    $items = As-Array $netpols.items
    if ($items.Count -eq 0) {
        Write-Check "NetworkPolicy count" 'FAIL' "Zero policies. Cluster is default-allow."
        return
    }
    Write-Check "NetworkPolicy count" 'INFO' "$($items.Count) policies across cluster"

    $byNs = $items | Group-Object { $_.metadata.namespace }
    foreach ($g in $byNs) {
        $denyAll = $g.Group | Where-Object {
            $sel = $_.spec.podSelector
            $selectorEmpty = -not $sel -or -not $sel.matchLabels -or @($sel.matchLabels.PSObject.Properties).Count -eq 0
            $ingress = As-Array $_.spec.ingress
            $hasIngressType = (As-Array $_.spec.policyTypes) -contains 'Ingress'
            $selectorEmpty -and $ingress.Count -eq 0 -and $hasIngressType
        }
        if ($denyAll) {
            Write-Check "Namespace '$($g.Name)' default-deny ingress" 'PASS'
        } else {
            Write-Check "Namespace '$($g.Name)' default-deny ingress" 'WARN' "Has policies but no default-deny baseline."
        }
    }
}

# ---------- Privileged / risky pods ----------
function Test-RiskyPods {
    Write-Section "Privileged and Host-Namespace Pods" "SC.L2-3.13.4 / AC.L2-3.1.5"
    $pods = Invoke-KubectlJson @('get','pods','-A')
    $items = As-Array $pods.items
    if ($items.Count -eq 0) { Write-Check "Read pods" 'FAIL'; return }

    $systemNs   = @('kube-system','calico-system','tigera-operator','gatekeeper-system','azure-arc','azure-extensions-usage-system')
    $privileged = New-Object System.Collections.Generic.List[string]
    $hostNet    = New-Object System.Collections.Generic.List[string]
    $hostPID    = New-Object System.Collections.Generic.List[string]
    $hostIPC    = New-Object System.Collections.Generic.List[string]
    $sockets    = New-Object System.Collections.Generic.List[string]
    $rootRun    = New-Object System.Collections.Generic.List[string]

    foreach ($p in $items) {
        $id = "$($p.metadata.namespace)/$($p.metadata.name)"
        $isSystem = $p.metadata.namespace -in $systemNs

        foreach ($c in (As-Array $p.spec.containers)) {
            if ($c.securityContext.privileged -eq $true -and -not $isSystem) {
                [void]$privileged.Add("$id ($($c.name))")
            }
        }

        if (-not $isSystem) {
            if ($p.spec.hostNetwork -eq $true) { [void]$hostNet.Add($id) }
            if ($p.spec.hostPID     -eq $true) { [void]$hostPID.Add($id) }
            if ($p.spec.hostIPC     -eq $true) { [void]$hostIPC.Add($id) }
        }

        foreach ($v in (As-Array $p.spec.volumes)) {
            $path = $v.hostPath.path
            if ($path -in @('/var/run/docker.sock','/var/run/containerd/containerd.sock','/run/containerd/containerd.sock','/run/crio/crio.sock')) {
                [void]$sockets.Add("$id mounts $path")
            }
        }

        if (-not $isSystem) {
            $podNonRoot = $p.spec.securityContext.runAsNonRoot
            foreach ($c in (As-Array $p.spec.containers)) {
                $cNonRoot = $c.securityContext.runAsNonRoot
                if ($cNonRoot -ne $true -and $podNonRoot -ne $true) {
                    [void]$rootRun.Add("$id ($($c.name))")
                }
            }
        }
    }

    function _Report([System.Collections.Generic.List[string]]$bag, [string]$label, [string]$failTier='FAIL') {
        if ($bag.Count -eq 0) {
            Write-Check $label 'PASS' "None outside system namespaces"
        } else {
            $sample = ($bag | Select-Object -First 5) -join '; '
            $extra  = if ($bag.Count -gt 5) { " ...and $($bag.Count - 5) more" } else { '' }
            Write-Check $label $failTier "$($bag.Count) found: $sample$extra"
        }
    }

    _Report $privileged "Privileged containers"               'FAIL'
    _Report $hostNet    "Pods with hostNetwork"               'FAIL'
    _Report $hostPID    "Pods with hostPID"                   'FAIL'
    _Report $hostIPC    "Pods with hostIPC"                   'FAIL'
    _Report $sockets    "Pods mounting container runtime socket" 'FAIL'
    _Report $rootRun    "Containers not enforcing runAsNonRoot"  'WARN'
}

# ---------- RBAC ----------
function Test-Rbac {
    Write-Section "RBAC Posture" "AC.L2-3.1.5"
    $crbs = Invoke-KubectlJson @('get','clusterrolebinding')
    $items = As-Array $crbs.items
    if ($items.Count -eq 0) { Write-Check "Read CRBs" 'FAIL'; return }

    $admins = $items | Where-Object { $_.roleRef.name -eq 'cluster-admin' }
    $adminSubjects = @()
    foreach ($crb in $admins) {
        foreach ($s in (As-Array $crb.subjects)) {
            $adminSubjects += "$($s.kind):$($s.name) (via $($crb.metadata.name))"
        }
    }
    Write-Check "cluster-admin grants total" 'INFO' "$($adminSubjects.Count) subject(s)"

    $expectedPattern = 'system:masters|system:nodes|aks-cluster-admin|aks-service|aksService'
    $unexpected = @($adminSubjects | Where-Object { $_ -notmatch $expectedPattern })
    if ($unexpected.Count -gt 0) {
        $sample = ($unexpected | Select-Object -First 3) -join '; '
        Write-Check "Non-system cluster-admin grants" 'WARN' "$($unexpected.Count) found: $sample"
    } else {
        Write-Check "Non-system cluster-admin grants" 'PASS'
    }

    $pods = Invoke-KubectlJson @('get','pods','-A')
    $podItems = As-Array $pods.items
    $systemNs = @('kube-system','calico-system','tigera-operator','gatekeeper-system','azure-arc','azure-extensions-usage-system')
    $defaultSA = $podItems | Where-Object {
        ($_.spec.serviceAccountName -eq 'default' -or -not $_.spec.serviceAccountName) -and
        $_.metadata.namespace -notin $systemNs
    }
    if ($defaultSA.Count -gt 0) {
        Write-Check "Workloads using 'default' ServiceAccount" 'WARN' "$($defaultSA.Count) pods. Use dedicated SAs per workload."
    } else {
        Write-Check "Workloads using 'default' ServiceAccount" 'PASS'
    }
}

# ---------- Storage ----------
function Test-Storage {
    Write-Section "Storage Posture" "SC.L2-3.13.16 / MP.L2-3.8.3"
    $scs = Invoke-KubectlJson @('get','storageclass')
    foreach ($sc in (As-Array $scs.items)) {
        $name    = $sc.metadata.name
        $reclaim = $sc.reclaimPolicy
        $des     = if ($sc.parameters) { $sc.parameters.diskEncryptionSetID } else { $null }
        $msg     = "Reclaim=$reclaim; CMK=$(if ($des) { 'yes' } else { 'no' })"
        if ($reclaim -eq 'Delete' -and $des) {
            Write-Check "StorageClass '$name'" 'PASS' $msg
        } elseif ($reclaim -eq 'Retain' -and -not $des) {
            Write-Check "StorageClass '$name'" 'WARN' "$msg. Retain without CMK requires documented wipe procedure (MP.L2-3.8.3)."
        } else {
            Write-Check "StorageClass '$name'" 'INFO' $msg
        }
    }

    $disks = As-Array (Invoke-AzJson @('disk','list','-g',$ResourceGroup))
    if ($disks.Count -gt 0) {
        $cmk      = $disks | Where-Object { $_.encryption.type -like '*CustomerKey*' }
        $platform = $disks | Where-Object { $_.encryption.type -eq 'EncryptionAtRestWithPlatformKey' }
        Write-Check "Disks in resource group" 'INFO' "$($disks.Count) total — $($cmk.Count) CMK, $($platform.Count) platform-key"
        if ($cmk.Count -eq 0) {
            Write-Check "Customer-managed disk encryption" 'WARN' "No disks use a customer-managed key. Platform key is FIPS-validated; CMK strengthens the story for CUI."
        }
    }
}

# ---------- ARC runners ----------
function Test-ArcRunners {
    Write-Section "GitHub Actions Runner Configuration" "SC.L2-3.13.4 (runner isolation)"

    $newRaw = & kubectl get autoscalingrunnersets.actions.github.com -A -o json 2>$null
    $newOk  = ($LASTEXITCODE -eq 0 -and $newRaw)

    $legRaw = & kubectl get runnerdeployments -A -o json 2>$null
    $legOk  = ($LASTEXITCODE -eq 0 -and $legRaw)

    if (-not $newOk -and -not $legOk) {
        Write-Check "ARC CRDs detected" 'INFO' "No ARC CRDs found. If runners are deployed by other means, audit manually."
        return
    }

    if ($newOk) {
        $parsed = $newRaw | Out-String | ConvertFrom-Json
        $sets = As-Array $parsed.items
        if ($sets.Count -gt 0) {
            foreach ($rs in $sets) {
                $id = "$($rs.metadata.namespace)/$($rs.metadata.name)"
                Write-Check "AutoscalingRunnerSet '$id'" 'PASS' "ARC v2 (ephemeral by design)"
            }
        }
    }

    if ($legOk) {
        $parsed = $legRaw | Out-String | ConvertFrom-Json
        $rds = As-Array $parsed.items
        foreach ($rd in $rds) {
            $id = "$($rd.metadata.namespace)/$($rd.metadata.name)"
            $ephem = $rd.spec.template.spec.ephemeral
            $docker = $rd.spec.template.spec.dockerEnabled

            if ($ephem -eq $false) {
                Write-Check "RunnerDeployment '$id' ephemeral" 'FAIL' "ephemeral=false. Workspace persists between jobs."
            } else {
                Write-Check "RunnerDeployment '$id' ephemeral" 'PASS'
            }
            if ($docker -ne $false) {
                Write-Check "RunnerDeployment '$id' Docker daemon" 'FAIL' "dockerEnabled=true mounts the runtime socket. Use rootless build tooling (kaniko, buildah, BuildKit rootless)."
            }
        }
    }
}

# ---------- Azure Policy / Defender ----------
function Test-AzurePolicyDefender {
    if ($SkipPolicyChecks) { return }
    Write-Section "Azure Policy and Defender" "continuous compliance evidence"

    $ctx = Invoke-AzJson @('account','show')
    $resourceId = "/subscriptions/$($ctx.id)/resourceGroups/$ResourceGroup/providers/Microsoft.ContainerService/managedClusters/$ClusterName"

    $nonCompliant = Invoke-AzJson @('policy','state','list','--resource',$resourceId,'--filter',"complianceState eq 'NonCompliant'",'--top','100')
    $items = As-Array $nonCompliant
    if ($items.Count -gt 0) {
        $names = ($items | Select-Object -First 5 -ExpandProperty policyDefinitionName) -join '; '
        Write-Check "Non-compliant Azure Policy findings" 'WARN' "$($items.Count) findings. Top: $names"
    } else {
        Write-Check "Azure Policy compliance" 'PASS' "No non-compliant findings (or no policies assigned)."
    }

    $assess = Invoke-AzJson @('security','assessment','list','--query',"[?contains(resourceDetails.id,'$ClusterName')]")
    $aitems = As-Array $assess
    if ($aitems.Count -gt 0) {
        $unhealthy = $aitems | Where-Object { $_.status.code -ne 'Healthy' }
        if ($unhealthy.Count -gt 0) {
            Write-Check "Defender unhealthy assessments" 'WARN' "$($unhealthy.Count) findings"
        } else {
            Write-Check "Defender assessments" 'PASS'
        }
    } else {
        Write-Check "Defender assessments" 'INFO' "No data (Defender for Containers may not be enabled or no findings yet)."
    }
}

# ---------- Main ----------
$header = @"
# AKS Compliance Audit Report

**Cluster:** $ClusterName
**Resource Group:** $ResourceGroup
**Run:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
**Auditor:** $env:USERNAME on $env:COMPUTERNAME

This report is automated and read-only. It maps findings to NIST 800-171 Rev 2
controls used by CMMC Level 2. Use it as a gap analysis input — not a final
attestation. Each **FAIL** is a likely audit finding; each **WARN** warrants
review and either remediation or a documented risk acceptance / POA&M entry.

"@

Write-Host $header
[void]$script:report.Add($header)

try {
    Test-Prerequisites
    Test-ClusterPosture | Out-Null
    Test-NodePools
    Test-Nodes
    Test-PodSecurityAdmission
    Test-NetworkPolicies
    Test-RiskyPods
    Test-Rbac
    Test-Storage
    Test-ArcRunners
    Test-AzurePolicyDefender
} catch {
    Write-Host ""
    Write-Host "[ERROR] Audit halted: $_" -ForegroundColor Red
    [void]$script:report.Add("`n> **Audit halted:** $_`n")
}

# ---------- Summary ----------
Write-Section "Summary"
$total = $script:counts.PASS + $script:counts.WARN + $script:counts.FAIL
Write-Host ("  Passed:   {0}" -f $script:counts.PASS)   -ForegroundColor Green
Write-Host ("  Warnings: {0}" -f $script:counts.WARN)   -ForegroundColor Yellow
Write-Host ("  Failed:   {0}" -f $script:counts.FAIL)   -ForegroundColor Red
Write-Host ("  Info:     {0}" -f $script:counts.INFO)   -ForegroundColor Gray
Write-Host ("  Total:    {0} checks" -f $total)

[void]$script:report.Add("**Passed:** $($script:counts.PASS)  ")
[void]$script:report.Add("**Warnings:** $($script:counts.WARN)  ")
[void]$script:report.Add("**Failed:** $($script:counts.FAIL)  ")
[void]$script:report.Add("**Info:** $($script:counts.INFO)  ")
[void]$script:report.Add("**Total checks:** $total`n")

if ($script:topFails.Count -gt 0) {
    [void]$script:report.Add("`n## Priority Findings`n")
    [void]$script:report.Add("Address these first — they are the most likely audit findings:`n")
    $i = 1
    foreach ($f in $script:topFails) {
        [void]$script:report.Add("$i. $f")
        $i++
    }
}

# ---------- Write report ----------
try {
    $script:report -join "`n" | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host ""
    Write-Host "Report written: $OutputPath" -ForegroundColor Cyan
} catch {
    Write-Host "Failed to write report: $_" -ForegroundColor Red
}

# Exit code: non-zero if any FAIL, useful for pipelines
if ($script:counts.FAIL -gt 0) { exit 1 } else { exit 0 }
