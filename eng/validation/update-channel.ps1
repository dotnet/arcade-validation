Param(
  [string] $targetChannelName = ".NET Eng - Latest",
  [string] $azdoToken
)

$ci = $true
. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\..\common\pipeline-logging-functions.ps1
$darc = & "$PSScriptRoot\get-darc.ps1"

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName

try {
    # Get the Microsoft.DotNet.Arcade.Sdk with the version $arcadeSdkVersion so we can get the id of the build
    $assets = & $darc get-asset --name $arcadeSdkPackageName --version $arcadeSdkVersion --ci --output-format json | ConvertFrom-Json

    if (!$assets) {
        Write-Host "Asset '$arcadeSdkPackageName' with version $arcadeSdkVersion was not found"
        exit 1
    }

    if ($assets.Count -ne 1) {
        Write-Host "More than 1 asset matched the version '$arcadeSdkVersion' of Microsoft.DotNet.Arcade.Sdk. This is not normal. Stopping execution..."
        exit 1
    }

    $buildId = $assets[0].build.id

    & $darc add-build-to-channel --id $buildId --channel "$targetChannelName" --azdev-pat $azdoToken --ci --skip-assets-publishing
    
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
