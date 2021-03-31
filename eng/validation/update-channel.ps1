Param(
  [string] $maestroEndpoint,
  [string] $barToken,
  [string] $apiVersion = "2018-07-16",
  [string] $targetChannelName = ".NET Eng - Latest",
  [string] $azdoToken,
  [string] $githubToken
)

$ci = $true
. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\..\common\pipeline-logging-functions.ps1
$darc = & "$PSScriptRoot\get-darc.ps1"

function Get-Headers([string]$accept, [string]$barToken) {
    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept',$accept)
    $headers.Add('Authorization',"Bearer $barToken")
    return $headers
}

function Get-AzDO-Build([string]$token, [int]$azdoBuildId) {
    $uri = "https://dev.azure.com/dnceng/internal/_apis/build/builds/${azdoBuildId}?api-version=5.1"
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${token}"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get 
    return $content | ConvertFrom-Json
}

function Get-AzDOHeaders()
{
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${azdoToken}"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    return $headers
}

function Get-LatestBuildResult([PSObject]$repoData)
{
    ## Verified that this API gets completed builds, not in progress builds
    $headers = Get-AzDOHeaders
    $uri = "https://dev.azure.com/$($repoData.azdoOrg)/$($repoData.azdoProject)/_apis/build/latest/$($repoData.buildDefinitionId)?branchName=$($repoData.subscribedBranchName)&api-version=5.1-preview.1"
    $response = (Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json

    ## Report non-green repos for investigation purposes. 
    if(($response.result -ne "succeeded") -and ($response.result -ne "partiallySucceeded"))
    {
        Write-PipelineTaskError -message "The latest build on '$($repoData.subscribedBranchName)' branch for the '$($repoData.githubRepoName)' repository was not successful." -type "warning"
        return $false
    }

    return $true
}

$runtimeRepo = @{
    azdoOrg = 'dnceng';
    azdoProject = 'internal';
    buildDefinitionId = 679;
    githubRepoName = 'runtime';
    subscribedBranchName = 'main'
}
$aspnetcoreRepo = @{
    azdoOrg = 'dnceng';
    azdoProject = 'internal';
    buildDefinitionId = 21;
    githubRepoName = 'aspnetcore';
    subscribedBranchName = 'main'
}
$installerRepo = @{
    azdoOrg = 'dnceng';
    azdoProject = 'internal';
    buildDefinitionId = 286;
    githubRepoName = 'installer';
    subscribedBranchName = 'main'
}

$bellwetherRepos = @($runtimeRepo, $aspnetcoreRepo, $installerRepo)

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName
$getAssetsApiEndpoint = "$maestroEndpoint/api/assets?name=$arcadeSdkPackageName&version=$arcadeSdkVersion&api-version=$apiVersion"
$headers = Get-Headers 'text/plain' $barToken

try {
    # Validate that the "bellwether" repos (runtime, installer, aspnetcore) are green on their main branches
    $results = ($bellwetherRepos | ForEach-Object { Get-LatestBuildResult -repoData $_ })

    if(-not ($results -contains $false)) {
        # Get the Microsoft.DotNet.Arcade.Sdk with the version $arcadeSdkVersion so we can get the id of the build
        $assets = Invoke-WebRequest -Uri $getAssetsApiEndpoint -Headers $headers | ConvertFrom-Json

        if (!$assets) {
            Write-Host "Asset '$arcadeSdkPackageName' with version $arcadeSdkVersion was not found"
            exit 1
        }

        if ($assets.Count -ne 1) {
            Write-Host "More than 1 asset matched the version '$arcadeSdkVersion' of Microsoft.DotNet.Arcade.Sdk. This is not normal. Stopping execution..."
            exit 1
        }

        $buildId = $assets[0].'buildId'

        & $darc add-build-to-channel --id $buildId --channel "$targetChannelName" --github-pat $githubToken --azdev-pat $azdoToken --password $barToken --skip-assets-publishing
        
        if ($LastExitCode -ne 0) {
            Write-Host "Problems using Darc to promote build ${buildId} to channel ${targetChannelName}. Stopping execution..."
            exit 1
        }
    }
    else {
        Write-Host "##vso[task.complete result=SucceededWithIssues;]"
    }
}
catch {
    Write-Host $_
    Write-Host $_.ScriptStackTrace
    exit 1
}
