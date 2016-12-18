param(
    [Parameter(Mandatory = $true)]
    $NuGetApiKey
)

Publish-Module `
    -Path .\GraphRunbook `
    -Repository PSGallery `
    -NuGetApiKey $NuGetApiKey `
    -Verbose
