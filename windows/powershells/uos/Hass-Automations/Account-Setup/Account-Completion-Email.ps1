clear
###### GET CURRENT WORKING DIRECTORY ###
function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}
$dir = Get-ScriptDirectory
###### GET CURRENT WORKING DIRECTORY ###

### START OUTLOOK ###
$Outlook = New-Object -comObject Outlook.Application
$CustomerName = Read-Host -Prompt 'Please Enter Customer First Name'
$EmailAddress = Read-Host -Prompt 'Please Enter Email Address'
Write-Host "Type '1' = VPN Only"
Write-Host "Type '2' = VPN + CMS"
$Options = Read-Host -Prompt "Type '3' = CMS Only"
if ( $Options -ieq '1' )
{
$VPN_PW = Read-Host -Prompt 'Please Enter VPN Password'
$Email_Body = "Hello $CustomerName,
<br><br>
Welcome to Sussex - Thank you for collecting your username and password from IT Services. Your manager has requested VPN access for you so that you can access certain services (CMS, Cognos, Remote Desktop) from off-site. 
<br><hr>
The instructions for how to connect to the VPN can be found below but, as you are a new member of staff, you will not be able to complete step 1. Rather than working out your VPN setup password as indicated in step 1 please use the temporary password below.
<br><br><strong>Temporary VPN Password:</strong> $VPN_PW
<br>
<strong>VPN Instructions:</strong> https://sussex.box.com/s/qlrh6efwtrj0kw8h36m6bm1056gf7ykd
<br><hr>
<strong>Opening Links In IE Mode:</strong> https://sussex.box.com/s/jn3sqj9xvk6280fgrwxw87uaz9zt9kvt
<hr>
<br><br>
Kind Regards<br>
ITS Service Desk Team"
$Subject = 'Initial VPN Password'
}
if ( $Options -ieq '2' )
{
$VPN_PW = Read-Host -Prompt 'Please Enter VPN Password'
$CMS_PW = Read-Host -Prompt 'Please Enter CMS Password'
$Email_Body = "Hello $CustomerName,
<br><br>
Welcome to Sussex - Thank you for collecting your username and password from IT Services. Your manager has requested VPN access for you so that you can access certain services (CMS, Cognos, Remote Desktop) from off-site. 
<br><hr>
The instructions for how to connect to the VPN can be found below but, as you are a new member of staff, you will not be able to complete step 1. Rather than working out your VPN setup password as indicated in step 1 please use the temporary password below.
<br><br><strong>Temporary VPN Password:</strong> $VPN_PW
<br>
<strong>VPN Instructions:</strong> https://sussex.box.com/s/qlrh6efwtrj0kw8h36m6bm1056gf7ykd
<br><hr>
<strong>CMS Instructions:</strong> https://sussex.box.com/s/q7h2ceb2b54fhg5es5bk8xxx4v8ovb3m
<br><strong>Temporary CMS Password:</strong> $CMS_PW
<br><hr>
<strong>Opening Links In IE Mode:</strong> https://sussex.box.com/s/jn3sqj9xvk6280fgrwxw87uaz9zt9kvt
<hr>
<br><br>
Kind Regards<br>
ITS Service Desk Team"

$Subject = 'Initial VPN & CMS Password'
}
if ( $Options -ieq '3' )
{
$CMS_PW = Read-Host -Prompt 'Please Enter CMS Password'
$Email_Body = "Hello $CustomerName,
<br><br>
Welcome to Sussex - Thank you for collecting your username and password from IT Services. Your manager has requested CMS access for you so below are your temporary login details.
<br><hr>
<strong>CMS Instructions:</strong> https://sussex.box.com/s/q7h2ceb2b54fhg5es5bk8xxx4v8ovb3m
<br><strong>Temporary CMS Password:</strong> $CMS_PW
<br><hr>
<br><br>
Kind Regards<br>
ITS Service Desk Team"

$Subject = 'Initial CMS Password'
}
##### CREATE OUTLOOK ITEM###
$TlabEmail = $Outlook.CreateItem(0)
#$TlabEmail.From = "computer.account.manager@sussex.ac.uk"
#$TlabEmail.Attachments.Add("$dir\URL_IN_EDGE_W10.pdf")
$TlabEmail.To = $EmailAddress
$TlabEmail.HTMLBody = $Email_Body
$TlabEmail.Subject = $Subject
$TlabEmail.save()
$inspector = $TlabEmail.GetInspector
$inspector.Display()
##### CREATE OUTLOOK ITEM###

pause
& "$PSScriptRoot\Account-Completion-Email.ps1"