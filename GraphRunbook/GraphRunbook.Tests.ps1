$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.ps1$'

Get-Module -Name $sut -All | Remove-Module -Force -ErrorAction Ignore
Import-Module -Name "$here\$sut.psm1" -Force -ErrorAction Stop

InModuleScope $sut {
    Describe "Show-GraphRunbookActivityTraces" {

        $TestJobId = New-Guid
        $TestResourceGroup = 'TestResourceGroupName'
        $TestAutomationAccount = 'TestAccountName'

        function CreateTestJobOutputRecord($Id)
        {
            switch ($Id) {
                1 { @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityStart",Time:"2016-11-23 23:04"}' } } }
                2 { @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityInput",Time:"2016-11-23 23:05",Values:{Data:{Input1:"A",Input2:"B"}}}' } } }
                2 { @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityOutput",Time:"2016-11-23 23:05"}' } } }
                3 { @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityEnd",Time:"2016-11-23 23:06",DurationSeconds:1.2}' } } }

                4 { @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityStart",Time:"2016-11-23 23:09"}' } } }
                5 { @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityOutput",Time:"2016-11-23 23:12",Values:{Data:[2,7,1]}}' } } }
                6 { @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityEnd",Time:"2016-11-23 23:13",DurationSeconds:7}' } } }
            }
        }

        function VerifyShowObjectInput($InputObject)
        {
            $InputObject | Should not be $null
            $InputObject | Measure-Object | % Count | Should be 2

            $InputObject[0].Activity | Should be 'Activity1'
            $InputObject[0].Start | Should be (Get-Date '2016-11-23 23:04')
            $InputObject[0].End | Should be (Get-Date '2016-11-23 23:06')
            $InputObject[0].Duration | Should be ([System.TimeSpan]::FromSeconds(1.2))
            $InputObject[0].Input | Should not be $null
            $InputObject[0].Input.Input1 | Should be "A"
            $InputObject[0].Input.Input2 | Should be "B"
            $InputObject[0].Output | Should be $null

            $InputObject[1].Activity | Should be 'Activity2'
            $InputObject[1].Start | Should be (Get-Date '2016-11-23 23:09')
            $InputObject[1].End | Should be (Get-Date '2016-11-23 23:13')
            $InputObject[1].Duration | Should be ([System.TimeSpan]::FromSeconds(7))
            $InputObject[1].Input | Should be $null
            $InputObject[1].Output | Measure-Object | % Count | Should be 3
            $InputObject[1].Output[0] | Should be 2
            $InputObject[1].Output[1] | Should be 7
            $InputObject[1].Output[2] | Should be 1
        }

        Context "When Graph Runbook activity traces exist and job ID is known" {
            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($JobId -eq $TestJobId) -and
                    ($Stream -eq 'Verbose')
                } `
                -MockWith {
                    1..6
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ([Parameter(ValueFromPipeline = $true)] $Id)

                process {
                    CreateTestJobOutputRecord -Id $Id
                }
            }

            Mock Show-Object -Verifiable `
                -MockWith {
                    VerifyShowObjectInput -InputObject $InputObject
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -JobId $TestJobId

            It "Shows Graph Runbook activity traces" {
                Assert-VerifiableMocks
            }
        }

        Context "When Graph Runbook activity traces exist and runbook name is known" {
            $TestRunbookName = 'TestRunbookName'

            Mock Get-AzureRmAutomationJob -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($RunbookName -eq $TestRunbookName)
                } `
                -MockWith {
                    $LatestJobStartTime = Get-Date
                    New-Object PSObject -Property @{ StartTime = $LatestJobStartTime - [System.TimeSpan]::FromSeconds(1); JobId = New-Guid }
                    New-Object PSObject -Property @{ StartTime = $LatestJobStartTime; JobId = $TestJobId }
                    New-Object PSObject -Property @{ StartTime = $LatestJobStartTime - [System.TimeSpan]::FromSeconds(2); JobId = New-Guid }
                }

            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($Stream -eq 'Verbose')
                } `
                -MockWith {
                    $JobId | Should be $TestJobId
                    1..6
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ([Parameter(ValueFromPipeline = $true)] $Id)

                process {
                    CreateTestJobOutputRecord -Id $Id
                }
            }

            Mock Show-Object -Verifiable `
                -MockWith {
                    VerifyShowObjectInput -InputObject $InputObject
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -RunbookName $TestRunbookName

            It "Shows Graph Runbook activity traces" {
                Assert-VerifiableMocks
            }
        }

        Context "When no Graph Runbook activity traces" {
            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($JobId -eq $TestJobId) -and
                    ($Stream -eq 'Verbose')
                } `
                -MockWith {
                    1
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ( [Parameter(ValueFromPipeline = $true)] $Id)

                @{ Value = @{ Message = 'Regular verbose message' } }
            }

            Mock Write-Error -Verifiable `
                -MockWith {
                    $Message | Should be ('No activity traces found. Make sure activity tracing and ' +
                                          'logging Verbose stream are enabled in the runbook configuration.')
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -JobId $TestJobId

            It "Shows 'no activity traces' message" {
                Assert-VerifiableMocks
            }
        }

        Context "When no Verbose output" {
            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($JobId -eq $TestJobId) -and
                    ($Stream -eq 'Verbose')
                }

            Mock Get-AzureRmAutomationJobOutputRecord

            Mock Write-Error -Verifiable `
                -MockWith {
                    $Message | Should be ('No activity traces found. Make sure activity tracing and ' +
                                          'logging Verbose stream are enabled in the runbook configuration.')
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -JobId $TestJobId

            It "Shows 'no activity traces' message" {
                Assert-VerifiableMocks
                Assert-MockCalled Get-AzureRmAutomationJobOutputRecord -Times 0
            }
        }
    }
}
