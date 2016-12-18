param(
    [Parameter(Mandatory = $true)]
    $NuGetApiKey
)

Publish-Module `
    -Path .\GraphRunbook `
    -ProjectUri https://github.com/azureautomation/graphical-runbook-tools `
    -Tags AzureAutomation `
    -Repository PSGallery `
    -NuGetApiKey $NuGetApiKey
