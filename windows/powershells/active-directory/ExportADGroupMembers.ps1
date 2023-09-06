clear
import-module ActiveDirectory
$GroupID = Read-Host -Prompt 'Please Enter Group Name'

echo Processing...
Get-ADGroupMember -identity $GroupID | select name | Export-csv -path "GroupExport_$GroupID.csv" -Notypeinformation

echo Completed !
pause
