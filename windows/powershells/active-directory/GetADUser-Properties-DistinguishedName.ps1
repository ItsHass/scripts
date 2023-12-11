clear 

$UserID = Read-Host -Prompt 'Please Enter Username'

# EXPORT SCRIPT 
#Get-ADUser -Identity $UserID -Properties * | export-csv -path userexport.csv

# show script
Get-ADUser -Identity $UserID -Properties "DistinguishedName"  | Format-Table DistinguishedName -A


pause

& "$PSScriptRoot\GetADUser-Properties-DistinguishedName.ps1"