$dir = "C:\Users\hz306\OneDrive - University of Sussex\Documents"
$newDir = "C:\Users\hz306\OneDrive - University of Sussex\Documents"

Copy-Item "$dir\test.docx" -Destination "$dir\test00.docx"


$word = New-Object -ComObject Word.Application
#$doc = $word.Documents.Open("$dir\test.docx")

$newdoc = $word.Documents.Open("$dir\test00.docx")
$doc.password = 'password'

#$newfilename = "C:\Users\hz306\OneDrive - University of Sussex\Documents\test2.pdf"

#$doc.ExportAsFixedFormat($newfilename,17,$false,0,3,1,1,0,$false, $false,0,$false, $true)

$doc.Close()
$word.Quit()