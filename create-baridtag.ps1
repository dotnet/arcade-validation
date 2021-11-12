Param(
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $barToken,
  [Parameter(Mandatory=$true)][string] $githubPAT
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\tools.ps1
#. $PSScriptRoot\validation-functions.ps1
$darc = & "$PSScriptRoot\get-darc.ps1"

$global:azdoToken = $azdoToken
$global:githubPAT = $githubPAT
$global:barToken = $barToken

$global:arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$global:arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$global:arcadeSdkPackageName
$global:azdoRepoName = "dotnet-arcade"
$jsonAsset = & $darc get-asset --name $global:arcadeSdkPackageName --version $global:arcadeSdkVersion --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken --output-format json | convertFrom-Json

## Get the BAR Build ID for the version of Arcade we are validating
$barBuildId = $jsonAsset.build.id

Write-Host "##vso[build.addbuildtag]ValidatingBarIds: $barBuildId"