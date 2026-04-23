# launch-aap-job (PowerShell)

GitHub composite action backed by a PowerShell module for interacting with Red Hat Ansible Automation Platform 2.5.

## Layout

```
launch-aap-job-pwsh/
├── action.yml                          # GHA composite action manifest (thin)
├── src/
│   └── entrypoint.ps1                  # GHA glue: env vars in, $GITHUB_OUTPUT out
├── AAP/                                # Module — usable independently of GHA
│   ├── AAP.psd1                        # Manifest (version, exports, requirements)
│   ├── AAP.psm1                        # Loader
│   ├── Public/                         # Exported cmdlets
│   │   ├── Connect-AAPController.ps1
│   │   ├── Invoke-AAPJobTemplate.ps1
│   │   ├── Get-AAPJob.ps1
│   │   ├── Get-AAPJobStdout.ps1
│   │   ├── Stop-AAPJob.ps1
│   │   ├── Wait-AAPJob.ps1
│   │   └── Resolve-AAPJobTemplate.ps1
│   └── Private/                        # Internal helpers
│       ├── Invoke-AAPRestMethod.ps1    # Auth, retry, error handling
│       └── Write-AAPLog.ps1            # GHA-aware logging
└── tests/
    └── AAP.Tests.ps1                   # Pester v5 — runs without an AAP instance
```

## Why this structure

The action.yml is a shim. All real logic lives in the `AAP/` module, which means:

- **Pester unit tests don't need AAP.** Mock `Invoke-AAPRestMethod` and you can exercise launch / poll / cancel logic against fixture data in CI.
- **Operators get a real cmdlet library.** Anyone who installs the module on their workstation can `Connect-AAPController` and use the same cmdlets the pipeline uses to debug failed jobs, query inventories, etc.
- **The GHA wrapper is replaceable.** If you later run this from Azure DevOps, GitLab, or a scheduled task, you keep the module — just write a new entrypoint.
- **Testability stays honest.** Bash scripts that grow past 50 lines almost never get tests. PowerShell modules with a Public/Private split tend to.

## Usage from a workflow

```yaml
- name: Checkout shared actions
  uses: actions/checkout@v4
  with:
    repository: your-org/gha-actions
    ref: v1.4.0
    path: .gha-actions
    token: ${{ secrets.INTERNAL_REPO_PAT }}

- name: Configure VM via AAP
  uses: ./.gha-actions/launch-aap-job-pwsh
  with:
    aap-url:      ${{ secrets.AAP_URL }}
    aap-token:    ${{ secrets.AAP_OAUTH_TOKEN }}
    job-template: ${{ vars.AAP_JT_RHEL9_CONFIGURE }}
    limit:        ${{ needs.terraform.outputs.vm_name }}
    extra-vars: |
      {
        "target_host":         "${{ needs.terraform.outputs.vm_name }}",
        "target_ip":           "${{ needs.terraform.outputs.vm_private_ip }}",
        "cmmc_level":          "2",
        "data_classification": "cui"
      }
    timeout-seconds: 1800
```

## Usage from a workstation

```powershell
Import-Module ./AAP/AAP.psd1
Connect-AAPController -BaseUrl 'https://aap.example.gov' -Token $env:AAP_TOKEN

# One-liner: launch and wait
Invoke-AAPJobTemplate -JobTemplate 'rhel9-configure' -Limit 'vm-app01' -ExtraVars @{
    cmmc_level = '2'
} | Wait-AAPJob -TimeoutSeconds 1800

# Triage a failed job
Get-AAPJobStdout -Id 12345 -Tail 100
```

## Runner requirements

- PowerShell 7.2+ (the module manifest enforces this — `pwsh` on default `ubuntu-*` runners satisfies it).
- Network reach to your AAP controller.

## Running the tests

```powershell
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0 -Force
Invoke-Pester ./tests/AAP.Tests.ps1 -Output Detailed
```

The tests don't need a real AAP — `Invoke-AAPRestMethod` is mocked at the module scope.

## Why a module per concern, not one giant script

Two reasons that pay off over time:

1. **Each cmdlet does one thing.** `Invoke-AAPJobTemplate` launches. `Wait-AAPJob` polls. `Stop-AAPJob` cancels. They compose via the pipeline. When you need a "launch but don't wait" workflow (fire-and-forget reconciliation jobs), you already have it — drop the `| Wait-AAPJob`.
2. **The module grows without action.yml growing.** Adding `Get-AAPInventory`, `Sync-AAPProject`, `Get-AAPWorkflowJob` is a new file in `Public/` and a line in the manifest. The composite action stays at one entrypoint.
