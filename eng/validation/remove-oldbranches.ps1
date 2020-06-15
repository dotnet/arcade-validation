Param(
  [Parameter(Mandatory=$true)][string] $azdoOrg, 
  [Parameter(Mandatory=$true)][string] $azdoProject,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $githubUser,
  [Parameter(Mandatory=$true)][string] $githubPAT,
  [Parameter(Mandatory=$true)][string] $githubOrg,
  [Parameter(Mandatory=$true)][string] $githubRepoName,
  [Parameter(Mandatory=$true)][string] $barToken, 
  [string] $azdoRepoName
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\..\common\darc-init.ps1

$global:arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$global:arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$global:arcadeSdkPackageName
$global:azdoOrg = $azdoOrg
$global:azdoProject = $azdoProject
$global:azdoToken = $azdoToken
$global:githubUser = $githubUser
$global:githubPAT = $githubPAT
$global:githubOrg = $githubOrg
$global:githubRepoName = $githubRepoName
$global:barToken = $barToken
$global:azdoRepoName = if (-not $azdoRepoName) { "" } else { $azdoRepoName }

# Get a temporary directory for a test root. Use the agent work folder if running under azdo, use the temp path if not.
$testRootBase = if ($env:AGENT_WORKFOLDER) { $env:AGENT_WORKFOLDER } else { $([System.IO.Path]::GetTempPath()) }
$testRoot = Join-Path -Path $testRootBase -ChildPath $([System.IO.Path]::GetRandomFileName())
New-Item -Path $testRoot -ItemType Directory | Out-Null

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

## Global Variables
$global:githubUri = "https://${global:githubUser}:${global:githubPAT}@github.com/${global:githubOrg}/${global:githubRepoName}"
$global:azdoUri = "https://${global:githubUser}:${global:azdoToken}@dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:remoteName = ($global:azdoOrg + "-" + $global:azdoRepoName)
$global:branchNamePrefix = "refs/heads/dev/" + $global:githubUser + "/arcade-"
$global:darcAzDORepoName = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:lastBranch = $global:branchNamePrefix + $global:arcadeSdkVersion

Write-Host "Cloning '${global:githubRepoName} from GitHub"
GitHub-Clone $global:githubRepoName

$remoteBranches = @()
Write-Host "Getting remote branches on ${global:githubRepoName} in Azure DevOps"
$remoteBranches = Git-Command $global:githubRepoName ls-remote --heads $global:azdoUri

foreach($remoteBranch in $remoteBranches)
{
    ## Delete all of the old branches except for any that match the current version of Arcade being validated
    if(($remoteBranch -match ".*($global:branchNamePrefix).*") -and -not ($remoteBranch -match ".*($global:lastBranch).*"))
    {
        $branchName = ($remoteBranch -split "`t")[1]
        try
        {
            & darc delete-default-channel --channel "General Testing" --branch $branchName --repo $global:darcAzDORepoName --azdev-pat $global:azdoToken --password $global:bartoken
            Git-Command $global:githubRepoName remote add $remoteName $global:azdoUri
            Git-Command $global:githubRepoName push $remoteName --delete $branchName
        }
        catch
        {
            Write-Warning "Unable to delete default channel or branch when cleaning up"
        }
    }
}