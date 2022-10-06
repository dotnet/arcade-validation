$path = "$PSScriptRoot\darc\$(New-Guid)"

& $PSScriptRoot\..\common\darc-init.ps1 -toolpath $path -darcVersion "1.1.0-beta.22220.1" | Out-Host

return "$path\darc.exe"
