clear 

$UserID = Read-Host -Prompt 'Please Enter Username'

Get-ADUser -Identity $UserID -Properties *

pause

& "$PSScriptRoot\GetADUser-Properties-All.ps1"