set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

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
        $commandOutput = & git @gitParams; if ($LASTEXITCODE -ne 0) { throw "Git exited with exit code: $LASTEXITCODE" } else { $commandOutput }
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
    & git clone $githubUri $(Get-Repo-Location $repoName)
    Push-Location -Path $(Get-Repo-Location $repoName)
    & git config user.email "${githubUser}@test.com"
    & git config user.name $githubUser
    Pop-Location
}

function Cleanup-Branch(
	$githubRepoName,
	$branch)
{
	Write-Host "Cleaning up ${global:targetBranch} branch."
	try
	{
		Git-Command $githubRepoName push origin --delete $branch
	}
	catch
	{
		Write-Warning "Unable to delete branch when cleaning up:"
		Write-Warning $_
	}
}