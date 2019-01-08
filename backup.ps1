# ================================================
#
# The log folder is created in the folder .duplicacy/tbp-logs/
#
# If the user wishes (sets the flag to true) and the script is run as an Administrator,
# the backup command will use the -vss flag (Shadow Copy),
# which can only be used as an Administrator.
#
# Thanks to <bassebaba/DuplicacyPowershell> for the initial script which
# inspired this one and from which I borrowed some parts.
#
# The script can be run manually (after setting the correct paths and variable names) like this:
#       powershell -NoProfile -ExecutionPolicy Bypass -File "C:\duplicacy repo\backup.ps1" -Verb RunAs;
#
#
# ================================================


# ================================================
# ================================================
# Import the global and local config files

. "$PSScriptRoot\default_config.ps1"
. "$PSScriptRoot\user_config.ps1"
. "$PSScriptRoot\remote_notifications_util.ps1"
# ================================================


# ================================================
# ================================================
# Various timers keeping time

$timings = @{
    scriptStartTime = 0
    scriptEndTime = 0
    scriptTotalRuntime = 0
}
# ================================================

# ================================================
# ================================================
# Info about log paths
# It is empty now but filled in the function initLoggingOptions

$log = @{ }
# ================================================




# ================================================
# ================================================
# Initialize the script-level duplicacy table.
# It is empty now but filled in the function initDuplicacyOptions

$duplicacy = @{ }
# ================================================

# ================================================
# ================================================
# If there was no error for all the duplicacy command invocations
# $globalSuccessStatus should remain true.

$globalSuccessStatus = $true
# ================================================

function main
{
    # http://www.wallacetech.co.uk/?p=693
    doPreBackupTasks
    # ============================================
    # ============================================

    # ============================================
    # == Execute the commands ==
    if ($runBackup)
    {
        doDuplicacyCommand $duplicacy.backup
    }
    if ($runPrune)
    {
        doDuplicacyCommand $duplicacy.prune
    }
    if ($runCheck)
    {
        doDuplicacyCommand $duplicacy.check
    }
    if ($runCopyToOffsite)
    {
        doDuplicacyCommand $duplicacy.copy
    }
    if ($runPruneOffsite)
    {
        doDuplicacyCommand $duplicacy.pruneOffsite
    }

    warnIfNoCommandsWereExecuted

    # ============================================
    # ============================================
    doPostBackupTasks
}

function doPreBackupTasks()
{
    initDuplicacyOptions

    Push-Location $repositoryFolder

    initLoggingOptions
    createLogFolder
    logStartBackupProcess
    cleanupOlderLogFiles
}

function logStartBackupProcess()
{
    $timings.scriptStartTime = Get-Date
    $startTime = $timings.scriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
    log
    log
    log "================================================================="
    log "==== Starting $scheduledTaskName @ $repositoryFolder"
    log "===="
    log "==== Start time is: $startTime"
    log "================================================================="

    $msg = @"
<code>`n`n`n`n`n`n`n`n
 == Starting $scheduledTaskName @ $repositoryFolder

 = Start time is`: $startTime
</code>
"@
    doRemoteNotifications $msg
}

function cleanupOlderLogFiles()
{
    $logFiles = Get-ChildItem $log.basePath -Directory |  Where-Object { $_.LastWriteTime -lt (Get-Date -Hour 0 -Minute 0 -Second 0) }
    foreach ($folder in $logFiles)
    {
        $fullName = $folder.FullName
        $zipFileName = "$fullName.zip"
        log "Zipping (and then deleting) the folder: $fullName to the zipFile: $zipFileName"
        Compress-Archive -Path $fullName -DestinationPath $zipFileName -CompressionLevel Optimal -Update

        if ($IsLinux -Or $IsMacOS)
        {
            log "OS is NOT Windows => deleting the folder"
            # w/o -Verbose there is no output
            # w/o output redirect *>&1 the output dooesn't go to Tee-Object
            doCall { Remove-Item -Path $fullName -Recurse -Verbose *>&1 }
        }
        else
        {
            log "OS is Windows => sending file to Recycle Bin"
            $shell = New-Object -ComObject "Shell.Application"
            $item = $shell.Namespace(0).ParseName("$fullName")
            $item.InvokeVerb("delete")
        }
    }
}

function doPostBackupTasks()
{
    logFinishBackupProcess

    Pop-Location
}

function logFinishBackupProcess()
{
    $timings.scriptEndTime = Get-Date
    $timings.scriptTotalRuntime = New-Timespan -Start $timings.scriptStartTime -End $timings.scriptEndTime
    $startTime = $timings.scriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
    $endTime = $timings.scriptEndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $logFilePath = (Resolve-Path -Path $log.filePath).Path

    $successStatusString = successStatusAsString $globalSuccessStatus

    log "================================================================="
    log "==== Finished($successStatusString) $scheduledTaskName @ $repositoryFolder"
    log "===="
    log "==== Start time is: $startTime"
    log "==== End   time is: $endTime"
    log "===="
    log ("==== Total runtime: {0} Hours {1} Minutes {2} Seconds" -f [int]($timings.scriptTotalRuntime.TotalHours), $timings.scriptTotalRuntime.Minutes, $timings.scriptTotalRuntime.Seconds)
    log "==== logFile is: $logFilePath"
    log "================================================================="

    $msg = @"
<code>`n
 == Finished($successStatusString) $scheduledTaskName @ $repositoryFolder

 = Start time is: $startTime
 = End   time is: $endTime

 = Total runtime: {0} Hours {1} Minutes {2} Seconds

 = logFile is: $logFilePath
</code>
"@ -f [int]($timings.scriptTotalRuntime.TotalHours), $timings.scriptTotalRuntime.Minutes, $timings.scriptTotalRuntime.Seconds

    doRemoteNotifications $msg
}



function doDuplicacyCommand($arg)
{
    $command = $duplicacy.command + $arg
    log "==="
    log "=== Now executting $command"
    log "==="

    doRemoteNotifications "<code> = Now executting $command</code>"

    doCall $duplicacy.exe (-split $duplicacy.options + -split $arg)

    $localSuccessStatus = $true

    if ($LastExitCode -ne 0)
    {
        $globalSuccessStatus = $false
        $localSuccessStatus = $false
    }
    $successStatusString = successStatusAsString $localSuccessStatus

    $msg = Get-Content -Tail 6 -Path $log.filePath
    $msg = "$successStatusString($LastExitCode)! Last lines:`n" + " => " + "$( $msg -join "`n => " )"
    doRemoteNotifications "<code>$msg</code>"
}

function doCall($command, $arg)
{
    & $command @arg *>&1 | Tee-Object -FilePath "$( $log.filePath )" -Append
    echo ""
    echo ""
    echo ""
    echo ""
    echo $LastExitCode
    echo ""
    echo ""
    echo ""
    echo ""
}


function log($str)
{
    $date = $( Get-Date ).ToString("yyyy-MM-dd HH:mm:ss.fff")
    doCall { Write-Output "${date} $str" }
}

function initDuplicacyOptions
{
    # ============================================
    # Duplicacy global options

    $globalOpts = " -log "
    if ($duplicacyDebug)
    {
        $globalOpts += " -d "
    }


    # ============================================
    # Duplicacy backup options

    $backupOpts = ""
    if ($duplicacyVssOption -And ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
    {
        $backupOpts += " -vss "
        $backupOpts += " -vss-timeout " + $duplicacyVssTimeout
    }

    if ($maxBackupTransferRate)
    {
        $backupOpts += " -limit-rate $maxBackupTransferRate "
    }

    if ($duplicacyBackupNumberOfThreads)
    {
        $backupOpts += " -threads " + $duplicacyBackupNumberOfThreads
    }

    # ============================================
    # Duplicacy prune options

    $pruneOpts = " $pruneRetentionPolicyLocal "
    $pruneOffsiteOpts = " $pruneRetentionPolicyLocal "

    if ($duplicacyPruneNumberOfThreads)
    {
        $pruneOpts += " -threads " + $duplicacyPruneNumberOfThreads
        $pruneOffsiteOpts += " -threads " + $duplicacyPruneNumberOfThreads
    }

    if ($duplicacyPruneExtraOptionsLocal)
    {
        $pruneOpts += " $duplicacyPruneExtraOptionsLocal "
    }

    if ($duplicacyPruneExtraOptionsOffsite)
    {
        $pruneOffsiteOpts += " $duplicacyPruneExtraOptionsOffsite "
    }


    # ============================================
    # Duplicacy copy options

    $copyOpts = ""
    if ($duplicacyCopyNumberOfThreads)
    {
        $copyOpts += " -threads " + $duplicacyCopyNumberOfThreads
    }

    if ($maxCopyTransferRate)
    {
        $copyOpts += " -upload-limit-rate " + $maxCopyTransferRate
    }


    # ============================================
    # Initialize the script-level duplicacy table with all the precomputed strings
    $script:duplicacy.exe = "$duplicacyExePath"
    $script:duplicacy.options = "$globalOpts"
    $script:duplicacy.command = "$duplicacyExePath $globalOpts "

    $script:duplicacy.backup = "backup -stats $backupOpts"
    $script:duplicacy.check = " check "

    $script:duplicacy.prune = " prune $pruneOpts "
    $script:duplicacy.pruneOffsite = " prune $pruneOffsiteOpts "
    $script:duplicacy.copy = " copy -to offsite $copyOpts "
}


function initLoggingOptions
{
    # Init the logging paths and files
    $log = $script:log
    $log.basePath = ".duplicacy/tbp-logs" # relative to $repositoryFolder
    $log.fileName = "backup-log " + $( Get-Date ).toString("yyyy-MM-dd HH-mm-ss") + "_" + $( Get-Date ).Ticks + ".log"
    $log.workingPath = $log.basePath + "/" + $( Get-Date ).toString("yyyy-MM-dd dddd") + "/"
    $log.filePath = $log.workingPath + $log.fileName
}


function createLogFolder
{
    if (!(Test-Path -Path $log.workingPath))
    {
        New-Item -ItemType directory -Path $log.workingPath
        log "Folder ${log.workingPath} does not exist. It has just been created"
    }
}

function warnIfNoCommandsWereExecuted
{
    if (-Not($runBackup -Or
            $runPrune -Or
            $runCheck -Or
            $runPruneOffsite -Or
            $runCopyToOffsite))
    {
        $msg = "       !!! No commands were executed. You should check your configuration file: user_config.ps1!"
        log
        log $msg
        log

        doRemoteNotifications $msg
    }
}


function successStatusAsString($someBoolean)
{
    $status = "SUCCESS"
    if (-Not$someBoolean)
    {
        $status = "FAILURE"
    }
    return $status
}


main
