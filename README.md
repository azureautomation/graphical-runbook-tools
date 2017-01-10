# graphical-runbook-tools

Contains a set of experimental tools that help with authoring and debugging *graphical runbooks* in Azure Automation.

## GraphRunbook module

### Installation

1. Install from the [PowerShell Gallery](https://www.powershellgallery.com/packages/GraphRunbook): `Install-Module -Name GraphRunbook -Scope CurrentUser`

2. Most commands in the module also require the [Microsoft Azure Automation Graphical Authoring SDK](https://www.microsoft.com/en-us/download/details.aspx?id=50734) to be installed.

### Commands

* **Show-GraphRunbookActivityTraces** shows graphical runbook activity traces for an Azure Automation job. Activity tracing data is extremely helpful when testing and troubleshooting graphical runbooks in Azure Automation: it shows the execution order of activities, activity start and finish time, activity input and output data, and more. Azure Automation saves this data encoded in JSON in the job Verbose stream. Even though this data is very valuable, the raw JSON format may be hard to read, especially when activities input and output large and complex objects. Show-GraphRunbookActivityTraces command retrieves activity tracing data and displays it in a user-friendly tree structure.

* **Convert-GraphRunbookToPowerShellData** converts a graphical runbook to PowerShell data. The resulting representation contains the entire runbook definition in a human-readable and PowerShell-readable text format. It can be used for inspecting and documenting runbooks, storing them in a source control system, comparing different versions, etc. Furthermore, the resulting representation is valid PowerShell code that constructs a data structure with all the runbook content, so you can save it in a .psd1 file, open it in any PowerShell editing tool, parse it with PowerShell, etc.

*  **Get-GraphRunbookDependency** inspects a graphical runbook and outputs the runbook dependencies: required modules, accessed Automation Assets (Certificates, Connections, Credentials, and Variables), and invoked runbooks.

### Syntax and usage

* `Get-Help Show-GraphRunbookActivityTraces -Full`
* `Get-Help Convert-GraphRunbookToPowerShellData -Full`
* `Get-Help Get-GraphRunbookDependency -Full`
