#require -Version 7.0

$env:EDITOR = "code --wait"

Invoke-Expression (&starship init powershell)

Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) })