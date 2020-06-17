
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