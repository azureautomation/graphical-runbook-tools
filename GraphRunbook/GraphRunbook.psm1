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

function Show-GraphRunbookActivityTraces(
    [Parameter(Mandatory = $true)]
    [string]
    $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]
    $AutomationAccountName,

    [Parameter(Mandatory = $true)]
    [string]
    $JobId
)
{
    $GraphTraces = GetGraphTraces $ResourceGroupName $AutomationAccountName $JobId
    $ActivityExecutionInstances = GetActivityExecutionInstances $GraphTraces
    if ($ActivityExecutionInstances)
    {
        Show-Object -InputObject $ActivityExecutionInstances
    }
    else
    {
        Write-Error -Message ('No activity traces found. Make sure activity tracing and ' +
                              'logging Verbose stream are enabled in the runbook configuration.')
    }
}

Export-ModuleMember -Function Show-GraphRunbookActivityTraces
