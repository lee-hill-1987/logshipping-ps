function SQL_SetRecoveryModel{
    param([string] $fullSourceInstanceName, [string] $dbName )

        Write-host "setting recovery on $fullSourceInstanceName.$dbName"    
        Invoke-Sqlcmd -Query "ALTER database $dbName SET RECOVERY FULL;" -ServerInstance $fullSourceInstanceName
    }

function SQL_PerformBackup{
    param([string] $serverName, [string] $instanceName, [string] $dbName )
            
        Write-host "Performing Full Backup on $instanceName.$dbName"
        
        $backupFilePath = "\\$serverName\backup\$dbName.bak"

        $query = "backup database $dbName to disk = '\\$serverName\backup\$dbName.bak'"

        Invoke-Sqlcmd -ServerInstance $instanceName -Query $query
    }
        
function SQL_RestoreDatabase{
    param([string] $sourceInstance, [string] $targetInstance, [string] $dbName, [string] $backupFilePath)

    $datafiles = Invoke-Sqlcmd -ServerInstance $sourceInstance -Database $dbName -Query “select name, physical_name from sys.master_files where name like '%$dbName%' and type = 0”
    $logfiles = Invoke-Sqlcmd -ServerInstance $sourceInstance -Database $dbName -Query “select name, physical_name from sys.master_files where name like '%$dbName%' and type = 1”

    $datafile = $datafiles.name
    $logfile = $logfiles.name

    $datafilepath = "F:\Data\$datafile.mdf"
    $logfilepath = "F:\Logs\$logfile.ldf"

    $query = "restore database $dbName from disk = '\\$targetInstance\backup\$dbName.bak' with norecovery, move '$datafile' TO '$datafilepath',  move '$logfile' TO '$logfilepath' , replace"
    
    $targetInstance
    $query

    Invoke-Sqlcmd -ServerInstance $targetInstance -Query $query
}


