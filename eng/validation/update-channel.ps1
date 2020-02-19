Param(
  [string] $maestroEndpoint,
  [string] $barToken,
  [string] $apiVersion = "2018-07-16",
  [string] $targetChannelName = ".NET Eng - Latest",
  [string] $azdoToken,
  [string] $githubToken
)

. $PSScriptRoot\..\common\tools.ps1

function Get-Headers([string]$accept, [string]$barToken) {
    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept',$accept)
    $headers.Add('Authorization',"Bearer $barToken")
    return $headers
}

function Get-AzDO-Build([string]$token, [int]$azdoBuildId) {
    $uri = "https://dev.azure.com/dnceng/internal/_apis/build/builds/${azdoBuildId}?api-version=5.1"
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${token}"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get 
    return $content | ConvertFrom-Json
}

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName
$getAssetsApiEndpoint = "$maestroEndpoint/api/assets?name=$arcadeSdkPackageName&version=$arcadeSdkVersion&api-version=$apiVersion"
$headers = Get-Headers 'text/plain' $barToken

try {
    # Get the Microsoft.DotNet.Arcade.Sdk with the version $arcadeSdkVersion so we can get the id of the build
    $assets = Invoke-WebRequest -Uri $getAssetsApiEndpoint -Headers $headers | ConvertFrom-Json

    if (!$assets) {
        Write-Host "Asset '$arcadeSdkPackageName' with version $arcadeSdkVersion was not found"
        exit 1
    }

    if ($assets.Count -ne 1) {
        Write-Host "More than 1 asset matched the version '$arcadeSdkVersion' of Microsoft.DotNet.Arcade.Sdk. This is not normal. Stopping execution..."
        exit 1
    }

    $buildId = $assets[0].'buildId'

    . $PSScriptRoot\..\common\darc-init.ps1

    $DarcOutput = darc add-build-to-channel --id $buildId --channel "$targetChannelName" --github-pat $githubToken --azdev-pat $azdoToken --bar-uri "$maestroEndpoint" --password $barToken
    
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
    else {
        $buildUrlRegex = "https://dnceng.visualstudio.com/internal/_build/results\?buildId=(?<buildId>[0-9]*)"

        $azdoBuildId = $DarcOutput | select-string -Pattern $buildUrlRegex -AllMatches | % { $_.Matches.Groups[1].Value } 
        $waitIntervalsInSeconds = 60
        $build = $null

        do {
            Write-Host "Waiting ${waitIntervalsInSeconds} seconds for promotion build to complete... https://dnceng.visualstudio.com/internal/_build/results?buildId=${azdoBuildId}"

            Start-Sleep -Seconds $waitIntervalsInSeconds

            $build = Get-AzDO-Build -token $azdoToken -azdoBuildId $azdoBuildId
        } while ($build.status -ne "completed")

        if ($build.result -eq "succeeded") {
            Write-Host "Build '$buildId' was successfully added to channel '$targetChannelName'"
        }
        else {
            Write-Host "Error trying to promote build. The promotion build finished with this result: $($build.result)"
            exit 1
        }    
    }
}
catch {
    Write-Host $_
    Write-Host $_.ScriptStackTrace
    exit 1
}
