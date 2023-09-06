clear
###### GET CURRENT WORKING DIRECTORY ###
function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}
$CurrentDir = Get-ScriptDirectory
###### GET CURRENT WORKING DIRECTORY ###

##### COPY TEMPLATE FILE ##
$toCopyFile = "$CurrentDir\template.docx"
$toCopyNewFile = "$CurrentDir\templateCopy_$(get-date -f yyyy_MM_dd).docx"

if (Test-Path $toCopyNewFile = True) {
  Remove-Item $toCopyNewFile
}

clear

Copy-Item $toCopyFile -Destination $toCopyNewFile
##### COPY TEMPLATE FILE ##

##########################
## get username ## 
$NewUser_Username = Read-Host -Prompt 'Please Enter Username'
##################
## get password ##
$NewUser_Password = Read-Host -Prompt 'Please Enter Password'
##################
## Word file Password ##
$NewUser_WFpassword = Read-Host ("Enter the password for the word file")
##################
$Word = New-Object -ComObject Word.Application

$FindText = "%username%" # <= Find this text
$ReplaceText = $NewUser_Username # <= Replace it with this text

$MatchCase = $false
$MatchWholeWorld = $true
$MatchWildcards = $false
$MatchSoundsLike = $false
$MatchAllWordForms = $false
$Forward = $false
$Wrap = 1
$Format = $false
$Replace = 2

$WordFile = $toCopyNewFile

    $Document = $Word.Documents.Open($WordFile)
    
    # Find and replace the text using the variables we just setup
    $Document.Content.Find.Execute($FindText, $MatchCase, $MatchWholeWorld, $MatchWildcards, $MatchSoundsLike, $MatchAllWordForms, $Forward, $Wrap, $Format, $ReplaceText, $Replace)

#### pw / user ####
$FindText = "%password%" # <= Find this text
$ReplaceText = $NewUser_Password # <= Replace it with this text
 
    # Find and replace the text using the variables we just setup
    $Document.Content.Find.Execute($FindText, $MatchCase, $MatchWholeWorld, $MatchWildcards, $MatchSoundsLike, $MatchAllWordForms, $Forward, $Wrap, $Format, $ReplaceText, $Replace)
echo "Now Making File Passworded..."    
    $Document.password = "$NewUser_WFpassword"
echo "File Passwording Complete"
    # Save and close the document
    $Document.Close(-1) # The -1 corresponds to https://docs.microsoft.com/en-us/office/vba/api/word.wdsaveoptions

$Word.Quit()
##########################

echo "Renaming File"
Rename-Item -Path $WordFile -NewName "$NewUser_Username.docx"
echo "File Renamed to: $NewUser_Username.docx"

pause
& "$PSScriptRoot\CreatePasswordedUserAccountDetails_Docx.ps1"