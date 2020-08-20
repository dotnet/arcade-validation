Param(
  [Parameter(Mandatory=$true)][string] $buildId,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $barToken,
  [Parameter(Mandatory=$true)][string] $githubPAT
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

$darc = & "$PSScriptRoot\get-darc.ps1"

$global:azdoOrg = $azdoOrg
$global:azdoProject = $azdoProject
$global:buildDefinitionId = $buildDefinitionId
$global:subscribedBranchName = $subscribedBranchName #------------ missing these 4
$global:buildId = $buildId
$global:targetChannel = "General Testing"
$global:azdoToken = $azdoToken
$global:barToken = $barToken
$global:githubPAT = $githubPAT

. .\validation-functions.ps1

function Find-BuildInTargetChannel(
    [string] $buildId,
    [string] $targetChannelName
)
{
    $buildJson = & $darc get-build --id $buildId --azdev-pat $global:azdoToken --password $global:barToken --output-format json
    $build = ($buildJson | ConvertFrom-Json)

    $channels = ($build | Select-Object -ExpandProperty channels)
    if($channels -contains $targetChannelName)
    {
        return $true
    }

    return $false
}

$global:arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$global:arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$global:arcadeSdkPackageName
$global:githubRepoName = "arcade"
$asset = darc get-asset --name "microsoft.dotnet.arcade.sdk" --version "5.0.0-beta.20419.21" --output-format json | convertFrom-Json
$sha = $asset.build.commit
$global:targetBranch = "val/" + $global:githubUser + "/arcade-" + $global:arcadeSdkVersion

## Create a branch from the repo with the given SHA.
Git-Command $global:githubRepoName checkout -b $global:targetBranch $sha

## Get the BAR Build ID for the version of Arcade we want to use in update-dependecies
$asset = & $darc get-asset --name $global:arcadeSdkPackageName --version $global:arcadeSdkVersion --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken
$barBuildIdString = $asset | Select-String -Pattern 'BAR Build Id:'
$barBuildId = ([regex]"\d+").Match($barBuildIdString).Value

## Make the changes to that branch to update Arcade - use darc
Set-Location $(Get-Repo-Location $global:githubRepoName)
& $darc update-dependencies --id $barBuildId --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken

Git-Command $global:githubRepoName commit -am "Arcade branch - version ${global:arcadeSdkVersion}"

Git-Command $global:githubRepoName push origin HEAD

# Verify that the build doesn't already exist in our target channel (otherwise we cannot verify that it was published correctly)
Write-Host "Verifying that build '${global:buildId}' does not exist in channel '${global:targetChannel}'"
$preCheck = (Find-BuildInTargetChannel -buildId $global:buildId -targetChannelName $global:targetChannel)
if($preCheck)
{
    Write-Error "Build already exists in '${global:targetChannel}'."
}

Write-Host "Adding build '${global:buildId}' to channel '${global:targetChannel}'"
& $darc add-build-to-channel --id $global:buildId --channel $global:targetChannel --source-branch $global:targetBranch --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:barToken

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

## Clean up branch if successful
Write-Host "Build was successful. Cleaning up ${global:targetBranch} branch."
try
{
	Git-Command $global:githubRepoName push origin --delete $global:targetBranch
}
catch
{
    Write-Warning "Unable to delete branch when cleaning up"
}