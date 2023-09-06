$word = New-Object -ComObject Word.Application
$doc = $word.Documents.Open('C:\Users\hz306\OneDrive - University of Sussex\Documents\test.docx')
$newfilename = "C:\Users\hz306\OneDrive - University of Sussex\Documents\test2.pdf"

$doc.ExportAsFixedFormat($newfilename,17,$false,0,3,1,1,0,$false, $false,0,$false, $true)
$doc.Close()
$word.Quit()