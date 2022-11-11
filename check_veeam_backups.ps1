#Get argument for excluded jobs
param([string]$excluded_jobs = "")
if ($excluded_jobs -ne "") {
    $excluded_jobs_array = $excluded_jobs.Split(",")
}

$VeeamModulePath = "C:\Program Files\Veeam\Backup and Replication\Console"
$env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$VeeamModulePath"
$TestPath = $VeeamModulePath + "\Veeam.Backup.PowerShell\Veeam.Backup.PowerShell.psd1"

try {
    if (Test-Path -Path $TestPath -PathType Leaf) {
        Import-Module -DisableNameChecking Veeam.Backup.PowerShell
    }
    else {
        #Adding required SnapIn
        if($null -eq (Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue))
        {
	        Add-PsSnapin VeeamPSSnapIn
        }
    }
    #-------------------------------------------------------------------------------

    $output_jobs_failed = ""
    $output_jobs_warning = ""
    $output_jobs_disabled = ""
    $return_output = ""
    $return_state = 0

    $output_jobs_failed_counter = 0
    $output_jobs_warning_counter = 0
    $output_jobs_success_counter = 0
    $output_jobs_none_counter = 0
    $output_jobs_working_counter = 0
    $output_jobs_skipped_counter = 0
    $output_jobs_disabled_counter = 0

    #Check Configuration Backup Job
    $confBackups = Get-VBRConfigurationBackupJob

    ForEach ($confjob in $confBackups) {
        $IsEnabled = $confjob.Enabled

        if ($IsEnabled) {
            $lastResult = $confjob.LastResult

            if ($lastResult -eq "Warning") {
                $output_jobs_warning += $confjob.Name + ", "
                if ($return_state -ne 2) {
                    $return_state = 1
                }

                $output_jobs_warning_counter ++
            }
            elseif ($lastResult -eq "Success") {
                $output_jobs_success_counter ++
            }
            elseif ($lastResult -eq "Failed") {
                $output_jobs_failed += $confjob.Name + ", "
                $return_state = 2
                $output_jobs_failed_counter++
            }
        }
        else {
            $output_jobs_disabled += $confjob.Name + ", "
            if ($return_state -ne 2) {
                $return_state = 1
            }
            $output_jobs_disabled_counter++
        }
    }

    #Get all Veeam backup jobs 
    $jobs = Get-VBRJob -WarningAction SilentlyContinue

    #Loop through every backup job
    ForEach ($job in $jobs) {
        if (-not($null -ne $excluded_jobs_array -and $excluded_jobs_array -contains $job.Name)) {            
            $IsEnabled = $Job.Info.IsScheduleEnabled

            if ($IsEnabled) {
                $LastSession = $Job.FindLastSession()
                $Log = $LastSession.Logger.GetLog()

                $HasErrors = $Log.IsAnyFailedRecords()
                $HasWarnings = $Log.IsAnyWarningRecords()
            
                $runtime = $LastSession.CreationTime.ToString("dd.MM.yyyy")
                $state = $job.GetLastState()

                #Skip jobs that are currently running
                if ($state -ne "Working") {
                    if ($HasErrors) {
                        $output_jobs_failed += $job.Name + " (" + $runtime + "), "
                        $return_state = 2
                        $output_jobs_failed_counter++
                    }
                    elseif ($HasWarnings) {
                        $output_jobs_warning += $job.Name + " (" + $runtime + "), "
                        if ($return_state -ne 2) {
                            $return_state = 1
                        }
                
                        $output_jobs_warning_counter ++
                    }
                    else {
                        $output_jobs_success_counter ++
                    }
                }
            }
            else {
                $output_jobs_disabled += $job.Name + ", "
                if ($return_state -ne 2) {
                    $return_state = 1
                }
                $output_jobs_disabled_counter++
            }
        }
    }

    #We could display currently running jobs, but if we'd like to use the Nagios stalking option we just summarize "ok" and "working"
    $output_jobs_success_counter = $output_jobs_working_counter + $output_jobs_success_counter

    if ($output_jobs_failed -ne "") {
        $output_jobs_failed = $output_jobs_failed.Substring(0, $output_jobs_failed.Length - 2)
	
        $return_output += "`nFailed: " + $output_jobs_failed
    }

    if ($output_jobs_warning -ne "") {
        $output_jobs_warning = $output_jobs_warning.Substring(0, $output_jobs_warning.Length - 2)
	
        $return_output += "`nWarning: " + $output_jobs_warning
    }

    if ($output_jobs_disabled -ne "") {
        $output_jobs_disabled = $output_jobs_disabled.Substring(0, $output_jobs_disabled.Length - 2)
	
        $return_output += "`nDisabled: " + $output_jobs_disabled
    }

    if ($return_state -eq 1 -or $return_state -eq 2) {
        Write-Host "Backup Status - Failed: "$output_jobs_failed_counter" / Warning: "$output_jobs_warning_counter" / OK: "$output_jobs_success_counter" / None: "$output_jobs_none_counter" / Skipped: "$output_jobs_skipped_counter" / Disabled: "$output_jobs_disabled_counter $return_output
    }
    elseif ($output_jobs_disabled_counter -gt 0) {
        Write-Host "Backup Status - Disabled: "$output_jobs_disabled_counter" backups stopped"
    }
    else {
        Write-Host "Backup Status - All "$output_jobs_success_counter" backups successful"
    }

    exit $return_state
}
catch [System.SystemException] {
    Write-Host $_
    exit 3
}
