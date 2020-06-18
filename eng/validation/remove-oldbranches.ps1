Param(
  [Parameter(Mandatory=$true)][string] $azdoOrg, 
  [Parameter(Mandatory=$true)][string] $azdoProject,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $user,
  [Parameter(Mandatory=$true)][string] $barToken, 
  [string] $azdoRepoName
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\..\common\darc-init.ps1

# Get a temporary directory for a test root. Use the agent work folder if running under azdo, use the temp path if not.
$testRootBase = if ($env:AGENT_WORKFOLDER) { $env:AGENT_WORKFOLDER } else { $([System.IO.Path]::GetTempPath()) }
$testRoot = Join-Path -Path $testRootBase -ChildPath $([System.IO.Path]::GetRandomFileName())
New-Item -Path $testRoot -ItemType Directory | Out-Null

$global:arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$global:arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$global:arcadeSdkPackageName
$global:azdoOrg = $azdoOrg
$global:azdoProject = $azdoProject
$global:azdoToken = $azdoToken
$global:user = $user
$global:barToken = $barToken
$global:azdoRepoName = if (-not $azdoRepoName) { "" } else { $azdoRepoName }
$global:azdoUri = "https://${global:user}:${global:azdoToken}@dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:branchNamePrefix = "dev/" + $global:user + "/arcade-"
$global:darcAzDORepoName = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:lastBranch = "refs/heads/" + $global:branchNamePrefix + $global:arcadeSdkVersion

function Get-AzDOHeaders()
{
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${global:azdoToken}"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    return $headers
}

function Get-AzDOGitReposUri(
    [string] $queryStringParameters
)
{
    $uri = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_apis/git/repositories/${global:azdoRepoName}/refs"
    $uri += "?api-version=5.1" + $queryStringParameters

    return $uri
}

function Get-Branches()
{
    $queryStringParameters = "&filter=heads/&filterContains=${global:branchNamePrefix}"
    $uri = (Get-AzDOGitReposUri -queryStringParameters $queryStringParameters)
    $headers = Get-AzDOHeaders
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Method Get 
    return ($content | ConvertFrom-Json).value
}

function Remove-AzDOBranches($body)
{ 
    $uri = Get-AzDOGitReposUri
    $headers = Get-AzDOHeaders

    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Body (ConvertTo-Json $body) -Method Post 
    return ($content | ConvertFrom-Json).value
}

Write-Host "Getting remote branches for '${global:azdoRepoName}' on Azure DevOps"
$remoteBranches = (Get-Branches)

if($null -ne $remotebranches)
{
    $jsonBodyArray = @()

    foreach($remoteBranch in $remoteBranches)
    {
        $branchName = $remoteBranch.name

        # we want to retain the branch with the current version of Arcade in case it's still being used for investigation purposes. 
        if($branchName -ne $global:lastBranch)
        {
            $oldObjectId = $remoteBranch.objectId
            $json = @{
                "name"=$branchName;
                "oldObjectId"=$oldObjectId;
                "newObjectId"="0000000000000000000000000000000000000000"
            }
            
            $jsonBodyArray += $json

            Write-Host "Sending '${branchName}' to AzDO API to be deleted"
            Write-Host "Delete default channel and branch for branch named '${branchName}'"
            & darc delete-default-channel --channel "General Testing" --branch $branchName --repo $global:darcAzDORepoName --azdev-pat $global:azdoToken --password $global:bartoken
        }
    }

    $results = Remove-AzDOBranches($jsonBodyArray)

    if($null -ne $results)
    {
        foreach($result in $results)
        {
            $branchName = $result.name
            $updateStatus = $result.updateStatus

            if(-not $result.success)
            {
                Write-Warning "Deleting branch '${branchName}' was not successful: '${updateStatus}'"
            }
        }
    }
}
else 
{
    Write-Host "There were no branches to clean up in ${global:azdoRepoName}"
}