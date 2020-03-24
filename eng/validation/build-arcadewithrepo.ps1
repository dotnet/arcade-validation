Param(
  [Parameter(Mandatory=$true)][string] $azdoOrg, 
  [Parameter(Mandatory=$true)][string] $azdoProject,
  [Parameter(Mandatory=$true)][int] $buildDefinitionId,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $githubUser,
  [Parameter(Mandatory=$true)][string] $githubPAT,
  [Parameter(Mandatory=$true)][string] $githubOrg,
  [Parameter(Mandatory=$true)][string] $githubRepoName,
  [Parameter(Mandatory=$true)][string] $barToken, 
  [string] $buildParameters = '',
  [int] $daysOfOldestBuild = 3,
  [switch] $pushBranchToGithub,
  [string] $azdoRepoName
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\..\common\darc-init.ps1

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName

# Get a temporary directory for a test root. Use the agent work folder if running under azdo, use the temp path if not.
$testRootBase = if ($env:AGENT_WORKFOLDER) { $env:AGENT_WORKFOLDER } else { $([System.IO.Path]::GetTempPath()) }
$testRoot = Join-Path -Path $testRootBase -ChildPath $([System.IO.Path]::GetRandomFileName())
New-Item -Path $testRoot -ItemType Directory | Out-Null

$minTime = (Get-Date).AddDays(-$daysOfOldestBuild)
$buildReasonsList = @("batchedCI", "individualCI")

function Get-LastKnownGoodBuildSha()
{
    ## Have there been any builds in the last $daysOfOldestBuild days? 
    $headers = Get-AzDOHeaders
    $count = 0

    foreach($reason in $buildReasonsList)
    {
        $uri = Get-AzDOBuildUri -queryStringParameters "&statusFilter=completed&definitions=${buildDefinitionId}&reasonFilter=${reason}&minTime=${minTime}&`$top=1"
        $reponse = (Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json
        $count += $reponse.count
    }

    ## No? Then get the last known good build regardless of age
    if($count -eq 0)
    {
        $contentArray = Get-Builds
        return ($contentArray | Sort-Object { $_.value.finishTime } -descending)[0].value.triggerInfo.'ci.sourceSha'
    }

    ## If there have been builds in the last $daysOfOldestBuild days, get the last known good build from that time frame
    else
    {
        $count = 0
        $contentArray = Get-Builds -useMinTime
        ## If there are no last known good builds in the last $daysOfOldestBuild days, then write a warning. 
        $contentArray | Foreach-Object {$count += $_.count}
        if($count -eq 0)
        {
            Write-warning "There were no successful builds for the '${githubRepoName}' repository in the last ${daysOfOldestBuild} days."
            Exit
        }

        if("" -eq ($contentArray | Sort-Object { $_.value.finishTime } -descending)[0].value.triggerInfo)
        {
            return ($contentArray | Sort-Object { $_.value.finishTime } -descending)[0].value.sourceVersion
        }
        else
        {
            return ($contentArray | Sort-Object { $_.value.finishTime } -descending)[0].value.triggerInfo.'ci.sourceSha'
        }
    }
}

function Invoke-AzDOBuild(
    [int] $buildDefinitionId,
    [string] $branchName,
    [string] $buildParameters)
{ 
    $uri = Get-AzDOBuildUri
    $headers = Get-AzDOHeaders

    $body = @{
        "definition"=@{
            "id"=$buildDefinitionId
        };
        "sourceBranch"=$branchName;
    }

    if("" -ne $buildParameters)
    {
        $body = $body += @{"parameters"=$buildParameters}
    }

    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Body ($body | ConvertTo-Json) -Method Post 
    return ($content | ConvertFrom-Json).id
}

function Get-Builds(
    [switch] $useMinTime
)
{
    $contentArray = @()

    foreach($reason in $buildReasonsList)
    {
        $uri = Get-AzDOBuildUri -queryStringParameters "&resultFilter=succeeded&definitions=${buildDefinitionId}&reasonFilter=${reason}&buildQueryOrder=finishTimeAscending&`$top=1"
        if($useMinTime)
        {
            $uri += "&minTime=${minTime}"
        }

        $response = ((Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json)

        if(1 -eq $response.count)
        {
            $contentArray += $response
        }
    }

    return $contentArray
}

function Get-BuildStatus(
    [int] $buildId)
{
    $uri = (Get-AzDOBuildUri -buildId $buildId)
    $headers = Get-AzDOHeaders
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Method Get 
    return ($content | ConvertFrom-Json).status
}

function Get-BuildResult(
    [int] $buildId)
{
    $uri = (Get-AzDOBuildUri -buildId $buildId)
    $headers = Get-AzDOHeaders
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Method Get 
    return ($content | ConvertFrom-Json).result
}

function Get-BuildLink(
    [int] $build)
{
    $uri = (Get-AzDOBuildUri -buildId $buildId)
    $headers = Get-AzDOHeaders
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Method Get 
    return ($content | ConvertFrom-Json)._links.web.href
}

function Get-AzDOBuildUri(
    [int] $buildId,
    [string] $queryStringParameters
)
{
    $uri = "https://dev.azure.com/${azdoOrg}/${azdoProject}/_apis/build/builds/"
    if(0 -ne $buildId) 
    {
        $uri += $buildId
    }
    
    $uri += "?api-version=5.1" + $queryStringParameters
    return $uri
}

function Get-AzDOHeaders()
{
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${azdoToken}"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    return $headers
}

function Get-Github-RepoAuthUri($repoName)
{
    "https://${githubUser}:${githubPAT}@github.com/${githubOrg}/${repoName}"
}

function Get-AzDO-RepoAuthUri($repoName)
{
    "https://${githubUser}:${azdoToken}@dev.azure.com/${azdoOrg}/${azdoProject}/_git/${repoName}"
}

function GitHub-Clone($repoName) 
{
    & git clone $githubUri $(Get-Repo-Location $repoName)
    Push-Location -Path $(Get-Repo-Location $repoName)
    & git config user.email "${githubUser}@test.com"
    & git config user.name $githubUser
    Pop-Location
}

function Get-Repo-Location($repoName){ "$testRoot\$repoName" }

function Git-Command($repoName) {
    Push-Location -Path $(Get-Repo-Location($repoName))
    try {
        $gitParams = $args
        if ($gitParams.GetType().Name -ne "Object[]") {
            $gitParams = $gitParams.ToString().Split(" ")
        }
        Write-Host "Running 'git $gitParams' from $(Get-Location)"
        $commandOutput = & git @gitParams; if ($LASTEXITCODE -ne 0) { throw "Git exited with exit code: $LASTEXITCODE" } else { $commandOutput }
        $commandOutput
    }
    finally {
        Pop-Location
    }
}

## Global Variables
$githubUri = Get-Github-RepoAuthUri $githubRepoName
$azdoUri = Get-AzDO-RepoAuthUri $azdoRepoName
$remoteName = ($azdoOrg + "-" + $azdoRepoName)
$targetBranch = "dev/" + $githubUser + "/arcade-" + $arcadeSdkVersion
$darcBranchName = "refs/heads/" + $targetBranch
$darcGitHubRepoName = "https://github.com/${githubOrg}/${githubRepoName}"
$darcAzDORepoName = "https://${azdoOrg}.visualstudio.com/${azdoProject}/_git/${azdoRepoName}"

## If able to retrieve a build, get the SHA that it was built from
$sha = Get-LastKnownGoodBuildSha
Write-Host "Last Known Good Build SHA: ${sha}"

## Clone the repo from git
Write-Host "Cloning '${githubRepoName} from GitHub"
GitHub-Clone $githubRepoName
 
## Check to see if branch exists and clean it up if it does
$branchExists = $false
if($true -eq $pushBranchToGithub)
{
    Write-Host "Looking up '${targetBranch}' branch on GitHub"
    $branchExists = Git-Command $githubRepoName ls-remote --heads $githubUri refs/heads/$targetBranch
}
else 
{
    Write-Host "Looking up '${targetBranch}' branch on Azure DevOps"
    $branchExists = Git-Command $githubRepoName ls-remote --heads $azdoUri refs/heads/$targetBranch
}
if($null -ne $branchExists)
{
    Write-Host "${targetBranch} was found. Attempting to clean up."
    try
    {
        & darc delete-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcRepoName --github-pat $githubPAT --password $barToken
        if($true -eq $pushBranchToGithub)
        {
            & darc delete-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcGitHubRepoName --github-pat $githubPAT --password $barToken
            Git-Command $githubRepoName push origin --delete $targetBranch
        }
        else
        {
            & darc delete-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcAzDORepoName --azdev-pat $azdoToken --password $barToken
            Git-Command $githubRepoName remote add $remoteName $azdoUri
            Git-Command $githubRepoName push $remoteName --delete $targetBranch
        }
    }
    catch
    {
        Write-Warning "Unable to delete default channel or branch when cleaning up existing branch"
    }
}

## Create a branch from the repo with the given SHA.
Git-Command $githubRepoName checkout -b $targetBranch $sha

## Make the changes to that branch to update Arcade - use darc
Set-Location $(Get-Repo-Location $githubRepoName)
& darc update-dependencies --channel ".NET Eng - Validation" --source-repo "arcade" --github-pat $githubPAT --azdev-pat $azdoToken --password $barToken

Git-Command $githubRepoName commit -am "Arcade Validation test branch - version ${arcadeSdkVersion}"

if($true -eq $pushBranchToGithub)
{
    ## Push branch to github
    Git-Command $githubRepoName push origin HEAD

    ## Add default channel from that github repo and branch to "General Testing"
    & darc add-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcGitHubRepoName --github-pat $githubPAT --password $barToken
}
else
{
    ## Push branch to AzDO org/project with the official pipeline to build the repo
    ## make remote, it might already exist if we had to delete it earlier, so wrapping it in a try/catch
    try
    {
        Git-Command $githubRepoName remote add $remoteName $azdoUri
    }
    catch
    {
        Write-Host "'${remoteName}' already exists."
    }
    ## push to remote
    Git-Command $githubRepoName push $remoteName $targetBranch

    ## Add default channel from that AzDO repo and branch to "General Testing"
    & darc add-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcAzDORepoName --azdev-pat $azdoToken --password $barToken
}

## Run an official build of the branch using the official pipeline
Write-Host "Invoking build on Azure DevOps"
$buildId = Invoke-AzDOBuild -buildDefinitionId $buildDefinitionId -branchName $targetBranch -buildParameters $buildParameters

## Output summary of references for investigations
Write-Host "Arcade Version: ${arcadeSdkVersion}"
Write-Host "Repository Cloned: ${githubOrg}/${githubRepoName}"
Write-Host "Branch name in repository: ${targetBranch}"
Write-Host "Last Known Good build SHA: ${sha}"

Write-Host "Link to view build: " (Get-BuildLink -buildId $buildId)

## Check build for completion every 5 minutes. 
while("completed" -ne (Get-BuildStatus -buildId $buildId))
{
    Write-Host "Waiting for build to complete..."
    Start-Sleep -Seconds (5*60)
}

## If build fails, then exit
$buildResult = (Get-BuildResult -buildId $buildId)
if(("failed" -eq $buildResult) -or ("canceled" -eq $buildResult))
{
    Write-Error "Build failed or was cancelled"
    exit
}

## Clean up branch if successful
Write-Host "Build was successful. Cleaning up ${targetBranch} branch."
try
{
    if($true -eq $pushBranchToGithub)
    {
        & darc delete-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcGitHubRepoName --github-pat $githubPAT --password $barToken
        Git-Command $githubRepoName push origin --delete $targetBranch
    }
    else
    {
        & darc delete-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcAzDORepoName --azdev-pat $azdoToken --password $barToken
        Git-Command $githubRepoName push $remoteName --delete $targetBranch
    }
}
catch
{
    Write-Warning "Unable to delete default channel or branch when cleaning up branch"
}