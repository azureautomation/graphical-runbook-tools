$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.ps1$'

Get-Module -Name $sut -All | Remove-Module -Force -ErrorAction Ignore
Import-Module -Name "$here\$sut.psm1" -Force -ErrorAction Stop

InModuleScope $sut {
    Describe "Show-GraphRunbookActivityTraces" {

        $TestJobId = New-Guid
        $TestResourceGroup = 'TestResourceGroupName'
        $TestAutomationAccount = 'TestAccountName'

        $TestJobOutputRecords =
            @(
                @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityStart",Time:"2016-11-23 23:04"}' } },
                @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityInput",Time:"2016-11-23 23:05",Values:{Data:{Input1:"A",Input2:"B"}}}' } },
                @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityOutput",Time:"2016-11-23 23:05"}' } },
                @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityEnd",Time:"2016-11-23 23:06",DurationSeconds:1.2}' } },
                @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityStart",Time:"2016-11-23 23:09"}' } },
                @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityOutput",Time:"2016-11-23 23:12",Values:{Data:[2,7,1]}}' } },
                @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityEnd",Time:"2016-11-23 23:13",DurationSeconds:7}' } }
            )

        function VerifyShowObjectInput($InputObject)
        {
            $InputObject | Should not be $null
            $InputObject | Measure-Object | % Count | Should be 1

            $InputObject.'Job ID' | Should be $TestJobId

            $ActivityExecutionInstances = $InputObject.'Activity execution instances'

            $ActivityExecutionInstances | Measure-Object | % Count | Should be 2

            $ActivityExecutionInstances[0].Activity | Should be 'Activity1'
            $ActivityExecutionInstances[0].Start | Should be (Get-Date '2016-11-23 23:04')
            $ActivityExecutionInstances[0].End | Should be (Get-Date '2016-11-23 23:06')
            $ActivityExecutionInstances[0].Duration | Should be ([System.TimeSpan]::FromSeconds(1.2))
            $ActivityExecutionInstances[0].Input | Should not be $null
            $ActivityExecutionInstances[0].Input.Input1 | Should be "A"
            $ActivityExecutionInstances[0].Input.Input2 | Should be "B"
            $ActivityExecutionInstances[0].Output | Should be $null

            $ActivityExecutionInstances[1].Activity | Should be 'Activity2'
            $ActivityExecutionInstances[1].Start | Should be (Get-Date '2016-11-23 23:09')
            $ActivityExecutionInstances[1].End | Should be (Get-Date '2016-11-23 23:13')
            $ActivityExecutionInstances[1].Duration | Should be ([System.TimeSpan]::FromSeconds(7))
            $ActivityExecutionInstances[1].Input | Should be $null
            $ActivityExecutionInstances[1].Output | Measure-Object | % Count | Should be 3
            $ActivityExecutionInstances[1].Output[0] | Should be 2
            $ActivityExecutionInstances[1].Output[1] | Should be 7
            $ActivityExecutionInstances[1].Output[2] | Should be 1
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
                    0..($TestJobOutputRecords.Length - 1)
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ([Parameter(ValueFromPipeline = $true)] $Id)

                process {
                    $TestJobOutputRecords[$Id]
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
                    $JobId | Should be $TestJobId > $null

                    0..($TestJobOutputRecords.Length - 1)
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ([Parameter(ValueFromPipeline = $true)] $Id)

                process {
                    $TestJobOutputRecords[$Id]
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

    Describe "Convert-GraphRunbookToPsd1" {
        Context "When GraphRunbook provided" {
            $AuthoringSdkDir = 'C:\Program Files (x86)\Microsoft Azure Automation Graphical Authoring SDK'
            Add-Type -Path $AuthoringSdkDir\Orchestrator.GraphRunbook.Model.dll

            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            $ActivityA = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity A'
            $ActivityA.Process = "'Hello'"
            $Runbook.AddActivity($ActivityA)

            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Get-Date'
            $ActivityB = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList 'Activity B', $CommandActivityType
            $ActivityB.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $ActivityB.Parameters.Add("Parameter1", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Value 1'))
            $ActivityB.Parameters.Add("Parameter2", (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Activity A'))
            $Runbook.AddActivity($ActivityB)

            $LinkAtoB = New-Object Orchestrator.GraphRunbook.Model.Link -ArgumentList $ActivityA, $ActivityB, Sequence
            $LinkAtoB.Condition = '$ActivityOutput[''A''].Count -gt 0'
            $Runbook.AddLink($LinkAtoB)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Comments = @(
)

OutputTypes = @(
)

Activities = @(
    @{
        Name = 'Activity A'
        Type = 'Code'
        Process = { 'Hello' }
    }
    @{
        Name = 'Activity B'
        Type = 'Command'
        CommandName = 'Get-Date'
        Parameters = @{
            Parameter1 = 'Value 1'
            Parameter2 = @{
                SourceType = 'ActivityOutput'
                Activity = 'Activity A'
            }
        }
    }
)

Links = @(
    @{
        From = 'Activity A'
        To = 'Activity B'
        Type = 'Sequence'
        Condition = { `$ActivityOutput['A'].Count -gt 0 }
    }
)

}

"@
            }
        }
    }
}
