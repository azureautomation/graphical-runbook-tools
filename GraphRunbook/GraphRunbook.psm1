function ExpectEvent($GraphTraceRecord, $ExpectedEventType, $ExpectedActivityName)
{
    $ActualEventType = $GraphTraceRecord.Event
    $ActualActivityName = $GraphTraceRecord.Activity

    if (($ActualEventType -ne $ExpectedEventType) -or
        (($ExpectedActivityName -ne $null) -and ($ActualActivityName -ne $ExpectedActivityName)))
    {
        throw "Unexpected event $ActualEventType/$ActualActivityName (expected $ExpectedEventType/$ExpectedActivityName)"
    }
}

function GetGraphTraces($ResourceGroupName, $AutomationAccountName, $JobId)
{
    Write-Verbose "Retrieving traces for job $JobId..."

    $GraphTracePrefix = "GraphTrace:"

    Get-AzureRmAutomationJobOutput `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Id $JobId `
            -Stream Verbose |
        Get-AzureRmAutomationJobOutputRecord |
        % Value |
        % Message |
        ?{ $_.StartsWith($GraphTracePrefix) } |
        %{ $_.Substring($GraphTracePrefix.Length) } |
        ConvertFrom-Json
}

function GetActivityExecutionInstances($GraphTraces)
{
    $GraphTracePos = 0

    while ($GraphTracePos -lt $GraphTraces.Count)
    {
        ExpectEvent $GraphTraces[$GraphTracePos] 'ActivityStart'
        $Activity = $GraphTraces[$GraphTracePos].Activity
        $Start = $GraphTraces[$GraphTracePos].Time
        $GraphTracePos += 1

        $Input = $null
        if ($GraphTraces[$GraphTracePos].Event -eq 'ActivityInput')
        {
            ExpectEvent $GraphTraces[$GraphTracePos] 'ActivityInput' $Activity
            $Input = $GraphTraces[$GraphTracePos].Values.Data
            $GraphTracePos += 1
        }

        ExpectEvent $GraphTraces[$GraphTracePos] 'ActivityOutput' $Activity
        $Output = $GraphTraces[$GraphTracePos].Values.Data
        $GraphTracePos += 1

        ExpectEvent $GraphTraces[$GraphTracePos] 'ActivityEnd' $Activity
        $End = $GraphTraces[$GraphTracePos].Time
        $DurationSeconds = $GraphTraces[$GraphTracePos].DurationSeconds
        $GraphTracePos += 1

        $ActivityExecution = New-Object -TypeName PsObject
        Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name Activity -Value $Activity
        Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name Start -Value (Get-Date $Start)
        Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name End -Value (Get-Date $End)
        Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name Duration -Value ([System.TimeSpan]::FromSeconds($DurationSeconds))
        if ($Input)
        {
            Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name Input -Value $Input
        }
        Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name Output -Value $Output

        $ActivityExecution
    }
}

function GetLatestJobByRunbookName($ResourceGroupName, $AutomationAccountName, $RunbookName)
{
    Write-Verbose "Looking for the latest job for runbook $RunbookName..."

    Get-AzureRmAutomationJob `
                -RunbookName $RunbookName `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName |
        sort StartTime -Descending |
        select -First 1
}

function Show-GraphRunbookActivityTraces
{
<#

.SYNOPSIS

Shows graphical runbook activity traces for an Azure Automation job


.DESCRIPTION

Graphical runbook activity tracing data is extremely helpful when testing and troubleshooting graphical runbooks in Azure Automation. Specifically, it can help the user determine the execution order of activities, any activity start and finish time, and any activity input and output data. Azure Automation saves this data encoded in JSON in the job Verbose stream.

Even though this data is very valuable, it may not be directly human-readable in the raw format, especially when activities input and output large and complex objects. Show-GraphRunbookActivityTraces command simplifies this task. It retrieves activity tracing data from a specified Azure Automation job, then parses and displays this data in a user-friendly tree structure:

    - Activity execution instance 1
        - Activity name, start time, end time, duration, etc.
        - Input
            - <parameter name> : <object>
            - <parameter name> : <object>
            ...
        - Output
            - <output object 1>
            - <output object 2>
            ...
    - Activity execution instance 2
    ...

Prerequisites
=============

1. The following modules are required:
        AzureRm.Automation
        PowerShellCookbook

   Run the following commands to install these modules from the PowerShell gallery:
        Install-Module -Name AzureRM.Automation
        Install-Module -Name PowerShellCookbook

2. Make sure you add an authenticated Azure account (for example, use Add-AzureRmAcccount cmdlet) before invoking Show-GraphRunbookActivityTraces.

3. In the Azure Portal, enable activity-level tracing *and* verbose logging for a graphical runbook:
    - Runbook Settings -> Logging and tracing
        - Logging verbose records: *On*
        - Trace level: *Basic* or *Detailed*


.PARAMETER ResourceGroupName

Azure Resource Group name


.PARAMETER AutomationAccountName

Azure Automation Account name


.PARAMETER JobId

Azure Automation graphical runbook job ID


.EXAMPLE

Show-GraphRunbookActivityTraces -ResourceGroupName myresourcegroup -AutomationAccountName myautomationaccount -JobId b15d38a1-ddea-49d1-bd90-407f66f282ef


.LINK

Source code: https://github.com/azureautomation/graphical-runbook-tools


.LINK

Azure Automation: https://azure.microsoft.com/services/automation

#>
    [CmdletBinding()]

    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = "ByJobId")]
        [Alias('Id')]
        [guid]
        $JobId,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = "ByRunbookName")]
        [string]
        $RunbookName,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]
        $AutomationAccountName
    )

    process
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            "ByJobId"
            {
                $GraphTraces = GetGraphTraces $ResourceGroupName $AutomationAccountName $JobId
            }

            "ByRunbookName"
            {
                $Job = GetLatestJobByRunbookName `
                            -RunbookName $RunbookName `
                            -ResourceGroupName $ResourceGroupName `
                            -AutomationAccountName $AutomationAccountName

                if ($Job)
                {
                    $JobId = $Job.JobId
                    $GraphTraces = GetGraphTraces $ResourceGroupName $AutomationAccountName $JobId
                }
                else
                {
                    Write-Error -Message "No job found for runbook $RunbookName."
                }
            }
        }

        $ActivityExecutionInstances = GetActivityExecutionInstances $GraphTraces
        if ($ActivityExecutionInstances)
        {
            $ObjectToShow = New-Object PsObject -Property @{
                'Job ID' = $JobId
                'Activity execution instances' = $ActivityExecutionInstances
            }

            Show-Object -InputObject @($ObjectToShow)
        }
        else
        {
            Write-Error -Message ('No activity traces found. Make sure activity tracing and ' +
                                  'logging Verbose stream are enabled in the runbook configuration.')
        }
    }
}

function Get-ActivityText([Orchestrator.GraphRunbook.Model.Activity]$Activity)
{
    "    @{`r`n        Name = '$($Activity.Name)'`r`n    }`r`n"
}

function Get-ActivitiesText([Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook)
{
    $Result = ''
    foreach ($Activity in $Runbook.Activities)
    {
        $Result += "$(Get-ActivityText $Activity)"
    }

    $Result
}

function Get-Indent($IndentLevel)
{
    ' ' * $IndentLevel * 4
}

function IsDefaultValue($Value)
{
    ($Value -eq $null) -or
    (($Value -is [int]) -and ($Value -eq 0)) -or
    (($Value -is [bool]) -and ($Value -eq $false)) -or
    (($Value -is [Orchestrator.GraphRunbook.Model.Condition]) -and
        ($Value.Mode -eq [Orchestrator.GraphRunbook.Model.ConditionMode]::Disabled) -and
        ([string]::IsNullOrEmpty($Value.Expression)))
}

function Get-ActivityById([Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook, $ActivityId)
{
    $Result = $Runbook.Activities | %{ $_ } | ?{ $_.EntityId -eq $ActivityId }
    if (-not $Result)
    {
        throw "Cannot find activity by entity ID: $ActivityId"
    }
    $Result
}

function ConvertListToPsd($IndentLevel, [System.Collections.IList]$Value)
{
        if ($Value.Count -eq 0)
        {
            '@()'
        }
        else
        {
            $Result = "@(`r`n"
            $NextIndentLevel = $IndentLevel + 1
            foreach ($Item in $Value)
            {
                $Result += "$(Get-Indent $NextIndentLevel)$(ConvertValueToPsd -IndentLevel $NextIndentLevel -Value $Item)`r`n"
            }
            $Result += "$(Get-Indent $IndentLevel))"
            $Result
        }
}

function ConvertDictionaryToPsd($IndentLevel, $Value)
{
    $Result = "@{`r`n"
    $NextIndentLevel = $IndentLevel + 1
    foreach ($Entry in $Value.GetEnumerator())
    {
        if (-not (IsDefaultValue $Entry.Value))
        {
            $Result += "$(ConvertNamedValueToPsd -IndentLevel $NextIndentLevel -Name $Entry.Key -Value $Entry.Value)`r`n"
        }
    }
    $Result += "$(Get-Indent $IndentLevel)}"
    $Result
}

function ConvertScriptBlockToPsd($IndentLevel, [scriptblock]$Value)
{
    $NextIndentLevel = $IndentLevel + 1
    "{`r`n$(Get-Indent $NextIndentLevel)$Value`r`n$(Get-Indent $IndentLevel)}"
}

function ConvertValueToPsd($IndentLevel, $Value)
{
    if ($Value -eq $null)
    {
        '$null'
    }
    elseif ($Value -is [System.Collections.IList])
    {
        ConvertListToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [scriptblock])
    {
        ConvertScriptBlockToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [hashtable])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [System.Collections.Specialized.OrderedDictionary])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.WorkflowScriptActivity])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            Name = $Value.Name
            Description = $Value.Description
            Type = 'Code'
            Begin = $(if ($Value.Begin) { [scriptblock]::Create($Value.Begin) })
            Process = $(if ($Value.Process) { [scriptblock]::Create($Value.Process) })
            End = $(if ($Value.End) { [scriptblock]::Create($Value.End) })
            CheckpointAfter = $Value.CheckpointAfter
            ExceptionsToErrors = $Value.ExceptionsToErrors
            LoopExitCondition = $Value.LoopExitCondition
            PositionX = $Value.PositionX
            PositionY = $Value.PositionY
        })
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.CommandActivity])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            Name = $Value.Name
            Description = $Value.Description
            Type = 'Command'
            CommandName = $Value.CommandType.CommandName
            Parameters = $Value.Parameters
            CheckpointAfter = $Value.CheckpointAfter
            ExceptionsToErrors = $Value.ExceptionsToErrors
            LoopExitCondition = $Value.LoopExitCondition
            PositionX = $Value.PositionX
            PositionY = $Value.PositionY
        })
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.InvokeRunbookActivity])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            Name = $Value.Name
            Description = $Value.Description
            Type = 'InvokeRunbook'
            CommandName = $Value.RunbookActivityType.CommandName
            Parameters = $Value.Parameters
            CheckpointAfter = $Value.CheckpointAfter
            ExceptionsToErrors = $Value.ExceptionsToErrors
            LoopExitCondition = $Value.LoopExitCondition
            PositionX = $Value.PositionX
            PositionY = $Value.PositionY
        })
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.JunctionActivity])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            Name = $Value.Name
            Description = $Value.Description
            Type = 'Junction'
            CheckpointAfter = $Value.CheckpointAfter
            PositionX = $Value.PositionX
            PositionY = $Value.PositionY
        })
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.ActivityParameters])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.ConstantValueDescriptor])
    {
        ConvertValueToPsd -IndentLevel $IndentLevel -Value $Value.Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            SourceType = 'ActivityOutput'
            Activity = $Value.ActivityName
        })
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.Link])
    {
        $FromActivity = Get-ActivityById $Runbook $Value.SourceActivityEntityId
        $ToActivity = Get-ActivityById $Runbook $Value.DestinationActivityEntityId

        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            From = $FromActivity.Name
            To = $ToActivity.Name
            Type = $Value.LinkType
            Condition = $Value.Condition
        })
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.Condition])
    {
        if ($Value.Mode -eq [Orchestrator.GraphRunbook.Model.ConditionMode]::Enabled)
        {
            ConvertValueToPsd -IndentLevel $IndentLevel -Value ([scriptblock]::Create($Value.Expression))
        }
        else
        {
            ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
                Mode = $Value.Mode
                Expression = [scriptblock]::Create($Value.Expression)
            })
        }
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.Comment])
    {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            Name = $Value.Name
            Text = $Value.Text
        })
    }
    elseif ($Value -is [int])
    {
        "$Value"
    }
    elseif ($Value -is [bool])
    {
        if ($Value)
        {
            '$true'
        }
        else
        {
            '$false'
        }
    }
    else
    {
        "'$([Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value.ToString()))'"
    }
}

function ConvertNamedValueToPsd($IndentLevel, $Name, $Value)
{
    "$(Get-Indent $IndentLevel)$Name = $(ConvertValueToPsd -IndentLevel $IndentLevel -Value $Value)"
}

function ConvertOptionalSectionToPsd($Name, $Data)
{
    if ($Data)
    {
        "$(ConvertNamedValueToPsd -IndentLevel 0 -Name $Name -Value $Data)`r`n`r`n"
    }
    else
    {
        ''
    }
}

function Convert-GraphRunbookToPsd1
{
    param(
        [Parameter(Mandatory = $true)]
        [Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook
    )

    $Result = "@{`r`n`r`n"
    $Result += ConvertOptionalSectionToPsd -Name Comments -Data $Runbook.Comments
    $Result += ConvertOptionalSectionToPsd -Name OutputTypes -Data $Runbook.OutputTypes
    $Result += ConvertOptionalSectionToPsd -Name Activities -Data $Runbook.Activities
    $Result += ConvertOptionalSectionToPsd -Name Links -Data $Runbook.Links
    $Result += "}`r`n"

    $Result
}

Export-ModuleMember -Function Show-GraphRunbookActivityTraces
Export-ModuleMember -Function Convert-GraphRunbookToPsd1
