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
  [string] $azdoRepoName,
  [string] $subscribedBranchName
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\..\common\darc-init.ps1

$global:arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$global:arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$global:arcadeSdkPackageName
$global:azdoOrg = $azdoOrg
$global:azdoProject = $azdoProject
$global:buildDefinitionId = $buildDefinitionId
$global:azdoToken = $azdoToken
$global:githubUser = $githubUser
$global:githubPAT = $githubPAT
$global:githubOrg = $githubOrg
$global:githubRepoName = $githubRepoName
$global:barToken = $barToken
$global:buildParameters = if (-not $buildParameters) { "" } else { $buildParameters }
$global:daysOfOldestBuild = if (-not $daysOfOldestBuild) { 3 } else { $daysOfOldestBuild }
$global:pushBranchToGithub = $pushBranchToGithub
$global:azdoRepoName = if (-not $azdoRepoName) { "" } else { $azdoRepoName }

# Get a temporary directory for a test root. Use the agent work folder if running under azdo, use the temp path if not.
$testRootBase = if ($env:AGENT_WORKFOLDER) { $env:AGENT_WORKFOLDER } else { $([System.IO.Path]::GetTempPath()) }
$testRoot = Join-Path -Path $testRootBase -ChildPath $([System.IO.Path]::GetRandomFileName())
New-Item -Path $testRoot -ItemType Directory | Out-Null

$global:minTime = (Get-Date).AddDays(-$global:daysOfOldestBuild)
$global:buildReasonsList = @("batchedCI", "individualCI", "manual")

function Get-LastKnownGoodBuildSha()
{
    ## Have there been any builds in the last $daysOfOldestBuild days? 
    $headers = Get-AzDOHeaders
    $count = 0

    foreach($reason in $global:buildReasonsList)
    {
        $uri = Get-AzDOBuildUri -queryStringParameters "&statusFilter=completed&definitions=${global:buildDefinitionId}&reasonFilter=${reason}&minTime=${global:minTime}&branchName=${global:subscribedBranchName}&`$top=1"
        $reponse = (Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json
        $count += $reponse.count
    }

    ## No? Then get the last known good build regardless of age
    if($count -eq 0)
    {
        $contentArray = Get-Builds
        if($null -eq $contentArray)
        {
            Write-Warning "There were no successful builds on the '${global:subscribedBranchName}' branch for the '${global:githubRepoName}' repository."
        }
        
        return ($contentArray | Sort-Object { $_.value.finishTime } -descending)[0].value.triggerInfo.'ci.sourceSha'
    }

    ## If there have been builds in the last $global:daysOfOldestBuild days, get the last known good build from that time frame
    else
    {
        $count = 0
        $contentArray = Get-Builds -useMinTime
        ## If there are no last known good builds in the last $global:daysOfOldestBuild days, then write a warning. 
        $contentArray | Foreach-Object {$count += $_.count}
        if($count -eq 0)
        {
            Write-Error "There were no successful builds on the '${global:subscribedBranchName}' branch for the '${global:githubRepoName}' repository in the last ${global:daysOfOldestBuild} days."
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

function Invoke-AzDOBuild()
{ 
    $uri = Get-AzDOBuildUri
    $headers = Get-AzDOHeaders

    $body = @{
        "definition"=@{
            "id"=$global:buildDefinitionId
        };
        "sourceBranch"=$global:targetBranch;
    }

    if("" -ne $global:buildParameters)
    {
        $body = $body += @{"parameters"=$global:buildParameters}
    }

    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Body ($body | ConvertTo-Json) -Method Post 
    return ($content | ConvertFrom-Json).id
}

function Get-Builds(
    [switch] $useMinTime
)
{
    $contentArray = @()

    foreach($reason in $global:buildReasonslist)
    {
        $uri = Get-AzDOBuildUri -queryStringParameters "&resultFilter=succeeded&definitions=${global:buildDefinitionId}&reasonFilter=${reason}&branchName=${global:subscribedBranchName}&buildQueryOrder=finishTimeAscending&`$top=1"
        if($useMinTime)
        {
            $uri += "&minTime=${global:minTime}"
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
    $uri = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_apis/build/builds/"
    if(0 -ne $buildId) 
    {
        $uri += $buildId
    }
    
    $uri += "?api-version=5.1" + $queryStringParameters

    return $uri
}

function Get-AzDOHeaders()
{
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${global:azdoToken}"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    return $headers
}

function GitHub-Clone($repoName) 
{
    & git clone $global:githubUri $(Get-Repo-Location $repoName)
    Push-Location -Path $(Get-Repo-Location $repoName)
    & git config user.email "${global:githubUser}@test.com"
    & git config user.name $global:githubUser
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

function Get-SubscribedBranch()
{
    $targetRepoRegex = "${global:githubRepoName}$"
    $subscriptions = darc get-subscriptions --target-repo $targetRepoRegex --source-repo "arcade$" --channel ".NET Eng - Latest" --regex --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken

    if("String" -eq $subscriptions.GetType().Name)
    {
        ## If the repo we're testing against doesn't have a subscription to Arcade in .NET Eng - Latest, then we shouldn't test with it
        Write-Warning "${global:githubRepoName} does not have a subscription to Arcade in '.NET Eng - Latest'"
        exit
    }

    $count = 0
    $subscriptions | foreach { if($_.StartsWith("https://github.com/dotnet/arcade (.NET Eng - Latest)")){ $count++ } }
    if($count -gt 1)
    {
        ## If the repo we're testing against is subscribed to Latest in more than one branch, we won't test it
        Write-Warning "${global:githubRepoName} has more than one branch subscribed to Arcade in '.NET Eng - Latest'"
        exit
    }

    $startBranchName = $subscriptions[0].IndexOf("('") + 2
    $branchNameLength = $subscriptions[0].IndexOf("')") - $startBranchName
    $branchName = $subscriptions[0].Substring($startBranchName, $branchNameLength)

    return $branchName
}

## Global Variables
$global:githubUri = "https://${global:githubUser}:${global:githubPAT}@github.com/${global:githubOrg}/${global:githubRepoName}"
$global:azdoUri = "https://${global:githubUser}:${global:azdoToken}@dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:remoteName = ($global:azdoOrg + "-" + $global:azdoRepoName)
$global:targetBranch = "dev/" + $global:githubUser + "/arcade-" + $global:arcadeSdkVersion
$global:darcBranchName = "refs/heads/" + $global:targetBranch
$global:darcGitHubRepoName = "https://github.com/${global:githubOrg}/${global:githubRepoName}"
$global:darcAzDORepoName = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:darcRepoName = ""
$global:subscribedBranchName = if (-not $subscribedBranchName) { "refs/heads/" + (Get-SubscribedBranch) } else { "refs/heads/${subscribedBranchName}" }

## If able to retrieve a build, get the SHA that it was built from
$sha = Get-LastKnownGoodBuildSha
Write-Host "Last Known Good Build SHA: ${sha}"

## Clone the repo from git
Write-Host "Cloning '${global:githubRepoName} from GitHub"
GitHub-Clone $global:githubRepoName
 
## Check to see if branch exists and clean it up if it does
$branchExists = $false
if($true -eq $global:pushBranchToGithub)
{
    Write-Host "Looking up '${global:targetBranch}' branch on GitHub"
    $branchExists = Git-Command $global:githubRepoName ls-remote --heads $global:githubUri refs/heads/$global:targetBranch
}
else 
{
    Write-Host "Looking up '${global:targetBranch}' branch on Azure DevOps"
    $branchExists = Git-Command $global:githubRepoName ls-remote --heads $global:azdoUri refs/heads/$global:targetBranch
}
if($null -ne $branchExists)
{
    Write-Host "${global:targetBranch} was found. Attempting to clean up."
    try
    {
        if($true -eq $global:pushBranchToGithub)
        {
            & darc delete-default-channel --channel "General Testing" --branch $global:darcBranchName --repo $global:darcGitHubRepoName --github-pat $global:githubPAT --password $global:bartoken
            Git-Command $global:githubRepoName push origin --delete $global:targetBranch
        }
        else
        {
            & darc delete-default-channel --channel "General Testing" --branch $global:darcBranchName --repo $global:darcAzDORepoName --azdev-pat $global:azdoToken --password $global:bartoken
            Git-Command $global:githubRepoName remote add $remoteName $global:azdoUri
            Git-Command $global:githubRepoName push $remoteName --delete $global:targetBranch
        }
    }
    catch
    {
        Write-Warning "Unable to delete default channel or branch when cleaning up"
    }
}

## Create a branch from the repo with the given SHA.
Git-Command $global:githubRepoName checkout -b $global:targetBranch $sha

## Get the BAR Build ID for the version of Arcade we want to use in update-dependecies
$asset = darc get-asset --name $global:arcadeSdkPackageName --version $global:arcadeSdkVersion --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken
$barBuildIdString = $asset | Select-String -Pattern 'BAR Build Id:'
$barBuildId = ([regex]"\d+").Match($barBuildIdString).Value

## Make the changes to that branch to update Arcade - use darc
Set-Location $(Get-Repo-Location $global:githubRepoName)
& darc update-dependencies --id $barBuildId --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken

Git-Command $global:githubRepoName commit -am "Arcade Validation test branch - version ${global:arcadeSdkVersion}"

if($true -eq $global:pushBranchToGithub)
{
    ## Push branch to github
    Git-Command $global:githubRepoName push origin HEAD

    ## Assign darcRepoName value
    $global:darcRepoName = $global:darcGitHubRepoName
}
else
{
    ## Push branch to AzDO org/project with the official pipeline to build the repo
    ## make remote, it might already exist if we had to delete it earlier, so wrapping it in a try/catch
    try
    {
        Git-Command $global:githubRepoName remote add $global:remoteName $global:azdoUri
    }
    catch
    {
        Write-Host "'${global:remoteName}' already exists."
    }
    ## push to remote
    Git-Command $global:githubRepoName push $global:remoteName $global:targetBranch

    ## Assign darcRepoName value
    $global:darcRepoName = $global:darcAzDORepoName
}

## Add default channel from that AzDO repo and branch to "General Testing"
& darc add-default-channel --channel "General Testing" --branch $global:darcBranchName --repo $global:darcRepoName --azdev-pat $global:azdoToken --github-pat $global:githubPAT --password $global:bartoken

## Run an official build of the branch using the official pipeline
Write-Host "Invoking build on Azure DevOps"
$buildId = Invoke-AzDOBuild

## Output summary of references for investigations
Write-Host "Arcade Version: ${global:arcadeSdkVersion}"
Write-Host "BAR Build ID for Arcade: ${barBuildId}"
Write-Host "Repository Cloned: ${global:githubOrg}/${global:githubRepoName}"
Write-Host "Branch name in repository: ${global:targetBranch}"
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
Write-Host "Build was successful. Cleaning up ${global:targetBranch} branch."
try
{
    if($true -eq $global:pushBranchToGithub)
    {
        & darc delete-default-channel --channel "General Testing" --branch $global:darcBranchName --repo $global:darcGitHubRepoName --github-pat $global:githubPAT --password $global:bartoken
        Git-Command $global:githubRepoName push origin --delete $global:targetBranch
    }
    else
    {
        & darc delete-default-channel --channel "General Testing" --branch $global:darcBranchName --repo $global:darcAzDORepoName --azdev-pat $global:azdoToken --password $global:bartoken
        Git-Command $global:githubRepoName push $global:remoteName --delete $global:targetBranch
    }
}
catch
{
    Write-Warning "Unable to delete default channel or branch when cleaning up"
}