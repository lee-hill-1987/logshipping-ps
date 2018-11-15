param ( [Parameter(Mandatory=$true)][string] $csvFile )

$csv = Import-Csv $csvfile

$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$asyncscript = $("$ScriptDirectory\AsyncProcess.ps1")
#$asyncscript = $("$psscriptroot\AsyncProcess.ps1")

$asyncscript

if( -not $Credentials)
{
    $Credentials = Get-Credential
}

$csv
$asyncscript

foreach($line in $csv)
{
    Write-host ""
    Write-host "Starting Processing on "$line.SourceServer"."$line.DatabaseName
    
    Start-Job -FilePath $asyncscript -ArgumentList $Credentials, $line.SourceServer,$line.DestinationServer, $line.InstanceName, $line.DestInstanceName, $line.DatabaseName, $ScriptDirectory
}

Start-Sleep -Seconds 45
Get-Job | % { Receive-Job $_.Id }
