clear 
echo "This script counts users in a particular group."
echo ""
$UserID = Read-Host -Prompt "Please Enter Group Name "
echo ""
echo "Searching: $UserID  ......"
echo ""

$Total = (Get-ADGroupMember -Identity "$UserID")
$TotalC = $Total.count

echo "Total Users: $TotalC"

echo ""
pause

& "$PSScriptRoot\GetADGroupMembers-Count.ps1"