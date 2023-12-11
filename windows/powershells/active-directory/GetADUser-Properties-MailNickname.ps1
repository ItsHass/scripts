clear 

$UserID = Read-Host -Prompt 'Please Enter Username'

# EXPORT SCRIPT 
#Get-ADUser -Identity $UserID -Properties * | export-csv -path userexport.csv

# show script
Get-ADUser -Identity $UserID -Properties "mailNickname"  | Format-Table mailNickname -A


pause

& "$PSScriptRoot\GetADUser-Properties-MailNickname.ps1"