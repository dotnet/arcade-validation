Param(
  [Parameter(Mandatory=$true)][string] $barToken,
  [string] $sourceChannelName = '.NET Eng - Validation'
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\common\tools.ps1
$darc = & "$PSScriptRoot\validation\get-darc.ps1"

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName
$assetData = & $darc get-asset --name $arcadeSdkPackageName --version $arcadeSdkVersion --channel "$sourceChannelName" --password $bartoken --output-format json | convertFrom-Json

# Get the BAR Build ID for the version of Arcade we are validating
$barBuildId = $assetData.build.id
$azdoBuildId = $assetData.build.azdoBuildId

Write-Host "##vso[build.addbuildtag]ValidatingBarIds $barBuildId"
Write-Host "##vso[build.addbuildtag]ValidatingAzDOBuild $azdoBuildId"