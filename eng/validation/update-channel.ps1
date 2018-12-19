Param(
  [string] $maestroEndpoint,
  [string] $barToken,
  [string] $targetChannelName = ".NET Tools - Latest"
)

. $PSScriptRoot\..\common\tools.ps1

function Get-Headers([string]$accept, [string]$barToken) {
    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Accept',$accept)
    $headers.Add('Authorization',"Bearer $barToken")
    return $headers
}

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName
$getAssetsApiEndpoint = "$maestroEndpoint/api/assets?name=$arcadeSdkPackageName&version=$arcadeSdkVersion&api-version=2018-07-16"
$headers = Get-Headers 'text/plain' $barToken

# Get the Microsoft.DotNet.Arcade.Sdk with the version $arcadeSdkVersion so we can get the id of the build
$assets = Invoke-WebRequest -Uri $getAssetsApiEndpoint -Headers $headers | ConvertFrom-Json

if (!$assets) {
    Write-Host "Asset '$arcadeSdkPackageName' with version $arcadeSdkVersion was not found"
    exit 1
}

if ($assets.Count > 1) {
    Write-Host "More than 1 asset matched the version '$arcadeSdkVersion' of Microsoft.DotNet.Arcade.Sdk. This is not normal. Stopping execution..."
    exit 1
}

$getChannelsEndpoint = "$maestroEndpoint/api/channels?api-version=2018-07-16"
$channels = Invoke-WebRequest -Uri $getChannelsEndpoint -Headers $headers | ConvertFrom-Json
$matchedChannel = $($channels | Where-Object -Property "name" -Value "${targetChannelName}" -EQ | Select-Object -Property id)

if (!$matchedChannel) {
    Write-Host "Channel with name '$targetChannelName' was not found..."
    exit 1    
}

$channelId = $matchedChannel.id

try {
    $buildId = $assets[0].'buildId'

    $postBuildIntoChannelApiEndpoint = "$maestroEndpoint/api/channels/$channelId/builds/$buildId/?name=$arcadeSdkPackageName&version=$arcadeSdkVersion&api-version=2018-07-16"
    $headers = Get-Headers 'application/json' $barToken
        
    Write-Host "POSTing to $postBuildIntoChannelApiEndpoint..."
    $postResponse = Invoke-WebRequest -Uri $postBuildIntoChannelApiEndpoint -Headers $headers -Method Post
    Write-Host "Build '$buildId' was successfully added to channel '$channelId'"
}
catch {
    Write-Host $_
    Write-Host $_.ScriptStackTrace
    exit 1
}
