$Word = New-Object -ComObject Word.Application

# Search for all Word document types (.doc, .docx, .doct, etc.)
$WordFiles = Get-ChildItem -Recurse | ? Name -like "template.do[c,t]*"

$FindText = "%username%" # <= Find this text
$ReplaceText = "TestUsername" # <= Replace it with this text

$MatchCase = $false
$MatchWholeWorld = $true
$MatchWildcards = $false
$MatchSoundsLike = $false
$MatchAllWordForms = $false
$Forward = $false
$Wrap = 1
$Format = $false
$Replace = 2

foreach($WordFile in $WordFiles) {
	# Open the document
    $Document = $Word.Documents.Open($WordFile.FullName)
    
    # Find and replace the text using the variables we just setup
    $Document.Content.Find.Execute($FindText, $MatchCase, $MatchWholeWorld, $MatchWildcards, $MatchSoundsLike, $MatchAllWordForms, $Forward, $Wrap, $Format, $ReplaceText, $Replace)
    
    # Save and close the document
    $Document.Close(-1) # The -1 corresponds to https://docs.microsoft.com/en-us/office/vba/api/word.wdsaveoptions
}

$Word.Quit()