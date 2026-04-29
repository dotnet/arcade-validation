set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

# Audit logging module is loaded by calling scripts; provide a no-op fallback if not loaded
if (-not (Get-Command Write-AuditLog -ErrorAction SilentlyContinue)) {
    . $PSScriptRoot\audit-logging.ps1
}

# Get a temporary directory for a test root. Use the agent work folder if running under azdo, use the temp path if not.
$testRootBase = if ($env:AGENT_WORKFOLDER) { $env:AGENT_WORKFOLDER } else { $([System.IO.Path]::GetTempPath()) }
$testRoot = Join-Path -Path $testRootBase -ChildPath $([System.IO.Path]::GetRandomFileName())
New-Item -Path $testRoot -ItemType Directory | Out-Null

function Get-Repo-Location($repoName){ "$testRoot\$repoName" }

function Git-Command($repoName) {
    Push-Location -Path $(Get-Repo-Location($repoName))
    try {
        $gitParams = $args
        if ($gitParams.GetType().Name -ne "Object[]") {
            $gitParams = $gitParams.ToString().Split(" ")
        }
        Write-Host "Running 'git $gitParams' from $(Get-Location)"
        $commandOutput = & git @gitParams; if ($LASTEXITCODE -ne 0) { throw "Git exited with exit code: $LASTEXITCODE - $commandOutput " } else { $commandOutput }

        $commandOutput
    }
    finally {
        Pop-Location
    }
}

function GitHub-Clone(
	$repoName,
	$githubUser,
	$githubUri) 
{
    & git clone -c core.longpaths=true $githubUri $(Get-Repo-Location $repoName)
    Push-Location -Path $(Get-Repo-Location $repoName)
    & git config user.email "${githubUser}@test.com"
    & git config user.name $githubUser
    Pop-Location
    Write-AuditLog -OperationName "GitCloneWithCredentials" -OperationCategory "ResourceManagement" -OperationType "Read" `
        -OperationResult "Success" -TargetResourceType "GitRepository" -TargetResourceId $repoName
}

function Cleanup-Branch(
	$githubRepoName,
	$branch)
{
	Write-Host "Cleaning up ${global:targetBranch} branch."
	try
	{
		Git-Command $githubRepoName push origin --delete $branch
		Write-AuditLog-BranchOperation -Repository $githubRepoName -BranchName $branch -OperationType "Delete" -Result "Success"
	}
	catch
	{
		Write-AuditLog-BranchOperation -Repository $githubRepoName -BranchName $branch -OperationType "Delete" -Result "Failure" `
			-ResultDescription "$_"
		Write-Warning "Unable to delete branch when cleaning up:"
		Write-Warning $_
	}
}