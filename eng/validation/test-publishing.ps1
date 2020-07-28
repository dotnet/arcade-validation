Param(
  [Parameter(Mandatory=$true)][string] $buildId,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $barToken,
  [Parameter(Mandatory=$true)][string] $githubPAT
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\darc-init.ps1

refreshenv

$global:buildId = $buildId
$global:targetChannel = "General Testing"
$global:azdoToken = $azdoToken
$global:barToken = $barToken
$global:githubPAT = $githubPAT

function Find-BuildInTargetChannel(
    [string] $buildId,
    [string] $targetChannelName
)
{
    $buildJson = darc get-build --id $buildId --azdev-pat $global:azdoToken --password $global:barToken --output-format json
    $build = ($buildJson | ConvertFrom-Json)

    $channels = ($build | Select-Object -ExpandProperty channels)
    if($channels -contains $targetChannelName)
    {
        return $true
    }

    return $false
}

# Verify that the build doesn't already exist in our target channel (otherwise we cannot verify that it was published correctly)
Write-Host "Verifying that build '${global:buildId}' does not exist in channel '${global:targetChannel}'"
$preCheck = (Find-BuildInTargetChannel -buildId $global:buildId -targetChannelName $global:targetChannel)
if($preCheck)
{
    Write-Error "Build already exists in '${global:targetChannel}'."
}

Write-Host "Adding build '${global:buildId}' to channel '${global:targetChannel}'"
& darc add-build-to-channel --id $global:buildId --channel $global:targetChannel --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:barToken

if ($LastExitCode -ne 0) {
    Write-Host "Problems using Darc to promote build '${global:buildId}' to channel '${global:targetChannel}'. Stopping execution..."
    exit 1
}

# Validate that the build was added to the target channel. 
Write-Host "Verifying that build '${global:buildId}' was added in channel '${global:targetChannel}'"
$postCheck = (Find-BuildInTargetChannel -buildId $global:buildId -targetChannelName $global:targetChannel)
if(-not $postCheck)
{
    Write-Error "Build was not added to '${global:targetChannel}'."
}
