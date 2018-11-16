function SQL_SetRecoveryModel{
    param([string] $fullSourceInstanceName, [string] $dbName )

        [string](get-date) + ": setting recovery on $fullSourceInstanceName.$dbName"    
        Invoke-Sqlcmd -Query "ALTER database $dbName SET RECOVERY FULL;" -ServerInstance $fullSourceInstanceName -QueryTimeout 1000
    }

function SQL_PerformBackup{
    param([string] $serverName, [string] $instanceName, [string] $dbName )
            
        [string](get-date) + ": Performing Full Backup on $instanceName.$dbName"
        
        $backupFilePath = "\\$serverName\backup\$dbName.bak"

        $query = "backup database $dbName to disk = '\\$serverName\backup\$dbName.bak'"

        Invoke-Sqlcmd -ServerInstance $instanceName -Query $query -QueryTimeout 1000
    }
        
function SQL_RestoreDatabase{
    param([string] $sourceInstance, [string] $targetInstance, [string] $dbName, [string] $backupFilePath)

    [string](get-date) + ": restoring Backup on $targetInstance.$dbName"

    $datafiles = Invoke-Sqlcmd -ServerInstance $sourceInstance -Database $dbName -Query “select mf.name from master.sys.master_files mf inner join sys.databases db  on db.database_id = mf.database_id where db.name like '%$dbName%' and type = 0”
    $logfiles = Invoke-Sqlcmd -ServerInstance $sourceInstance -Database $dbName -Query “select mf.name from master.sys.master_files mf inner join sys.databases db  on db.database_id = mf.database_id where db.name like '%$dbName%' and type = 1”

    $datafile = $datafiles.name
    $logfile = $logfiles.name
    

    $query = "
    
    exec sys.sp_configure @configname = 'show advanced options', @configvalue = 1;
        reconfigure;
        exec sp_configure @configname = 'xp_cmdshell', @configvalue = 1;
        reconfigure;
    
        restore database $dbName from disk = '\\"+$targetInstance+"\backup\"+$dbName+".bak' with norecovery, move '"+$datafile+"' TO 'F:\Data\"+$dbName+".mdf',  move '"+$logfile+"' TO 'F:\Log\"+$dbName+"_log.ldf' , replace;
    
        if @@error = 0 
        begin
            exec master.dbo.xp_cmdshell 'del \\"+$targetInstance+"\backup\"+$dbName+".bak'
        end;
    "
    
    $query

    Invoke-Sqlcmd -ServerInstance $targetInstance -Query $query -QueryTimeout 1000
}

function SQL_RestoreWithRecovery{
    param($targetInstance, [string] $dbName)

     [string](get-date) + ": setting recovery on $targetInstance.$dbName"    
        Invoke-Sqlcmd -Query "restore database $dbName with RECOVERY;" -ServerInstance $targetInstance -QueryTimeout 1000
}



function SQL_DisableLogShipping {
    param($sourceServer, $targetServer, $dbName)

    [string](get-date) + ": removing log shipping config"

    $query = 
    "
         EXEC master.dbo.sp_delete_log_shipping_primary_secondary @primary_database = '"+$dbName+"', @secondary_server = '"+$targetServer+"', @secondary_database = '"+$dbName+"'
    "

    Invoke-Sqlcmd -ServerInstance $sourceServer -Query $query -QueryTimeout 1000

    $query = 
    "   
        exec master.sys.sp_delete_log_shipping_secondary_database
            @secondary_database = '"+$dbName+"'  -- sysname
           ,@ignoreremotemonitor = 1
    "
    Invoke-Sqlcmd -ServerInstance $targetServer -Query $query -QueryTimeout 1000

    $query = 
    "  
        EXEC master.dbo.sp_delete_log_shipping_primary_database @database = '"+$dbName+"'
     "
    Invoke-Sqlcmd -ServerInstance $sourceServer -Query $query -QueryTimeout 1000

     $query = 
    " 
        exec master.dbo.sp_delete_log_shipping_secondary_primary
           @primary_server = '"+$sourceServer+"'
          ,@primary_database = '"+$dbName+"'
    "
    Invoke-Sqlcmd -ServerInstance $sourceServer -Query $query -QueryTimeout 1000

}

function SQL_DisableLogShippingSecondary {
    param($sourceServer, $targetServer, $dbName)

    [string](get-date) + ": removing log shipping Secondary config"

    $query = 
    "    
       exec master.dbo.sp_delete_log_shipping_secondary_primary
           @primary_server = '"+$sourceServer+"'
          ,@primary_database = '"+$dbName+"';
   
    "

    Invoke-Sqlcmd -ServerInstance $targetServer -Query $query -QueryTimeout 1000

}

function Start_SQLAgentJob
{

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$SQLServer ,
        [Parameter(Mandatory=$true)][string]$JobName
    )

    [string](get-date) + ": running Job: "+ $JobName
    
    # Load the SQLPS module
    Push-Location; Import-Module SQLPS -DisableNameChecking; Pop-Location

    $ServerObj = New-Object Microsoft.SqlServer.Management.Smo.Server($SQLServer)
    $ServerObj.ConnectionContext.Connect()
    $JobObj = $ServerObj.JobServer.Jobs | Where-Object {$_.Name -eq $JobName}
    $JobObj.Refresh()

    # If the job is and enabled and not currently executing start it
    if ($JobObj.CurrentRunStatus -ne "Executing") {
        $JobObj.Start()
    }

    # Wait until the job completes. Check every second.
    do {
        Start-Sleep -Seconds 1
        # You have to run the refresh method to reread the status
        $JobObj.Refresh()
    } While ($JobObj.CurrentRunStatus -eq "Executing")

    # Get the run duration by adding all of the step durations
    $RunDuration = 0
    foreach($JobStep in $JobObj.JobSteps)     {
        $RunDuration += $JobStep.LastRunDuration
    }

    $JobObj | select Name,CurrentRunStatus,LastRunOutcome,LastRunDate,@{Name="LastRunDurationSeconds";Expression={$RunDuration}}
}


function SQL_WriteOutSQLFiles{
param ([string] $sourceServer,  [string] $targetServer, [string] $dbName, $BackupJobName, $CopyJobName, $RestoreJobName, $ScriptDirectory)

[string](get-date) + ": writing out SQL logshipping config files"

$source = "$($sourceServer.Replace("\","-"))_$($dbName)"
$target = "$($targetServer.Replace("\","-"))_$($dbName)"

$primarytext = 
"
DECLARE @LS_BackupJobId	AS uniqueidentifier 
DECLARE @LS_PrimaryId	AS uniqueidentifier 
DECLARE @SP_Add_RetCode	As int 


EXEC @SP_Add_RetCode = master.dbo.sp_add_log_shipping_primary_database 
		@database = N'$dbName' 
		,@backup_directory = N'\\$targetServer\backup' 
		,@backup_share = N'\\$targetServer\backup' 
		,@backup_job_name = N'LSBackup_$source' 
		,@backup_retention_period = 4320
		,@backup_threshold = 60 
		,@threshold_alert_enabled = 0
		,@history_retention_period = 5760 
		,@backup_job_id = @LS_BackupJobId OUTPUT 
		,@primary_id = @LS_PrimaryId OUTPUT 
		,@overwrite = 1 


IF (@@ERROR = 0 AND @SP_Add_RetCode = 0) 
BEGIN 

DECLARE @LS_BackUpScheduleUID	As uniqueidentifier 
DECLARE @LS_BackUpScheduleID	AS int 


EXEC msdb.dbo.sp_add_schedule 
		@schedule_name =N'LSBackupSchedule_$source' 
		,@enabled = 0 
		,@freq_type = 4 
		,@freq_interval = 1 
		,@freq_subday_type = 4 
		,@freq_subday_interval = 15 
		,@freq_recurrence_factor = 0 
		,@active_start_date = 20181114 
		,@active_end_date = 99991231 
		,@active_start_time = 0 
		,@active_end_time = 235900 
		,@schedule_uid = @LS_BackUpScheduleUID OUTPUT 
		,@schedule_id = @LS_BackUpScheduleID OUTPUT 

EXEC msdb.dbo.sp_attach_schedule 
		@job_id = @LS_BackupJobId 
		,@schedule_id = @LS_BackUpScheduleID  

EXEC msdb.dbo.sp_update_job 
		@job_id = @LS_BackupJobId 
		,@enabled = 0 

END 

EXEC master.dbo.sp_add_log_shipping_primary_secondary 
		@primary_database = N'$dbName' 
		,@secondary_server = N'$targetServer' 
		,@secondary_database = N'$dbName' 
		,@overwrite = 1 
"
$primaryfileName = "$ScriptDirectory\$source.sql"

$primaryfileName
$primarytext | Out-File -FilePath $primaryfileName

Invoke-Sqlcmd -ServerInstance $sourceServer -InputFile $primaryfileName -QueryTimeout 1000

$text = 

"

-- ****** Begin: Script to be run at Secondary: [WS2012-BI] ******

DECLARE @LS_Secondary__CopyJobId	AS uniqueidentifier 
DECLARE @LS_Secondary__RestoreJobId	AS uniqueidentifier 
DECLARE @LS_Secondary__SecondaryId	AS uniqueidentifier 
DECLARE @LS_Add_RetCode	As int 


EXEC @LS_Add_RetCode = master.dbo.sp_add_log_shipping_secondary_primary 
		@primary_server = N'$sourceServer' 
		,@primary_database = N'$dbName' 
		,@backup_source_directory = N'\\$targetServer\backup' 
		,@backup_destination_directory = N'\\$targetServer\backup' 
		,@copy_job_name = N'$CopyJobName' 
		,@restore_job_name = N'$RestoreJobName' 
		,@file_retention_period = 4320 
		,@overwrite = 1 
		,@copy_job_id = @LS_Secondary__CopyJobId OUTPUT 
		,@restore_job_id = @LS_Secondary__RestoreJobId OUTPUT 
		,@secondary_id = @LS_Secondary__SecondaryId OUTPUT 

IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

DECLARE @LS_SecondaryCopyJobScheduleUID	As uniqueidentifier 
DECLARE @LS_SecondaryCopyJobScheduleID	AS int 


EXEC msdb.dbo.sp_add_schedule 
		@schedule_name =N'DefaultCopyJobSchedule' 
		,@enabled = 1 
		,@freq_type = 4 
		,@freq_interval = 1 
		,@freq_subday_type = 4 
		,@freq_subday_interval = 15 
		,@freq_recurrence_factor = 0 
		,@active_start_date = 20181114 
		,@active_end_date = 99991231 
		,@active_start_time = 0 
		,@active_end_time = 235900 
		,@schedule_uid = @LS_SecondaryCopyJobScheduleUID OUTPUT 
		,@schedule_id = @LS_SecondaryCopyJobScheduleID OUTPUT 

EXEC msdb.dbo.sp_attach_schedule 
		@job_id = @LS_Secondary__CopyJobId 
		,@schedule_id = @LS_SecondaryCopyJobScheduleID  

DECLARE @LS_SecondaryRestoreJobScheduleUID	As uniqueidentifier 
DECLARE @LS_SecondaryRestoreJobScheduleID	AS int 


EXEC msdb.dbo.sp_add_schedule 
		@schedule_name =N'DefaultRestoreJobSchedule' 
		,@enabled = 1 
		,@freq_type = 4 
		,@freq_interval = 1 
		,@freq_subday_type = 4 
		,@freq_subday_interval = 15 
		,@freq_recurrence_factor = 0 
		,@active_start_date = 20181114 
		,@active_end_date = 99991231 
		,@active_start_time = 0 
		,@active_end_time = 235900 
		,@schedule_uid = @LS_SecondaryRestoreJobScheduleUID OUTPUT 
		,@schedule_id = @LS_SecondaryRestoreJobScheduleID OUTPUT 

EXEC msdb.dbo.sp_attach_schedule 
		@job_id = @LS_Secondary__RestoreJobId 
		,@schedule_id = @LS_SecondaryRestoreJobScheduleID  


END 


DECLARE @LS_Add_RetCode2	As int 


IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

EXEC @LS_Add_RetCode2 = master.dbo.sp_add_log_shipping_secondary_database 
		@secondary_database = N'$dbName' 
		,@primary_server = N'$sourceServer' 
		,@primary_database = N'$dbName' 
		,@restore_delay = 0 
		,@restore_mode = 0 
		,@disconnect_users	= 0 
		,@restore_threshold = 45   
		,@threshold_alert_enabled = 1 
		,@history_retention_period	= 5760 
		,@overwrite = 1 

END 


IF (@@error = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

EXEC msdb.dbo.sp_update_job 
		@job_id = @LS_Secondary__CopyJobId 
		,@enabled = 0 

EXEC msdb.dbo.sp_update_job 
		@job_id = @LS_Secondary__RestoreJobId 
		,@enabled = 0 
END 

-- ****** End: Script to be run at Secondary: [WS2012-BI] ******

"

$secondaryfileName = "$ScriptDirectory\$target.sql"

$secondaryfileName
$text | Out-File -FilePath $secondaryfileName

Invoke-Sqlcmd -ServerInstance $targetServer -InputFile $secondaryfileName -QueryTimeout 1000

}