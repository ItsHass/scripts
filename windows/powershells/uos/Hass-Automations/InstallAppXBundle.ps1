clear
## get pathway
$pathway = Read-Host -Prompt 'Please Enter AppX Location'
Add-AppxPackage -Path "$pathway"
pause
& "$PSScriptRoot\InstallAppXBundle.ps1"