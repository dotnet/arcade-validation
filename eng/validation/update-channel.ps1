Param(
  [string] $maestroEndpoint,
  [string] $barToken,
  [int] $channelId = 2             # channel 2 maps to  ".NET Tools - Latest" in Prod
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
$getAssetApiEndpoint = "$maestroEndpoint/api/assets?name=$arcadeSdkPackageName&version=$arcadeSdkVersion&api-version=2018-07-16"
$headers = Get-Headers 'text/plain' $barToken

# Get the Microsoft.DotNet.Arcade.Sdk with the version $arcadeSdkVersion so we can get the id of the build
$assets = Invoke-WebRequest -Uri $getAssetApiEndpoint -Headers $headers | ConvertFrom-Json

if ($assets) {
    # Today, there shouldn't be more that one build linked to a given Arcade SDK version, but if in the future we only bump the version if
    # changes were done that could be a possibility. Also, since we already validated version $arcadeSdkVersion we move all the builds that
    # produced it to channel $channelId
    foreach ($asset in $assets) {
        try {
            $buildId = $asset[0].'buildId'

            $postBuildIntoChannelApiEndpoint = "$maestroEndpoint/api/channels/$channelId/builds/$buildId/?name=$arcadeSdkPackageName&version=$arcadeSdkVersion&api-version=2018-07-16"
            $headers = Get-Headers 'application/json' $barToken
        
            Write-Host "POSTing to $postBuildIntoChannelApiEndpoint..."
            $postResponse = Invoke-WebRequest -Uri $postBuildIntoChannelApiEndpoint -Headers $headers -Method Post
            Write-Host "Build '$buildId' was successfully added to channel '$channelId'"
         }
        catch {
            Write-Host $_
            Write-Host $_.ScriptStackTrace
        }
    }
} else {
    Write-Host "Asset '$arcadeSdkPackageName' with version $arcadeSdkVersion was not found"
    exit 1
}