$psscriptroot

if( -not $Credentials)
{
    $Credentials = Get-Credential
}

$csv = Import-Csv "C:\scratch\servers.csv"

foreach($line in $csv)
{
    Write-host ""
    Write-host "Starting Processing on "$line.SourceServer"."$line.DatabaseName
    
    Start-Job -FilePath C:\scratch\logshipping_ps\AsyncProcess.ps1 -ArgumentList $Credentials, $line.SourceServer,$line.DestinationServer, $line.InstanceName, $line.DestInstanceName, $line.DatabaseName
}

Get-Job | % { Receive-Job $_.Id;}#Remove-Job -Force $_.Id;}
