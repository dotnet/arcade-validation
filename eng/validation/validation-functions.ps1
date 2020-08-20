set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

# Get a temporary directory for a test root. Use the agent work folder if running under azdo, use the temp path if not.
$testRootBase = if ($env:AGENT_WORKFOLDER) { $env:AGENT_WORKFOLDER } else { $([System.IO.Path]::GetTempPath()) }
$testRoot = Join-Path -Path $testRootBase -ChildPath $([System.IO.Path]::GetRandomFileName())
New-Item -Path $testRoot -ItemType Directory | Out-Null

function Get-LatestBuildSha(
	$azdoOrg, 
	$azdoProject, 
	$buildDefinitionId, 
	$subscribedBranchName, 
	$githubRepoName)
{
    ## Verified that this API gets completed builds, not in progress builds
    $headers = Get-AzDOHeaders
    $uri = "https://dev.azure.com/$azdoOrg/$azdoProject/_apis/build/latest/$buildDefinitionId?branchName=$subscribedBranchName&api-version=5.1-preview.1"
    $response = (Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json

    ## Report non-green repos for investigation purposes. 
    if(($response.result -ne "succeeded") -and ($response.result -ne "partiallySucceeded"))
    {
        Write-Host "##vso[task.setvariable variable=buildStatus;isOutput=true]NoLKG"
        Write-Warning "The latest build on '$subscribedBranchName' branch for the '$githubRepoName' repository was not successful."
    }

    if("" -eq $response.triggerInfo)
    {
        return $response.sourceVersion
    }
    else 
    {
        return $response.triggerInfo.'ci.sourceSha'
    }
}

function Get-AzDOHeaders(
	$azdoToken)
{
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$azdoToken"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    return $headers
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
