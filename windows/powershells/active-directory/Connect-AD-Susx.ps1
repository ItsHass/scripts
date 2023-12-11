$PSDefaultParameterValues['*-AD*:Server'] = 'ad.susx.ac.uk'
$PSDefaultParameterValues.Add('Get-ADUser:server', 'ad.susx.ac.uk')
$PSDefaultParameterValues.Add('Get-AD*:server', 'ad.susx.ac.uk')

$PSDefaultParameterValues


pause