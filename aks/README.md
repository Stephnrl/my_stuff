# AKS Safe Upgrade — Composite GitHub Action

Safely upgrades an AKS cluster across Kubernetes minor versions using a phased
approach: control plane first, then node pools one at a time, with health checks
between each step.

## Repo Structure

```
aks-upgrade-action/
├── action.yml                          # Composite action definition
├── src/
│   └── entrypoint.ps1                  # Action entry point
├── AKSUpgrade/
│   ├── AKSUpgrade.psd1                 # Module manifest
│   ├── AKSUpgrade.psm1                 # Module loader (dot-sources Public/Private)
│   ├── Public/
│   │   ├── Get-AKSClusterInfo.ps1      # Query cluster version & node pools
│   │   ├── Get-AKSUpgradePath.ps1      # Compute hop-by-hop upgrade path
│   │   ├── Resolve-AKSPatchVersion.ps1 # Find highest available patch version
│   │   ├── Test-AKSClusterHealth.ps1   # Validate nodes & pods
│   │   ├── Invoke-AKSControlPlaneUpgrade.ps1
│   │   ├── Invoke-AKSNodePoolUpgrade.ps1
│   │   └── Invoke-AKSClusterUpgrade.ps1  # Full orchestrator
│   ├── Private/
│   │   ├── Write-Log.ps1               # Logging helpers (GitHub Actions aware)
│   │   └── Invoke-AzCli.ps1            # az CLI wrapper with error handling
│   └── Tests/
│       ├── Get-AKSUpgradePath.Tests.ps1
│       ├── Resolve-AKSPatchVersion.Tests.ps1
│       ├── Test-AKSClusterHealth.Tests.ps1
│       └── Invoke-AKSClusterUpgrade.Tests.ps1
├── examples/
│   └── workflow.yml                    # Sample consuming workflow
└── README.md
```

## How It Works

1. Queries the current cluster version and available upgrades
2. Computes the hop-by-hop path (AKS requires one minor version at a time)
3. For each hop:
   - Resolves the highest available non-preview patch version
   - Upgrades the control plane
   - Validates cluster health (nodes Ready, kube-system pods healthy)
   - Upgrades each node pool sequentially with configurable max-surge
   - Validates health again after each node pool

## Usage as a GitHub Action

```yaml
- uses: your-org/internal-actions/aks-upgrade-action@main
  with:
    resource_group: "my-rg"
    cluster_name: "my-aks"
    target_version: "1.33"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `resource_group` | ✅ | — | Azure Resource Group |
| `cluster_name` | ✅ | — | AKS cluster name |
| `target_version` | ✅ | — | Target K8s minor version (e.g., `1.33`) |
| `max_surge` | ❌ | `1` | Extra nodes during rolling upgrade |
| `validation_wait` | ❌ | `120` | Seconds to wait between steps |
| `fail_on_workload_issues` | ❌ | `false` | Fail if non-system pods are unhealthy |

### Outputs

| Output | Description |
|--------|-------------|
| `status` | `completed`, `skipped`, or `failed` |
| `starting_version` | Version before upgrade |
| `final_version` | Version after upgrade |
| `upgrade_path` | Comma-separated hops (e.g., `1.32,1.33`) |

## Usage as a PowerShell Module

```powershell
Import-Module ./AKSUpgrade

# Full orchestrated upgrade
Invoke-AKSClusterUpgrade -ResourceGroupName "my-rg" -ClusterName "my-aks" -TargetVersion "1.33"

# Individual functions
$info = Get-AKSClusterInfo -ResourceGroupName "my-rg" -ClusterName "my-aks"
$path = Get-AKSUpgradePath -CurrentVersion $info.KubernetesVersion -TargetVersion "1.33"
Test-AKSClusterHealth
Test-AKSClusterHealth -FailOnWorkloadIssues
```

## Running Tests

```powershell
# Install Pester if needed
Install-Module -Name Pester -MinimumVersion 5.0 -Force

# Run all tests
Invoke-Pester ./AKSUpgrade/Tests -Output Detailed

# Run a specific test file
Invoke-Pester ./AKSUpgrade/Tests/Get-AKSUpgradePath.Tests.ps1 -Output Detailed
```

## Prerequisites

- **Azure CLI** authenticated (`az login`)
- **kubectl** available and configured (`az aks get-credentials`)
- **PowerShell 7+** (pre-installed on GitHub-hosted runners)
- Service principal / managed identity needs **Azure Kubernetes Service Contributor** role
- For GitHub Actions: configure Azure OIDC federated credentials and set `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` as repo secrets

## Module Design

**Public functions** are individually exported and can be composed for custom workflows. **Private functions** (`Write-Log.ps1`, `Invoke-AzCli.ps1`) are internal helpers not exposed outside the module. The `.psm1` auto-discovers and dot-sources everything from `Public/` and `Private/` directories — adding a new function is as simple as dropping a `.ps1` file in the right folder.

All public upgrade functions support `-WhatIf` via `SupportsShouldProcess`, so you can dry-run individual operations.
