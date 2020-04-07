Param(
  [Parameter(Mandatory=$true)][int] $assetId,
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

& darc add-build-to-channel --id $assetId --channel ".NET Eng - Latest" --skip-assets-publishing