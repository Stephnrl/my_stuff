<#
.SYNOPSIS
    Pester v5 tests for the AAP module.
.DESCRIPTION
    Demonstrates how the module structure makes AAP interactions unit-testable
    without hitting a real controller. Run with:
        Invoke-Pester ./tests/AAP.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'AAP' 'AAP.psd1'
    Import-Module $modulePath -Force

    # Establish context without a real ping
    Connect-AAPController -BaseUrl 'https://aap.test' -Token 'fake-token' -SkipConnectionTest
}

Describe 'Resolve-AAPJobTemplate' {

    It 'returns numeric input unchanged' {
        # Numeric short-circuit shouldn't even hit the API
        Mock -ModuleName AAP Invoke-AAPRestMethod { throw 'should not be called' }
        Resolve-AAPJobTemplate -Identifier '42' | Should -Be 42
    }

    It 'resolves a unique name to its ID' {
        Mock -ModuleName AAP Invoke-AAPRestMethod {
            [pscustomobject]@{
                count   = 1
                results = @([pscustomobject]@{ id = 99; name = 'rhel9-configure' })
            }
        }
        Resolve-AAPJobTemplate -Identifier 'rhel9-configure' | Should -Be 99
    }

    It 'throws when name is ambiguous' {
        Mock -ModuleName AAP Invoke-AAPRestMethod {
            [pscustomobject]@{ count = 2; results = @() }
        }
        { Resolve-AAPJobTemplate -Identifier 'duplicate' } | Should -Throw '*got 2*'
    }

    It 'throws when name is not found' {
        Mock -ModuleName AAP Invoke-AAPRestMethod {
            [pscustomobject]@{ count = 0; results = @() }
        }
        { Resolve-AAPJobTemplate -Identifier 'nope' } | Should -Throw '*No AAP job template*'
    }
}

Describe 'Invoke-AAPJobTemplate' {

    It 'POSTs to the launch endpoint with extra_vars and limit' {
        Mock -ModuleName AAP Resolve-AAPJobTemplate { 42 }
        Mock -ModuleName AAP Invoke-AAPRestMethod {
            param($Path, $Method, $Body)
            $Path   | Should -Be '/api/controller/v2/job_templates/42/launch/'
            $Method | Should -Be 'POST'
            $Body.limit             | Should -Be 'vm-app01'
            $Body.extra_vars.cmmc_level | Should -Be '2'

            [pscustomobject]@{ id = 1234; status = 'pending' }
        }

        $result = Invoke-AAPJobTemplate `
            -JobTemplate '42' `
            -Limit 'vm-app01' `
            -ExtraVars @{ cmmc_level = '2' }

        $result.id     | Should -Be 1234
        $result.ui_url | Should -Match '/#/jobs/playbook/1234/output$'
    }

    It 'omits limit and inventory from payload when not provided' {
        Mock -ModuleName AAP Resolve-AAPJobTemplate { 42 }
        Mock -ModuleName AAP Invoke-AAPRestMethod {
            param($Path, $Method, $Body)
            $Body.PSObject.Properties.Name | Should -Not -Contain 'limit'
            $Body.PSObject.Properties.Name | Should -Not -Contain 'inventory'
            [pscustomobject]@{ id = 1; status = 'pending' }
        }

        Invoke-AAPJobTemplate -JobTemplate '42' | Out-Null
    }
}

Describe 'Wait-AAPJob' {

    It 'returns immediately when status is successful' {
        Mock -ModuleName AAP Get-AAPJob { [pscustomobject]@{ id = 1; status = 'successful' } }
        $job = Wait-AAPJob -Id 1 -PollIntervalSeconds 1
        $job.status | Should -Be 'successful'
    }

    It 'throws on failed status when FailOnJobFailure is true' {
        Mock -ModuleName AAP Get-AAPJob       { [pscustomobject]@{ id = 1; status = 'failed' } }
        Mock -ModuleName AAP Get-AAPJobStdout { 'TASK [foo] FAILED' }

        { Wait-AAPJob -Id 1 -PollIntervalSeconds 1 -FailOnJobFailure $true } |
            Should -Throw "*finished with status 'failed'*"
    }

    It 'returns the job on failure when FailOnJobFailure is false' {
        Mock -ModuleName AAP Get-AAPJob       { [pscustomobject]@{ id = 1; status = 'failed' } }
        Mock -ModuleName AAP Get-AAPJobStdout { 'log tail' }

        $job = Wait-AAPJob -Id 1 -PollIntervalSeconds 1 -FailOnJobFailure $false
        $job.status | Should -Be 'failed'
    }

    It 'progresses through running states before terminal' {
        $script:callCount = 0
        Mock -ModuleName AAP Get-AAPJob {
            $script:callCount++
            switch ($script:callCount) {
                1 { [pscustomobject]@{ id = 1; status = 'pending' } }
                2 { [pscustomobject]@{ id = 1; status = 'running' } }
                3 { [pscustomobject]@{ id = 1; status = 'successful' } }
            }
        }

        $job = Wait-AAPJob -Id 1 -PollIntervalSeconds 1
        $job.status        | Should -Be 'successful'
        $script:callCount  | Should -Be 3
    }
}
