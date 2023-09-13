clear 
echo "This script searches for users that start with... then counts only where the object is enabled."
echo ""
$UserID = Read-Host -Prompt "Please Enter Username "
echo ""
echo "Searching: $UserID"
echo "Active Users Only"
echo ""

$Total = (Get-ADUser -Filter "name -like `"$($UserID+'*')`"" |Where {$_.enabled -eq "True"})
$TotalC = $Total.count

echo "Total Users: $TotalC"

echo ""
pause

& "$PSScriptRoot\SearchQuery-NameLike_EnabledUsers.ps1"