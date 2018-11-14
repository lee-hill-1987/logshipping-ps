param( [System.Management.Automation.PSCredential]$LoginCredential, [string] $sourceServer, [string] $destinationServer, [string] $instanceName, [string] $destinationInstanceName, [string] $dbName )

# region include functions file

try {
    . ("C:\scratch\logshipping_ps\functions.ps1")
}
catch {
    Write-Host "Error while loading supporting PowerShell Scripts" 
}
#endregion


$fullSourceInstanceName = "$sourceServer\$instanceName"

if($destinationInstanceName)
{
    $fullDestinationInstanceName = "$destinationServer\$destinationInstanceName"
}
else
{
    $fullDestinationInstanceName = "$destinationServer"
}

Write-host "Starting Processing on $fullSourceInstanceName $dbName to $fullDestinationInstanceName $dbName";
    
SQL_SetRecoveryModel -fullSourceInstanceName $fullSourceInstanceName -dbName $dbName;

SQL_PerformBackup -serverName $destinationServer -instanceName $fullSourceInstanceName -dbName $dbName

"\\$fullDestinationInstanceName\backup\$dbName.bak"

SQL_RestoreDatabase -sourceInstance $fullSourceInstanceName -targetInstance $fullDestinationInstanceName -dbName $dbName -backupFilePath "\\$fullDestinationInstanceName\backup\$dbName.bak"