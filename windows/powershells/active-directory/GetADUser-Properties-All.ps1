﻿clear 

$UserID = Read-Host -Prompt 'Please Enter Username'

# EXPORT SCRIPT 
#Get-ADUser -Identity $UserID -Properties * | export-csv -path userexport.csv

# show script
Get-ADUser -Identity $UserID -Properties *


pause

& "$PSScriptRoot\GetADUser-Properties-All.ps1"