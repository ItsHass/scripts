@echo off
cls
Set /P user=Please Enter Sussex Username:
Set /P drive=Please Enter Drive Letter (g) (t):

if %drive%==g (
net use G: /d 
cls
net use G: https://files.sussex.ac.uk/smbgroup /user:%user% /persistent:yes
)

if %drive%==t (
net use T: /d 
cls
net use T: https://files.sussex.ac.uk/teaching /user:%user% /persistent:yes
)
echo Script End
pause




