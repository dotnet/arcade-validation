Param(
  [Parameter(Mandatory=$true)][string] $buildId,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $azdoUser,
  [Parameter(Mandatory=$true)][string] $azdoOrg,
  [Parameter(Mandatory=$true)][string] $azdoProject,
  [Parameter(Mandatory=$true)][string] $githubPAT
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\validation-functions.ps1
$darc = & "$PSScriptRoot\get-darc.ps1"

$global:buildId = $buildId
$global:sourceChannel = ".NET Eng - Validation"
$global:targetChannel = "General Testing"
$global:azdoToken = $azdoToken
$global:azdoUser = $azdoUser
$global:azdoOrg = $azdoOrg
$global:azdoProject = $azdoProject
$global:githubPAT = $githubPAT

function Find-BuildInTargetChannel(
    [string] $buildId,
    [string] $targetChannelName
)
{
    $buildJson = & $darc get-build --id $buildId --ci --output-format json
    $build = ($buildJson | ConvertFrom-Json)

    $channels = ($build | Select-Object -ExpandProperty channels)
    if($channels -contains $targetChannelName)
    {
        return $true
    }
$
    return $false
}

$global:arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$global:arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$global:arcadeSdkPackageName
$global:azdoRepoName = "dotnet-arcade"
$global:azdoRepoUri = "https://unused:$azdoToken@${global:azdoOrg}.visualstudio.com/${global:azdoProject}/_git/${global:azdoRepoName}"
$jsonAsset = & $darc get-asset --name $global:arcadeSdkPackageName --version $global:arcadeSdkVersion --channel "$sourceChannel" --ci --output-format json | convertFrom-Json
$sha = $jsonAsset.build.commit
$global:targetBranch = "val/arcade-" + $global:arcadeSdkVersion

## Clone the repo from git
Write-Host "Cloning '${global:azdoRepoName}' from Azure Devops"
GitHub-Clone $global:azdoRepoName $global:azdoUser $global:azdoRepoUri

## Create a branch from the repo with the given SHA.
Git-Command $global:azdoRepoName checkout -b $global:targetBranch $sha

## Get the BAR Build ID for the version of Arcade we want to use in update-dependecies
$barBuildId = $jsonAsset.build.id

## Make the changes to that branch to update Arcade - use darc
Set-Location $(Get-Repo-Location $global:azdoRepoName)
& $darc update-dependencies --id $barBuildId --github-pat $global:githubPAT --ci

Git-Command $global:azdoRepoName commit -am "Arcade branch - version ${global:arcadeSdkVersion}"

Git-Command $global:azdoRepoName push origin HEAD

# Verify that the build doesn't already exist in our target channel (otherwise we cannot verify that it was published correctly)
Write-Host "Verifying that build '${global:buildId}' does not exist in channel '${global:targetChannel}'"
$preCheck = (Find-BuildInTargetChannel -buildId $global:buildId -targetChannelName $global:targetChannel)
if($preCheck)
{
    Write-Error "Build already exists in '${global:targetChannel}'."
}

Write-Host "Adding build '${global:buildId}' to channel '${global:targetChannel}'"
& $darc add-build-to-channel --id $global:buildId --channel $global:targetChannel --source-branch $global:targetBranch --azdev-pat $global:azdoToken --ci --publishing-infra-version 3

if ($LastExitCode -ne 0) {
    Write-Host "Problems using Darc to promote build '${global:buildId}' to channel '${global:targetChannel}'. Stopping execution..."
	Cleanup-Branch $global:azdoRepoName $global:targetBranch
    exit 1
}

# Validate that the build was added to the target channel. 
Write-Host "Verifying that build '${global:buildId}' was added in channel '${global:targetChannel}'"
$postCheck = (Find-BuildInTargetChannel -buildId $global:buildId -targetChannelName $global:targetChannel)
if(-not $postCheck)
{
    Write-Error "Build was not added to '${global:targetChannel}'."
}

Cleanup-Branch $global:azdoRepoName $global:targetBranch