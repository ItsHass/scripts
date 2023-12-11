clear 

$UserID = Read-Host -Prompt 'Please Enter Username'

# EXPORT SCRIPT 
#Get-ADUser -Identity $UserID -Properties * | export-csv -path userexport.csv

# show script
#Get-ADUser -Identity $UserID -Properties "EmployeeNumber"  | Format-Table EmployeeNumber -A
$Val = Get-ADUser -Identity $UserID -Properties "EmployeeNumber"  | select EmployeeNumber

# VALUE = echo $Val[0].EmployeeNumber

$Clipboard = $Val[0].EmployeeNumber

Set-Clipboard -Value $Clipboard

echo "copied to clipboard - $Clipboard"

pause

& "$PSScriptRoot\GetADUser-Properties-EmployeeNumber.ps1"