Param(
  [string] $maestroEndpoint,
  [string] $barToken,
  [string] $apiVersion = "2018-07-16",
  [string] $targetChannelName = ".NET 5 Eng"
)

. $PSScriptRoot\..\common\tools.ps1

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

    $darc = & "$PSScriptRoot\get-darc.ps1"

    $DarcOutput = & $darc add-build-to-channel --id $buildId --channel "$targetChannelName" --bar-uri "$maestroEndpoint" --password $barToken --skip-assets-publishing
    
    if ($LastExitCode -ne 0) {
        Write-Host "Problems using Darc to promote build ${buildId} to channel ${targetChannelName}. Stopping execution..."
        Write-Host $DarcOutput
        exit 1
    }

    # Consider re-working or removing the code below once this issue is closed:
    # https://github.com/dotnet/arcade/issues/4863

    if ($DarcOutput -match "has already been assigned to") {
        Write-Host "Build '$buildId' is already in channel '$targetChannelName'. This is most likely an arcade-validation internal build"
    }

    Write-Host "Build '$buildId' was successfully added to channel '$targetChannelName'"
}
catch {
    Write-Host $_
    Write-Host $_.ScriptStackTrace
    exit 1
}
