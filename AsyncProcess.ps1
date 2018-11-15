param( [System.Management.Automation.PSCredential]$LoginCredential, [string] $sourceServer, [string] $destinationServer, [string] $instanceName, [string] $destinationInstanceName, [string] $dbName, [string] $ScriptDirectory )

$ScriptDirectory

# region include functions file
try {
    . ("$ScriptDirectory\functions.ps1")
}
catch {
    Write-Host "Error while loading supporting PowerShell Scripts" 
}
#endregion

# region include functions file

    if($instanceName)
    {
        $fullSourceInstanceName = "$sourceServer\$instanceName"
    }
    else
    {
        $fullSourceInstanceName = "$sourceServer"
    }


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

    Start-Sleep -Seconds 5

    SQL_RestoreDatabase -sourceInstance $fullSourceInstanceName -targetInstance $fullDestinationInstanceName -dbName $dbName -backupFilePath "\\$fullDestinationInstanceName\backup\$dbName.bak"

    Start-Sleep -Seconds 5

    $BackupJobName = "LSBackup_$($fullSourceInstanceName.Replace("\","-"))_$($dbName)"
    $CopyJobName = "LSCopy_$($fullDestinationInstanceName.Replace("\","-"))_$($dbName)"
    $RestoreJobName = "LSRestore_$($fullDestinationInstanceName.Replace("\","-"))_$($dbName)"

    $BackupJobName
    $CopyJobName
    $RestoreJobName

    SQL_WriteOutSQLFiles -sourceServer $fullSourceInstanceName -targetServer $fullDestinationInstanceName -dbName $dbName -BackupJobName $BackupJobName -CopyJobName $CopyJobName -RestoreJobName $RestoreJobName -ScriptDirectory $ScriptDirectory

    Start-Sleep -Seconds 5

    Start_SQLAgentJob -SQLServer $fullSourceInstanceName -JobName $BackupJobName

    Start-Sleep -Seconds 3

    Start_SQLAgentJob -SQLServer $fullDestinationInstanceName -JobName $CopyJobName

    Start-Sleep -Seconds 3

    Start_SQLAgentJob -SQLServer $fullDestinationInstanceName -JobName $RestoreJobName

    Start-Sleep -Seconds 3

    SQL_RestoreWithRecovery -targetInstance $fullDestinationInstanceName -dbName $dbName

    Start-Sleep -Seconds 3

    SQL_DisableLogShippingPrimary -targetServer $fullSourceInstanceName -dbName $dbName

    SQL_DisableLogShippingSecondary -targetServer $fullDestinationInstanceName -dbName $dbName

