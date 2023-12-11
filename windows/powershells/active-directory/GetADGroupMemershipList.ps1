clear

$UserID = Read-Host -Prompt 'Please Enter Username'

Get-ADPrincipalGroupMembership -Identity $UserID | select SamAccountName

pause


& "$PSScriptRoot\GetADGroupMemershipList.ps1"