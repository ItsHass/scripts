$Word = New-Object -ComObject Word.Application

$FindText = "hello test" # <= Find this text
$ReplaceText = "hello haha" # <= Replace it with this text

$MatchCase = $false
$MatchWholeWorld = $true
$MatchWildcards = $false
$MatchSoundsLike = $false
$MatchAllWordForms = $false
$Forward = $false
$Wrap = 1
$Format = $false
$Replace = 2

$workingdir = "C:\Users\hz306\OneDrive - University of Sussex\Documents"

$WordFile = "$workingdir\test.docx"

    $Document = $Word.Documents.Open($WordFile)
    
    # Find and replace the text using the variables we just setup
    $Document.Content.Find.Execute($FindText, $MatchCase, $MatchWholeWorld, $MatchWildcards, $MatchSoundsLike, $MatchAllWordForms, $Forward, $Wrap, $Format, $ReplaceText, $Replace)
    
    # Save and close the document
    $Document.Close(-1) # The -1 corresponds to https://docs.microsoft.com/en-us/office/vba/api/word.wdsaveoptions

$Word.Quit()