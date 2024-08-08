Param(
  [string] $maestroEndpoint,
  [string] $barToken,
  [string] $apiVersion = "2020-02-20",
  [string] $targetChannelName = ".NET Eng - Latest",
  [string] $azdoToken,
  [string] $githubToken
)

$ci = $true
. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\..\common\pipeline-logging-functions.ps1
$darc = & "$PSScriptRoot\get-darc.ps1"

function Get-Headers([string]$accept, [string]$barToken) {
    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept',$accept)
    $headers.Add('Authorization',"Bearer $barToken")
    return $headers
}

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName
$getAssetsApiEndpoint = "$maestroEndpoint/api/assets?name=$arcadeSdkPackageName&version=$arcadeSdkVersion&api-version=$apiVersion"
$headers = Get-Headers 'text/plain' $barToken

try {
    # Get the Microsoft.DotNet.Arcade.Sdk with the version $arcadeSdkVersion so we can get the id of the build
    $assets = Invoke-WebRequest -Uri $getAssetsApiEndpoint -Headers $headers -UseBasicParsing | ConvertFrom-Json

    if (!$assets) {
        Write-Host "Asset '$arcadeSdkPackageName' with version $arcadeSdkVersion was not found"
        exit 1
    }

    if ($assets.Count -ne 1) {
        Write-Host "More than 1 asset matched the version '$arcadeSdkVersion' of Microsoft.DotNet.Arcade.Sdk. This is not normal. Stopping execution..."
        exit 1
    }

    $buildId = $assets[0].'buildId'

    & $darc add-build-to-channel --id $buildId --channel "$targetChannelName" --github-pat $githubToken --azdev-pat $azdoToken --password $barToken --skip-assets-publishing
    
    if ($LastExitCode -ne 0) {
        Write-Host "Problems using Darc to promote build ${buildId} to channel ${targetChannelName}. Stopping execution..."
        exit 1
    }
}
catch {
    Write-Host $_
    Write-Host $_.ScriptStackTrace
    exit 1
}
