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

Export-ModuleMember -Function Show-GraphRunbookActivityTraces
