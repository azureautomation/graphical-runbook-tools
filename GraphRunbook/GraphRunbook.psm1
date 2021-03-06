#region Show-GraphRunbookActivityTraces

function ExpectEvent($GraphTraceRecord, $ExpectedEventType, $ExpectedActivityName) {
    $ActualEventType = $GraphTraceRecord.Event
    $ActualActivityName = $GraphTraceRecord.Activity

    if (($ActualEventType -ne $ExpectedEventType) -or
            (($null -ne $ExpectedActivityName) -and ($ActualActivityName -ne $ExpectedActivityName))) {
        throw "Unexpected event $ActualEventType/$ActualActivityName (expected $ExpectedEventType/$ExpectedActivityName)"
    }
}

function GetGraphTraces($ResourceGroupName, $AutomationAccountName, $JobId) {
    Write-Verbose "Retrieving traces for job $JobId..."

    $GraphTracePrefix = "GraphTrace:"

    Get-AzureRmAutomationJobOutput `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Id $JobId `
            -Stream Verbose |
        Get-AzureRmAutomationJobOutputRecord |
        ForEach-Object Value |
        ForEach-Object Message |
        Where-Object { $_.StartsWith($GraphTracePrefix) } |
        ForEach-Object { $_.Substring($GraphTracePrefix.Length) } |
        ConvertFrom-Json
}

function GetActivityExecutionInstances($GraphTraces) {
    $GraphTracePos = 0

    while ($GraphTracePos -lt $GraphTraces.Count) {
        ExpectEvent $GraphTraces[$GraphTracePos] 'ActivityStart'
        $Activity = $GraphTraces[$GraphTracePos].Activity
        $Start = $GraphTraces[$GraphTracePos].Time
        $GraphTracePos += 1

        $Input = $null
        if ($GraphTraces[$GraphTracePos].Event -eq 'ActivityInput') {
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
        if ($Input) {
            Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name Input -Value $Input
        }
        Add-Member -InputObject $ActivityExecution -MemberType NoteProperty -Name Output -Value $Output

        $ActivityExecution
    }
}

function GetLatestJobByRunbookName($ResourceGroupName, $AutomationAccountName, $RunbookName) {
    Write-Verbose "Looking for the latest job for runbook $RunbookName..."

    Get-AzureRmAutomationJob `
                -RunbookName $RunbookName `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName |
        Sort-Object StartTime -Descending |
        Select-Object -First 1
}

function Show-GraphRunbookActivityTraces {
<#
.SYNOPSIS
Shows graphical runbook activity traces for an Azure Automation job

.DESCRIPTION
Activity tracing data is extremely helpful when testing and troubleshooting graphical runbooks in Azure Automation: it shows the execution order of activities, activity start and finish time, activity input and output data, and more. Azure Automation saves this data encoded in JSON in the job Verbose stream. Even though this data is very valuable, the raw JSON format may be hard to read, especially when activities input and output large and complex objects. Show-GraphRunbookActivityTraces command retrieves activity tracing data and displays it in a user-friendly tree structure:

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

1. Make sure you add an authenticated Azure account (for example, use Add-AzureRmAcccount cmdlet) before invoking Show-GraphRunbookActivityTraces.

2. In the Azure Portal, enable activity-level tracing *and* verbose logging for a graphical runbook:
    - Runbook Settings -> Logging and tracing
        - Logging verbose records: *On*
        - Trace level: *Basic* or *Detailed*

3. Start the runbook and take note of the job ID.

.PARAMETER ResourceGroupName
Azure Resource Group name

.PARAMETER AutomationAccountName
Azure Automation Account name

.PARAMETER JobId
Azure Automation graphical runbook job ID

.PARAMETER RunbookName
Runbook name

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

    process {
        switch ($PSCmdlet.ParameterSetName) {
            "ByJobId" {
                $GraphTraces = GetGraphTraces $ResourceGroupName $AutomationAccountName $JobId
            }

            "ByRunbookName" {
                $Job = GetLatestJobByRunbookName `
                            -RunbookName $RunbookName `
                            -ResourceGroupName $ResourceGroupName `
                            -AutomationAccountName $AutomationAccountName

                if ($Job) {
                    $JobId = $Job.JobId
                    $GraphTraces = GetGraphTraces $ResourceGroupName $AutomationAccountName $JobId
                }
                else {
                    Write-Error -Message "No job found for runbook $RunbookName."
                }
            }
        }

        $ActivityExecutionInstances = GetActivityExecutionInstances $GraphTraces
        if ($ActivityExecutionInstances) {
            $ObjectToShow = New-Object PsObject -Property @{
                'Job ID' = $JobId
                'Activity execution instances' = $ActivityExecutionInstances
            }

            Show-Object -InputObject @($ObjectToShow)
        }
        else {
            Write-Error -Message ('No activity traces found. Make sure activity tracing and ' +
                                  'logging Verbose stream are enabled in the runbook configuration.')
        }
    }
}

#endregion

#region Convert-GraphRunbookToPowerShellData

function Get-ActivityById([Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook, $ActivityId) {
    $Result = $Runbook.Activities | ForEach-Object { $_ } | Where-Object { $_.EntityId -eq $ActivityId }
    if (-not $Result) {
        throw "Cannot find activity by entity ID: $ActivityId"
    }
    $Result
}

function Get-Indent($IndentLevel) {
    ' ' * $IndentLevel * 4
}

function NullIfPositionZeroZero([Orchestrator.GraphRunbook.Model.IPositionedEntity]$Value) {
    if (($Value.PositionX -eq 0) -and ($Value.PositionY -eq 0)) {
        $null
    }
    else {
        [System.Tuple]::Create($Value.PositionX, $Value.PositionY)
    }
}

function NullIfEmptyString($Value) {
    if ([string]::IsNullOrEmpty($Value)) {
        $null
    }
    else {
        $Value
    }
}

function NullIfEmptyDictionary($Value) {
    if (($null -eq $Value) -or ($Value.Count -eq 0)) {
        $null
    }
    else {
        $Value
    }
}

function IsDefaultValue($Value) {
    ($null -eq $Value) -or
    (($Value -is [bool]) -and ($Value -eq $false)) -or
    (($Value -is [Orchestrator.GraphRunbook.Model.Condition]) -and
        ($Value.Mode -eq [Orchestrator.GraphRunbook.Model.ConditionMode]::Disabled) -and
        ([string]::IsNullOrEmpty($Value.Expression))) -or
    (($Value -is [Orchestrator.GraphRunbook.Model.ExecutableView.LinkStreamType]) -and
        ($Value -eq [Orchestrator.GraphRunbook.Model.ExecutableView.LinkStreamType]::Output))
}

function CreateScriptBlockIfNotEmpty($Value)
{
    if ($Value) {
        [scriptblock]::Create($Value)
    }
    else {
        $null
    }
}

function ConvertListToPsd($IndentLevel, [System.Collections.IList]$Value) {
    if ($Value.Count -eq 0) {
        '@()'
    }
    else {
        $Result = "@(`r`n"
        $NextIndentLevel = $IndentLevel + 1
        foreach ($Item in $Value) {
            $Result += "$(Get-Indent $NextIndentLevel)$(ConvertValueToPsd -IndentLevel $NextIndentLevel -Value $Item)`r`n"
        }
        $Result += "$(Get-Indent $IndentLevel))"
        $Result
    }
}

function ConvertDictionaryToPsd($IndentLevel, [System.Collections.IDictionary]$Value) {
    $Result = "@{`r`n"
    $NextIndentLevel = $IndentLevel + 1
    foreach ($Entry in $Value.GetEnumerator()) {
        if (-not (IsDefaultValue $Entry.Value)) {
            $Result += "$(ConvertNamedValueToPsd -IndentLevel $NextIndentLevel -Name $Entry.Key -Value $Entry.Value)`r`n"
        }
    }
    $Result += "$(Get-Indent $IndentLevel)}"
    $Result
}

function ConvertTuple2IntToPsd($IndentLevel, [System.Tuple`2[[int], [int]]]$Value) {
    "$($Value.Item1), $($Value.Item2)"
}

function ConvertScriptBlockToPsd($IndentLevel, [scriptblock]$Value) {
    $NextIndentLevel = $IndentLevel + 1
    "{`r`n$(Get-Indent $NextIndentLevel)$Value`r`n$(Get-Indent $IndentLevel)}"
}

function GetActivityTypeName([Orchestrator.GraphRunbook.Model.ExecutableView.IActivity]$Activity)
{
    if ($Activity -is [Orchestrator.GraphRunbook.Model.WorkflowScriptActivity]) {
        'Code'
    }
    elseif ($Activity -is [Orchestrator.GraphRunbook.Model.CommandActivity]) {
        'Command'
    }
    elseif ($Activity -is [Orchestrator.GraphRunbook.Model.InvokeRunbookActivity]) {
        'InvokeRunbook'
    }
    elseif ($Activity -is [Orchestrator.GraphRunbook.Model.JunctionActivity]) {
        'Junction'
    }
    else {
        throw "Activity '$($Activity.Name)' is of unknown type: $($Activity.GetType().FullName)"
    }
}

function CreateRetry($ExitCondition, $Delay) {
    $IsExitConditionDataPresent =
        ($null -ne $ExitCondition) -and
        (($ExitCondition.Mode -eq [Orchestrator.GraphRunbook.Model.ConditionMode]::Enabled) -or
            (-not [string]::IsNullOrEmpty($ExitCondition.Expression)))

    if ($IsExitConditionDataPresent) {
        [ordered]@{
            ExitCondition = $ExitCondition
            Delay = $Delay
        }
    }
    else {
        $null
    }
}

function ConvertActivityToPsd($IndentLevel, [Orchestrator.GraphRunbook.Model.ExecutableView.IActivity]$Value) {
    $Properties = [ordered]@{ }
    
    $Properties.Add('Name', $Value.Name)
    $Properties.Add('Description', (NullIfEmptyString $Value.Description))
    $Properties.Add('Type', (GetActivityTypeName $Value))

    $Properties.Add('Begin', (CreateScriptBlockIfNotEmpty $Value.Begin))
    $Properties.Add('Process', (CreateScriptBlockIfNotEmpty $Value.Process))
    $Properties.Add('End', (CreateScriptBlockIfNotEmpty $Value.End))

    $Properties.Add('ModuleName', (NullIfEmptyString $Value.CommandType.ModuleName))
    $Properties.Add('CommandName', $Value.InvocationActivityType.CommandName)
    $Properties.Add('Parameters', (NullIfEmptyDictionary $Value.Parameters))
    $Properties.Add('CustomParameters', (NullIfEmptyString $Value.CustomParameters))
    
    $Properties.Add('CheckpointAfter', $Value.CheckpointAfter)
    $Properties.Add('ExceptionsToErrors', $Value.ExceptionsToErrors)
    $Properties.Add('Retry', (CreateRetry -ExitCondition $Value.LoopExitCondition -Delay $Value.LoopDelay))

    $Properties.Add('Position', (NullIfPositionZeroZero $Value))

    ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value $Properties
}

function ConvertNamedReferenceToPsd($IndentLevel, $SourceType, $Name) {
    ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
        SourceType = $SourceType
        Name = $Name
    })
}

function ConvertValueDescriptorToPsd($IndentLevel, [Orchestrator.GraphRunbook.Model.ExecutableView.IValueDescriptor]$Value) {
    if ($Value -is [Orchestrator.GraphRunbook.Model.ExecutableView.IConstantValueDescriptor]) {
        ConvertValueToPsd -IndentLevel $IndentLevel -Value $Value.Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor]) {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            SourceType = 'ActivityOutput'
            Activity = $Value.ActivityName
            FieldPath = $Value.FieldPath
        })
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.PowerShellExpressionValueDescriptor]) {
        ConvertScriptBlockToPsd -IndentLevel $IndentLevel -Value (CreateScriptBlockIfNotEmpty $Value.Expression)
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.RunbookParameterValueDescriptor]) {
        ConvertNamedReferenceToPsd -IndentLevel $IndentLevel -SourceType 'RunbookParameter' -Name $Value.ParameterName
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.AutomationCertificateValueDescriptor]) {
        ConvertNamedReferenceToPsd -IndentLevel $IndentLevel -SourceType 'AutomationCertificate' -Name $Value.CertificateName
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.AutomationCredentialValueDescriptor]) {
        ConvertNamedReferenceToPsd -IndentLevel $IndentLevel -SourceType 'AutomationCredential' -Name $Value.CredentialName
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.AutomationConnectionValueDescriptor]) {
        ConvertNamedReferenceToPsd -IndentLevel $IndentLevel -SourceType 'AutomationConnection' -Name $Value.ConnectionName
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor]) {
        ConvertNamedReferenceToPsd -IndentLevel $IndentLevel -SourceType 'AutomationVariable' -Name $Value.VariableName
    }
    else {
        throw "Unknown value descriptor type: $($Value.GetType().FullName)"
    }
}

function ConvertLinkToPsd($IndentLevel, [Orchestrator.GraphRunbook.Model.Link]$Value) {
    $FromActivity = Get-ActivityById $Runbook $Value.SourceActivityEntityId
    $ToActivity = Get-ActivityById $Runbook $Value.DestinationActivityEntityId

    ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
        From = $FromActivity.Name
        To = $ToActivity.Name
        Description = (NullIfEmptyString $Value.Description)
        Stream = $Value.LinkStreamType
        Type = $Value.LinkType
        Condition = $Value.Condition
    })
}

function ConvertConditionToPsd($IndentLevel, [Orchestrator.GraphRunbook.Model.Condition]$Value) {
    if ($Value.Mode -eq [Orchestrator.GraphRunbook.Model.ConditionMode]::Enabled) {
        ConvertValueToPsd -IndentLevel $IndentLevel -Value (CreateScriptBlockIfNotEmpty $Value.Expression)
    }
    else {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
            Mode = $Value.Mode
            Expression = CreateScriptBlockIfNotEmpty $Value.Expression
        })
    }
}

function ConvertCommentToPsd($IndentLevel, [Orchestrator.GraphRunbook.Model.Comment]$Value) {
    ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
        Name = $Value.Name
        Text = $Value.Text
        Position = NullIfPositionZeroZero $Value
    })
}

function ConvertParameterToPsd($IndentLevel, [Orchestrator.GraphRunbook.Model.Parameter]$Value) {
    ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value ([ordered]@{
        Name = $Value.Name
        Description = (NullIfEmptyString $Value.Description)
        Mandatory = -not $Value.Optional
        DefaultValue = $Value.DefaultValue
    })
}

function ConvertValueToPsd($IndentLevel, $Value) {
    if ($null -eq $Value) {
        '$null'
    }
    elseif ($Value -is [bool]) {
        if ($Value) {
            '$true'
        }
        else {
            '$false'
        }
    }
    elseif ($Value -is [int]) {
        "$Value"
    }
    elseif ($Value -is [scriptblock]) {
        ConvertScriptBlockToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [System.TimeSpan]) {
        $Value.Ticks
    }
    elseif ($Value -is [System.Collections.IList]) {
        ConvertListToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [System.Collections.IDictionary]) {
        ConvertDictionaryToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [System.Tuple`2[[int], [int]]]) {
        ConvertTuple2IntToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.ExecutableView.IActivity]) {
        ConvertActivityToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.ExecutableView.IValueDescriptor]) {
        ConvertValueDescriptorToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.Link]) {
        ConvertLinkToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.Condition]) {
        ConvertConditionToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.Comment]) {
        ConvertCommentToPsd -IndentLevel $IndentLevel -Value $Value
    }
    elseif ($Value -is [Orchestrator.GraphRunbook.Model.Parameter]) {
        ConvertParameterToPsd -IndentLevel $IndentLevel -Value $Value
    }
    else {
        # PowerShell v.5+ required!
        "'$([Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value.ToString()))'"
    }
}

function ConvertNamedValueToPsd($IndentLevel, $Name, $Value) {
    "$(Get-Indent $IndentLevel)$Name = $(ConvertValueToPsd -IndentLevel $IndentLevel -Value $Value)"
}

function ConvertOptionalSectionToPsd($Name, $Data) {
    if ($Data) {
        "$(ConvertNamedValueToPsd -IndentLevel 0 -Name $Name -Value $Data)`r`n`r`n"
    }
    else {
        ''
    }
}

function Get-GraphicalAuthoringSdkDirectoryFromRegistry {
    Get-ItemPropertyValue -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\AzureAutomation\GraphicalAuthoringSDK -Name InstallPath
}

function Add-GraphRunbookModelAssembly($GraphicalAuthoringSdkDirectory) {
    if (-not $GraphicalAuthoringSdkDirectory) {
        $GraphicalAuthoringSdkDirectory = Get-GraphicalAuthoringSdkDirectoryFromRegistry
    }

    $ModelAssemblyPath = Join-Path $GraphicalAuthoringSdkDirectory 'Orchestrator.GraphRunbook.Model.dll'

    if (Test-Path $ModelAssemblyPath -PathType Leaf) {
        Add-Type -Path $ModelAssemblyPath
    }
    else {
        Write-Warning ("Assembly not found: $ModelAssemblyPath. Install Microsoft Azure Automation Graphical Authoring SDK " +
            "(https://www.microsoft.com/en-us/download/details.aspx?id=50734) and provide the installation directory path " +
            "in the GraphicalAuthoringSdkDirectory parameter.")
    }
}

function Get-GraphRunbookFromFile($FileName) {
    $SerializedRunbook = Get-Content -Path $FileName | Out-String
    $RunbookContainer = [Orchestrator.GraphRunbook.Model.Serialization.RunbookSerializer]::DeserializeRunbookContainer($SerializedRunbook)
    if ($RunbookContainer.SchemaVersion.Major -gt 1) {
        Write-Warning ("Runbook $FileName is serialized using schema version $($RunbookContainer.SchemaVersion). " +
            "Schema versions higher than 1.* may not be supported.")
    }

    [Orchestrator.GraphRunbook.Model.Serialization.RunbookSerializer]::GetRunbook($RunbookContainer)
}

function New-TemporaryDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Scope="Function")]
    param()

    $parent = [System.IO.Path]::GetTempPath()
    [string]$name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

function Convert-GraphRunbookObjectToPowerShellData(
    [Parameter(Mandatory = $true)]
    [Orchestrator.GraphRunbook.Model.GraphRunbook]
    $Runbook) {

    $Result = "@{`r`n`r`n"
    $Result += ConvertOptionalSectionToPsd -Name Parameters -Data $Runbook.Parameters
    $Result += ConvertOptionalSectionToPsd -Name Comments -Data $Runbook.Comments
    $Result += ConvertOptionalSectionToPsd -Name OutputTypes -Data $Runbook.OutputTypes
    $Result += ConvertOptionalSectionToPsd -Name Activities -Data $Runbook.Activities
    $Result += ConvertOptionalSectionToPsd -Name Links -Data $Runbook.Links
    $Result += "}`r`n"

    $Result
}

function Convert-GraphRunbookFileToPowerShellData($RunbookFileName) {
    Write-Verbose "Converting runbook from file $RunbookFileName"
    $Runbook = Get-GraphRunbookFromFile -FileName $RunbookFileName
    Convert-GraphRunbookObjectToPowerShellData $Runbook
}

function WithExportedRunbook($RunbookName, $Slot, $ResourceGroupName, $AutomationAccountName, [scriptblock]$Action) {
    $OutputFolder = New-TemporaryDirectory
    Write-Verbose "Created temporary directory: $OutputFolder"
    try {
        Write-Verbose "Exporting runbook '$RunbookName' to temporary directory '$OutputFolder'"
        $RunbookFile = Export-AzureRMAutomationRunbook `
            -Name $RunbookName `
            -OutputFolder $OutputFolder `
            -Slot $Slot `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName
        
        $FullFileName = Join-Path $OutputFolder $RunbookFile.Name
        Write-Verbose "Exported runbook '$RunbookName' to file '$FullFileName'"

        $Action.Invoke($FullFileName)
    }
    finally {
        Remove-Item $OutputFolder -Recurse -Force
    }
}

function Convert-GraphRunbookInAzureToPowerShellData($RunbookName, $Slot, $ResourceGroupName, $AutomationAccountName) {
    WithExportedRunbook -RunbookName $RunbookName -Slot $Slot -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Action {
        param($FullFileName)
        Convert-GraphRunbookFileToPowerShellData $FullFileName
    }
}

function Convert-GraphRunbookToPowerShellData {
<#
.SYNOPSIS
Converts a graphical runbook to PowerShell data

.DESCRIPTION
Converts a graphical runbook to PowerShell data. The resulting representation contains the entire runbook definition in a human-readable and PowerShell-readable text format. It can be used for inspecting and documenting runbooks, storing them in a source control system, comparing different versions, etc. Furthermore, the resulting representation is valid PowerShell code that constructs a data structure with all the runbook content, so you can save it in a .psd1 file, open it in any PowerShell editing tool, parse it with PowerShell, etc.

IMPORTANT NOTES
===============

1. The resulting PowerShell code is not an executable runbook. If this code is executed, it builds a data structure describing the original graphical runbook, but does not run the runbook.

2. Even though the resulting representation contains all the data from the original runbook, and it can theoretically be used to construct a runbook equivalent to the original one, there is no automated conversion back to .graphrunbook implemented yet. If you intend to use this runbook in Azure Automation later, do *not* discard the original .graphrunbook file after conversion.

Prerequisites
=============

1. Install Microsoft Azure Automation Graphical Authoring SDK (https://www.microsoft.com/en-us/download/details.aspx?id=50734).

2. Before invoking Convert-GraphRunbookToPowerShellData with RunbookName, ResourceGroupName, and AutomationAccountName parameters, make sure you add an authenticated Azure account (for example, use Add-AzureRmAcccount cmdlet).

.PARAMETER Runbook
An instance of Orchestrator.GraphRunbook.Model.GraphRunbook type

.PARAMETER GraphicalAuthoringSdkDirectory
Microsoft Azure Automation Graphical Authoring SDK installation directory

.PARAMETER RunbookFileName
Runbook file name (.graphrunbook)

.PARAMETER RunbookName
Runbook name

.PARAMETER Slot
Specifies whether this cmdlet converts the draft or published content of the runbook. Valid values are:
        -- Published
        -- Draft

.PARAMETER ResourceGroupName
Azure Resource Group name

.PARAMETER AutomationAccountName
Azure Automation Account name

.EXAMPLE
Convert-GraphRunbookToPowerShellData -RunbookFileName ./MyRunbook.graphrunbook
Convert a graphical runbook from .graphrunbook file to PowerShell data.

.EXAMPLE
Convert-GraphRunbookToPowerShellData -RunbookFileName ./MyRunbook.graphrunbook | Out-File ./MyRunbook.psd1
Save a graphical runbook converted to PowerShell data as a .psd1 file.

.EXAMPLE
Convert-GraphRunbookToPowerShellData -RunbookName MyRunbook -ResourceGroupName myresourcegroup -AutomationAccountName myautomationaccount
Convert a graphical runbook from an Azure Automation account to PowerShell data.

.EXAMPLE
Convert-GraphRunbookToPowerShellData -RunbookFileName ./MyRunbook.graphrunbook -GraphicalAuthoringSdkDirectory 'C:\Program Files (x86)\Microsoft Azure Automation Graphical Authoring SDK'
Specify the Microsoft Azure Automation Graphical Authoring SDK installation directory.

.EXAMPLE
Get-AzureRmAutomationRunbook -ResourceGroupName myresourcegroup -AutomationAccountName myautomationaccount -PipelineVariable Runbook | ?{ ($_.RunbookType -match '^Graph') -and ($_.State -eq 'Published') } | Convert-GraphRunbookToPowerShellData -Verbose | %{ $_ | Out-File "$HOME\Desktop\AllRunbooks\$($Runbook.Name).psd1" }
Retrieve all published graphical runbooks from a specified Azure Automation account, convert them to PowerShell data, and save the results to .psd1 files.

.LINK
Source code: https://github.com/azureautomation/graphical-runbook-tools

.LINK
Azure Automation: https://azure.microsoft.com/services/automation

.LINK
Microsoft Azure Automation Graphical Authoring SDK: https://www.microsoft.com/en-us/download/details.aspx?id=50734
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByGraphRunbook')]
        # Should be [Orchestrator.GraphRunbook.Model.GraphRunbook], but declaring this type here would require
        # the Model assembly to be pre-loaded even before accessing module metadata
        $Runbook,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByRunbookFileName')]
        [string]
        $RunbookFileName,

        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByRunbookName')]
        [Alias('Name')]
        [string]
        $RunbookName,

        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByRunbookName')]
        [string]
        $ResourceGroupName,

        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByRunbookName')]
        [string]
        $AutomationAccountName,

        [Parameter(
            ParameterSetName = 'ByRunbookName')]
        [ValidateSet('Published', 'Draft')]
        [string]
        $Slot = 'Published',

        [string]
        $GraphicalAuthoringSdkDirectory
    )

    begin {
        Add-GraphRunbookModelAssembly $GraphicalAuthoringSdkDirectory
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ByGraphRunbook' {
                Convert-GraphRunbookObjectToPowerShellData $Runbook -ErrorAction Stop
            }

            'ByRunbookFileName' {
                Convert-GraphRunbookFileToPowerShellData $RunbookFileName -ErrorAction Stop
            }

            'ByRunbookName' {
                Convert-GraphRunbookInAzureToPowerShellData `
                    -RunbookName $RunbookName `
                    -Slot $Slot `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -ErrorAction Stop
            }
        }
    }
}

#endregion

#region Get-GraphRunbookDependency

Add-Type -Language 'CSharp' -TypeDefinition @"
    namespace GraphRunbook
    {
        public class Dependency
        {
            public Dependency(string type, string name)
            {
                this.Type = type;
                this.Name = name;
            }

            public string Type { get; set; }
            public string Name { get; set; }
        }
    }
"@

function Get-RequiredModules([Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook) {
    $Runbook.Activities | ForEach-Object CommandType | ForEach-Object ModuleName | Where-Object { $_ } | Sort-Object -Unique |
        ForEach-Object { New-Object GraphRunbook.Dependency -ArgumentList 'Module', $_ }
}

function Get-ValueDescriptor([Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook) {
    $Parameters = $Runbook.Activities | ForEach-Object Parameters
    $Parameters | Where-Object { $_ } | ForEach-Object { foreach ($Entry in $_.GetEnumerator()) { $Entry.Value } }
}

function Get-AutomationAssets(
    [Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook,
    [string]$ValueDescriptorPropertyName,
    [string[]]$AssetAccessCommandNames,
    [string]$DependencyType) {

    $NamesFromValueDescriptors = Get-ValueDescriptor $Runbook | ForEach-Object -MemberName $ValueDescriptorPropertyName

    $NamesFromAssetAccessCommands += $Runbook.Activities |
        Where-Object { $AssetAccessCommandNames -icontains $_.CommandType.CommandName } |
        ForEach-Object { $_.Parameters['Name'] } |
        Where-Object { $_ -is [Orchestrator.GraphRunbook.Model.ConstantValueDescriptor] } |
        ForEach-Object { $_.Value }

    $AllNames = $NamesFromValueDescriptors + $NamesFromAssetAccessCommands

    $AllNames | Where-Object { $_ } | Sort-Object -Unique |
        ForEach-Object { New-Object GraphRunbook.Dependency -ArgumentList $DependencyType, $_ }
}

function Get-RequiredAutomationAssets([Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook) {
    Get-AutomationAssets -Runbook $Runbook `
        -ValueDescriptorPropertyName CertificateName `
        -AssetAccessCommandNames ('Get-AutomationCertificate', 'Get-AzureAutomationCertificate', 'Get-AzureRmAutomationCertificate') `
        -DependencyType AutomationCertificate

    Get-AutomationAssets -Runbook $Runbook `
        -ValueDescriptorPropertyName ConnectionName `
        -AssetAccessCommandNames ('Get-AutomationConnection', 'Get-AzureAutomationConnection', 'Get-AzureRmAutomationConnection') `
        -DependencyType AutomationConnection

    Get-AutomationAssets -Runbook $Runbook `
        -ValueDescriptorPropertyName CredentialName `
        -AssetAccessCommandNames ('Get-AutomationPSCredential', 'Get-AzureAutomationCredential', 'Get-AzureRmAutomationCredential') `
        -DependencyType AutomationCredential

    Get-AutomationAssets -Runbook $Runbook `
        -ValueDescriptorPropertyName VariableName `
        -AssetAccessCommandNames (
            'Get-AutomationVariable', 'Set-AutomationVariable',
            'Get-AzureAutomationVariable', 'Get-AzureRmAutomationVariable',
            'Set-AzureAutomationVariable', 'Set-AzureRmAutomationVariable') `
        -DependencyType AutomationVariable
}

function Get-RequiredRunbooks([Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook) {
    $NamesFromInvokeRunbookActivity = $Runbook.Activities | ForEach-Object RunbookActivityType | ForEach-Object CommandName

    $NamesFromCommandActivity = $Runbook.Activities |
        Where-Object { @('Start-AzureAutomationRunbook', 'Start-AzureRmAutomationRunbook') -icontains $_.CommandType.CommandName } |
        ForEach-Object { $_.Parameters['Name'] } |
        Where-Object { $_ -is [Orchestrator.GraphRunbook.Model.ConstantValueDescriptor] } |
        ForEach-Object { $_.Value }

    $AllNames = $NamesFromInvokeRunbookActivity + $NamesFromCommandActivity

    $AllNames | Where-Object { $_ } | Sort-Object -Unique |
        ForEach-Object { New-Object GraphRunbook.Dependency -ArgumentList 'Runbook', $_ }
}

function Get-GraphRunbookDependencyByGraphRunbook(
    [Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook,
    [string]$DependencyType) {

    if ($DependencyType -ieq 'Module') {
        Get-RequiredModules -Runbook $Runbook
    }
    elseif ($DependencyType -ieq 'AutomationAsset') {
        Get-RequiredAutomationAssets -Runbook $Runbook
    }
    elseif ($DependencyType -ieq 'Runbook') {
        Get-RequiredRunbooks -Runbook $Runbook
    }
    elseif ($DependencyType -ieq 'All') {
        Get-RequiredModules -Runbook $Runbook
        Get-RequiredAutomationAssets -Runbook $Runbook
        Get-RequiredRunbooks -Runbook $Runbook
    }
}

function Get-GraphRunbookDependencyByRunbookFileName(
    [string]$RunbookFileName,
    [string]$DependencyType) {

    Write-Verbose "Inspecting runbook file $RunbookFileName"
    $Runbook = Get-GraphRunbookFromFile -FileName $RunbookFileName
    Get-GraphRunbookDependencyByGraphRunbook -Runbook $Runbook -DependencyType $DependencyType
}

function Get-GraphRunbookDependencyByRunbookName($RunbookName, $Slot, $ResourceGroupName, $AutomationAccountName, $DependencyType) {
    WithExportedRunbook -RunbookName $RunbookName -Slot $Slot -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Action {
        param($FullFileName)
        Get-GraphRunbookDependencyByRunbookFileName -RunbookFileName $FullFileName -DependencyType $DependencyType
    }
}

function Get-GraphRunbookDependency {
<#
.SYNOPSIS
Outputs graphical runbook dependencies

.DESCRIPTION
Inspects a graphical runbook and outputs the runbook dependencies: required modules, accessed Automation Assets (Certificates, Connections, Credentials, and Variables), and invoked runbooks.

This command discovers dependencies explicitly specified in the graphical runbook, but it may not accurately determine dependencies of any PowerShell code (such as Code activity body, PowerShell expressions in activity parameters, or Link and Retry conditions).

Prerequisites
=============

1. Install Microsoft Azure Automation Graphical Authoring SDK (https://www.microsoft.com/en-us/download/details.aspx?id=50734).

2. Before invoking Get-GraphRunbookDependency with RunbookName, ResourceGroupName, and AutomationAccountName parameters, make sure you add an authenticated Azure account (for example, use Add-AzureRmAcccount cmdlet).

.PARAMETER Runbook
An instance of Orchestrator.GraphRunbook.Model.GraphRunbook type

.PARAMETER GraphicalAuthoringSdkDirectory
Microsoft Azure Automation Graphical Authoring SDK installation directory

.PARAMETER RunbookFileName
Runbook file name (.graphrunbook)

.PARAMETER RunbookName
Runbook name

.PARAMETER Slot
Specifies whether this cmdlet converts the draft or published content of the runbook. Valid values are:
        -- Published
        -- Draft

.PARAMETER ResourceGroupName
Azure Resource Group name

.PARAMETER AutomationAccountName
Azure Automation Account name

.PARAMETER DependencyType
Dependency type: Module, AutomationAsset, Runbook, or All (default)

.EXAMPLE
Get-GraphRunbookDependency -RunbookFileName ./MyRunbook.graphrunbook -DependencyType Module
Output modules that the specified graphical runbook depends on.

.EXAMPLE
Get-GraphRunbookDependency -RunbookName MyRunbook -ResourceGroupName myresourcegroup -AutomationAccountName myautomationaccount
Output all dependencies of a graphical runbook from an Azure Automation account.

.EXAMPLE
Get-GraphRunbookDependency -RunbookFileName ./MyRunbook.graphrunbook -GraphicalAuthoringSdkDirectory 'C:\Program Files (x86)\Microsoft Azure Automation Graphical Authoring SDK'
Specify the Microsoft Azure Automation Graphical Authoring SDK installation directory.

.LINK
Source code: https://github.com/azureautomation/graphical-runbook-tools

.LINK
Azure Automation: https://azure.microsoft.com/services/automation

.LINK
Microsoft Azure Automation Graphical Authoring SDK: https://www.microsoft.com/en-us/download/details.aspx?id=50734
#>
    [CmdletBinding()]
    [OutputType([GraphRunbook.Dependency])]
    param(
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByGraphRunbook')]
        # Should be [Orchestrator.GraphRunbook.Model.GraphRunbook], but declaring this type here would require
        # the Model assembly to be pre-loaded even before accessing module metadata
        $Runbook,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByRunbookFileName')]
        [string]
        $RunbookFileName,

        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByRunbookName')]
        [Alias('Name')]
        [string]
        $RunbookName,

        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByRunbookName')]
        [string]
        $ResourceGroupName,

        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ByRunbookName')]
        [string]
        $AutomationAccountName,

        [Parameter(
            ParameterSetName = 'ByRunbookName')]
        [ValidateSet('Published', 'Draft')]
        [string]
        $Slot = 'Published',

        [ValidateSet('Module', 'AutomationAsset', 'Runbook', 'All')]
        [string]
        $DependencyType = 'All',

        [string]
        $GraphicalAuthoringSdkDirectory
    )
    
    begin {
        Add-GraphRunbookModelAssembly $GraphicalAuthoringSdkDirectory
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ByGraphRunbook' {
                Get-GraphRunbookDependencyByGraphRunbook -Runbook $Runbook -DependencyType $DependencyType -ErrorAction Stop
            }

            'ByRunbookFileName' {
                Get-GraphRunbookDependencyByRunbookFileName -RunbookFileName $RunbookFileName -DependencyType $DependencyType -ErrorAction Stop
            }

            'ByRunbookName' {
                Get-GraphRunbookDependencyByRunbookName `
                    -RunbookName $RunbookName `
                    -Slot $Slot `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -DependencyType $DependencyType `
                    -ErrorAction Stop
            }
        }
    }
}

#endregion

Export-ModuleMember -Function Show-GraphRunbookActivityTraces
Export-ModuleMember -Function Convert-GraphRunbookToPowerShellData
Export-ModuleMember -Function Get-GraphRunbookDependency
