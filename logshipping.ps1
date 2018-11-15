param ( [Parameter(Mandatory=$true)][string] $csvFile )

$csv = Import-Csv $csvfile

$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$asyncscript = $("$ScriptDirectory\AsyncProcess.ps1")
$outputfile = $("$ScriptDirectory\output.txt")

"start" | Out-File $outputfile

$asyncscript

if( -not $Credentials)
{
    $Credentials = Get-Credential
}

$csv

foreach($line in $csv)
{
    
    "Starting Processing on "+$line.SourceServer+"."+$line.DatabaseName | Out-File -Append $outputfile
    
    Start-Job -FilePath $asyncscript -ArgumentList $Credentials, $line.SourceServer,$line.DestinationServer, $line.InstanceName, $line.DestInstanceName, $line.DatabaseName, $ScriptDirectory
}

#Start-Sleep -Seconds 45

$asyncscript


while(Get-Job -State Running)
{
    Start-Sleep -Seconds 3
    Get-Job -State Running | % { 

    $outputfile = $("$ScriptDirectory\"+$_.Id+"-output.txt")

    Receive-Job $_.Id | Out-File -Append $outputfile }
}




