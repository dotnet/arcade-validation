Param(
  [string] $sourceChannelName = '.NET Eng - Validation'
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\common\tools.ps1
. $PSScriptRoot\validation\audit-logging.ps1
$darc = Get-Darc

$arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$arcadeSdkPackageName
$assetData = & $darc get-asset `
  --name $arcadeSdkPackageName `
  --version $arcadeSdkVersion `
  --channel "$sourceChannelName" `
  --ci `
  --output-format json `
  | convertFrom-Json

Write-AuditLog -OperationName "QueryBARAssets" -OperationCategory "ResourceManagement" -OperationType "Read" `
    -OperationResult "Success" -TargetResourceType "BAR_Asset" -TargetResourceId "$arcadeSdkPackageName@$arcadeSdkVersion"

# Get the BAR Build ID for the version of Arcade we are validating
$barBuildId = $assetData.build.id
$azdoBuildId = $assetData.build.azdoBuildId

Write-Host "##vso[build.addbuildtag]ValidatingBarIds $barBuildId"
Write-Host "##vso[build.addbuildtag]ValidatingAzDOBuild $azdoBuildId"
Write-AuditLog -OperationName "CreateBuildTag" -OperationCategory "ResourceManagement" -OperationType "Create" `
    -OperationResult "Success" -TargetResourceType "AzdoBuildTag" -TargetResourceId "Bar:$barBuildId/Azdo:$azdoBuildId"
