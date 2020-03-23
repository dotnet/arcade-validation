Param(
  [Parameter(Mandatory=$true)][string] $azdoOrg, 
  [Parameter(Mandatory=$true)][string] $azdoProject,
  [Parameter(Mandatory=$true)][int] $buildDefinitionId,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $githubUser,
  [Parameter(Mandatory=$true)][string] $githubPAT,
  [Parameter(Mandatory=$true)][string] $githubOrg,
  [Parameter(Mandatory=$true)][string] $targetRepoName,
  [Parameter(Mandatory=$true)][string] $barToken, 
  [string] $buildParameters = '',
  [int] $daysOfOldestBuild = 3
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

function Get-LastKnownGoodBuildSha(
    [int] $buildDefinitionId)
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
        $contentArray = @()

        foreach($reason in $buildReasonsList)
        {
            $uri = Get-AzDOBuildUri -queryStringParameters "&resultsFilter=succeeded&definitions=${buildDefinitionId}&reasonFilter=${reason}&buildQueryOrder=finishTimeAscending&`$top=1"
            $response = (Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json
            if(1 -eq $response.count)
            {
                $contentArray += $response
            }
        }

        return ($contentArray | Sort-Object { $_.value.finishTime } -descending)[0].value.triggerInfo.'ci.sourceSha'
    }

    ## If there have been builds in the last $daysOfOldestBuild days, get the last known good build from that time frame
    else
    {
        $contentArray = @()
        $count = 0

        foreach($reason in $buildReasonsList)
        {
            $uri = Get-AzDOBuildUri -queryStringParameters "&resultFilter=succeeded&definitions=${buildDefinitionId}&reasonFilter=${reason}&buildQueryOrder=finishTimeAscending&minTime=${minTime}&`$top=1"
            $response = (Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json
            if(1 -eq $response.count)
            {
                $contentArray += $response
            }
        }
        ## If there are no last known good builds in the last $daysOfOldestBuild days, then write a warning. 
        $contentArray | Foreach-Object {$count += $_.count}
        if($count -eq 0)
        {
            Write-warning "There were no successful builds for this repository in the last ${days} days."
            Exit
        }
        
        return ($contentArray | Sort-Object { $_.value.finishTime } -descending)[0].value.triggerInfo.'ci.sourceSha'
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

function GitHub-Clone($repoName) 
{
    $authUri = Get-Github-RepoAuthUri $repoName
    & git clone $authUri $(Get-Repo-Location $repoName)
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

## If able to retrieve a build, get the SHA that it was built from
$sha = Get-LastKnownGoodBuildSha -buildDefinitionId $buildDefinitionId

## Clone the repo from git
GitHub-Clone $targetRepoName

## Create a branch from the repo with the given SHA. 
$targetBranch = "dev/" + $githubUser + "/arcade-" + $arcadeSdkVersion
$githubUri = Get-Github-RepoAuthUri $targetRepoName

$darcBranchName = "refs/heads/" + $targetBranch
$darcRepoName = "https://github.com/${githubOrg}/${targetRepoName}"

# check to see if branch exists and clean it up if it does
$branchExists = Git-Command $targetRepoName ls-remote --heads $githubUri refs/heads/$targetBranch
if($null -ne $branchExists)
{
    try
    {
        & darc delete-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcRepoName --github-pat $githubPAT --password $barToken
        Git-Command $targetRepoName push origin --delete $targetBranch
    }
    catch
    {
        Write-Warning "Unable to delete default or branch when cleaning up existing branch"
    }
}
Git-Command $targetRepoName checkout -b $targetBranch $sha

## Make the changes to that branch to update Arcade - use darc
Set-Location $(Get-Repo-Location $targetRepoName)
& darc update-dependencies --channel ".NET Eng - Validation" --source-repo "arcade" --github-pat $githubPAT --password $barToken

## Push branch to github
Git-Command $targetRepoName commit -am "Arcade Validation test branch - version ${arcadeSdkVersion}"
Git-Command $targetRepoName push origin HEAD

## Push branch to AzDO org/project with the official pipeline to build the repo
## Don't need to do this for Roslyn, but we'll need to do it for Runtime. 

## Add default channel from that github repo and branch to "General Testing"
& darc add-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcRepoName --github-pat $githubPAT --password $barToken

## Run an official build of the branch using the official pipeline
$buildId = Invoke-AzDOBuild -buildDefinitionId $buildDefinitionId -branchName $targetBranch -buildParameters $buildParameters

Write-Host "Link to view build: " (Get-BuildLink -buildId $buildId)

## Check build for completion every 5 minutes. 
while("completed" -ne (Get-BuildStatus -buildId $buildId))
{
    Write-Host "Waiting for build to complete..."
    Start-Sleep -Seconds (5*60)
}

## Output summary of references for investigations
Write-Host "Arcade Version: ${arcadeSdkVersion}"
Write-Host "Repository Cloned: ${githubOrg}/${targetRepoName}"
Write-Host "Branch name in repository: ${targetBranch}"
Write-Host "Last Known Good build SHA: ${sha}"

## If build fails, then exit
$buildResult = (Get-BuildResult -buildId $buildId)
if(("failed" -eq $buildResult) -or ("canceled" -eq $buildResult))
{
    Write-Error "Build failed"
    exit
}

## Clean up branch if successful
try
{
    & darc delete-default-channel --channel "General Testing" --branch $darcBranchName --repo $darcRepoName --github-pat $githubPAT --password $barToken
    Git-Command $targetRepoName push origin --delete $targetBranch
}
catch
{
    Write-Warning "Unable to delete default or branch when cleaning up branch"
}