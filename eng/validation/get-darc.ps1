$path = "$PSScriptRoot\darc\$(New-Guid)"

& $PSScriptRoot\..\common\darc-init.ps1 -toolpath $path | Out-Host

return "$path\darc.exe"
