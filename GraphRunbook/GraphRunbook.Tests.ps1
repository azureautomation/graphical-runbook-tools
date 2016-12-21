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
        $AuthoringSdkDir = 'C:\Program Files (x86)\Microsoft Azure Automation Graphical Authoring SDK'
        Add-Type -Path $AuthoringSdkDir\Orchestrator.GraphRunbook.Model.dll

        Context "When GraphRunbook is empty" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

}

"@
            }
        }

        Context "When GraphRunbook contains Code activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Activity = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity name'
            $Activity.Description = 'Activity description'
            $Activity.Begin = "'Begin code block'"
            $Activity.Process = "'Process code block'"
            $Activity.End = "'End code block'"
            $Activity.CheckpointAfter = $true
            $Activity.ExceptionsToErrors = $true
            $Activity.LoopExitCondition = '$RetryData.NumberOfAttempts -gt 5'
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'Code'
        Begin = {
            'Begin code block'
        }
        Process = {
            'Process code block'
        }
        End = {
            'End code block'
        }
        CheckpointAfter = `$true
        ExceptionsToErrors = `$true
        LoopExitCondition = {
            `$RetryData.NumberOfAttempts -gt 5
        }
        PositionX = 12
        PositionY = 456
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains Command activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Do-Something'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList 'Activity name', $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $Activity.Parameters.Add("Parameter1", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Value 1'))
            $Activity.Parameters.Add("Parameter2", (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Activity A'))
            $Activity.Parameters.Add("Parameter3", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList @($null)))
            $Activity.Description = 'Activity description'
            $Activity.CheckpointAfter = $true
            $Activity.ExceptionsToErrors = $true
            $Activity.LoopExitCondition = '$RetryData.NumberOfAttempts -gt 5'
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'Command'
        CommandName = 'Do-Something'
        Parameters = @{
            Parameter1 = 'Value 1'
            Parameter2 = @{
                SourceType = 'ActivityOutput'
                Activity = 'Activity A'
            }
            Parameter3 = `$null
        }
        CheckpointAfter = `$true
        ExceptionsToErrors = `$true
        LoopExitCondition = {
            `$RetryData.NumberOfAttempts -gt 5
        }
        PositionX = 12
        PositionY = 456
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains InvokeRunbook activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $InvokeRunbookActivityType = New-Object Orchestrator.GraphRunbook.Model.InvokeRunbookActivityType
            $InvokeRunbookActivityType.CommandName = 'Do-Something'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.InvokeRunbookActivity -ArgumentList 'Activity name', $InvokeRunbookActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $Activity.Parameters.Add("Parameter1", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Value 1'))
            $Activity.Parameters.Add("Parameter2", (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Activity A'))
            $Activity.Parameters.Add("Parameter3", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList @($null)))
            $Activity.Description = 'Activity description'
            $Activity.CheckpointAfter = $true
            $Activity.ExceptionsToErrors = $true
            $Activity.LoopExitCondition = '$RetryData.NumberOfAttempts -gt 5'
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'InvokeRunbook'
        CommandName = 'Do-Something'
        Parameters = @{
            Parameter1 = 'Value 1'
            Parameter2 = @{
                SourceType = 'ActivityOutput'
                Activity = 'Activity A'
            }
            Parameter3 = `$null
        }
        CheckpointAfter = `$true
        ExceptionsToErrors = `$true
        LoopExitCondition = {
            `$RetryData.NumberOfAttempts -gt 5
        }
        PositionX = 12
        PositionY = 456
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains Junction activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Activity = New-Object Orchestrator.GraphRunbook.Model.JunctionActivity -ArgumentList 'Activity name'
            $Activity.Description = 'Activity description'
            $Activity.CheckpointAfter = $true
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'Junction'
        CheckpointAfter = `$true
        PositionX = 12
        PositionY = 456
    }
)

}

"@
            }
        }

        function CreateRunbookWithCommandActivityWithParameter($ActivityName, $CommandName, $ParameterName, $ValueDescriptor)
        {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = $CommandName
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList $ActivityName, $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $Activity.Parameters.Add($ParameterName, $ValueDescriptor)
            [void]$Runbook.AddActivity($Activity)
            $Runbook
        }

        Context "When GraphRunbook contains Command activity with ConstantValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter -ActivityName 'Activity name' -CommandName 'Do-Something' -ParameterName 'ParameterName' `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Parameter value')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Type = 'Command'
        CommandName = 'Do-Something'
        Parameters = @{
            ParameterName = 'Parameter value'
        }
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains Command activity with ActivityOutputValueDescriptor (activity name only)" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter -ActivityName 'Activity name' -CommandName 'Do-Something' -ParameterName 'ParameterName' `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Source activity')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Type = 'Command'
        CommandName = 'Do-Something'
        Parameters = @{
            ParameterName = @{
                SourceType = 'ActivityOutput'
                Activity = 'Source activity'
            }
        }
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains activities, links, output types, and comments" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            $Comment1 = New-Object Orchestrator.GraphRunbook.Model.Comment -ArgumentList 'First comment'
            $Comment1.Text = 'First comment text'
            $Runbook.AddComment($Comment1)
            $Comment2 = New-Object Orchestrator.GraphRunbook.Model.Comment -ArgumentList 'Second comment'
            $Comment2.Text = 'Second comment text'
            $Runbook.AddComment($Comment2)

            $Runbook.AddOutputType('First output type');
            $Runbook.AddOutputType('Second output type');

            $ActivityA = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity A'
            $ActivityA.Process = "'Hello'"
            $Runbook.AddActivity($ActivityA)

            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Get-Date'
            $ActivityB = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList 'Activity B', $CommandActivityType
            $ActivityB.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $ActivityB.Parameters.Add("Parameter1", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Value 1'))
            $ActivityB.Parameters.Add("Parameter2", (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Activity A'))
            $ActivityB.Parameters.Add("Parameter3", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList @($null)))
            $Runbook.AddActivity($ActivityB)

            $LinkAtoB = New-Object Orchestrator.GraphRunbook.Model.Link -ArgumentList $ActivityA, $ActivityB, Sequence
            $LinkAtoB.Condition = '$ActivityOutput[''A''].Count -gt 0'
            $Runbook.AddLink($LinkAtoB)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPsd1 -Runbook $Runbook

                $Text | Should be @"
@{

Comments = @(
    @{
        Name = 'First comment'
        Text = 'First comment text'
    }
    @{
        Name = 'Second comment'
        Text = 'Second comment text'
    }
)

OutputTypes = @(
    'First output type'
    'Second output type'
)

Activities = @(
    @{
        Name = 'Activity A'
        Type = 'Code'
        Process = {
            'Hello'
        }
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
            Parameter3 = `$null
        }
    }
)

Links = @(
    @{
        From = 'Activity A'
        To = 'Activity B'
        Type = 'Sequence'
        Condition = {
            `$ActivityOutput['A'].Count -gt 0
        }
    }
)

}

"@
            }
        }
    }
}
