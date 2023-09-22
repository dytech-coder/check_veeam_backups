#Get argument for excluded jobs
[CmdletBinding()]
param([string]$excluded_jobs = '')
if ($excluded_jobs -ne '') {
    $excluded_jobs_array = $excluded_jobs.Split(',')
}

#=== Add a temporary value from User to session ($Env:PSModulePath) ======
#https://docs.microsoft.com/powershell/scripting/developer/module/modifying-the-psmodulepath-installation-path?view=powershell-7
$path = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$env:PSModulePath +="$([System.IO.Path]::PathSeparator)$path"
#=========================================================================

$VeeamModulePath = "$env:ProgramFiles\Veeam\Backup and Replication\Console"
#$env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$VeeamModulePath"
$TestPath = $VeeamModulePath + '\Veeam.Backup.PowerShell\Veeam.Backup.PowerShell.psd1'

try {
    if (Test-Path -Path $TestPath -PathType Leaf) {
        $veeamPSModule = Get-Module -ListAvailable | ?{$_.Name -match "Veeam.Backup.Powershell"}
        Import-Module $veeamPSModule.Path -DisableNameChecking
        #Import-Module -DisableNameChecking Veeam.Backup.PowerShell
    }
    else {
        #Adding required SnapIn
        if($null -eq (Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue))
        {
	        Add-PsSnapin VeeamPSSnapIn
        }
    }
    #-------------------------------------------------------------------------------

    $output_jobs_failed = ''
    $output_jobs_warning = ''
    $output_jobs_disabled = ''
    $return_output = ''
    $return_state = 0

    $output_jobs_failed_counter = 0
    $output_jobs_warning_counter = 0
    $output_jobs_success_counter = 0
    $output_jobs_none_counter = 0
    $output_jobs_working_counter = 0
    $output_jobs_skipped_counter = 0
    $output_jobs_disabled_counter = 0

    Try {
        #Check Configuration Backup Job
        $confBackups = Get-VBRConfigurationBackupJob
    }
    Catch {
        #Catch any errors and asume that the Backup Configuration Job is disabled
        $confBackups = $null
        $IsEnabled = $false
        $output_jobs_disabled += 'Backup Configuration Job' + ', '
        $return_state = 1
        $output_jobs_disabled_counter++
    }

    ForEach ($confjob in $confBackups) {
        $IsEnabled = $confjob.Enabled

        if ($IsEnabled) {
            $lastResult = $confjob.LastResult

            if ($lastResult -eq 'Warning') {
                $output_jobs_warning += $confjob.Name + ', '
                if ($return_state -ne 2) {
                    $return_state = 1
                }

                $output_jobs_warning_counter ++
            }
            elseif ($lastResult -eq 'Success') {
                $output_jobs_success_counter ++
            }
            elseif ($lastResult -eq 'Failed') {
                $output_jobs_failed += $confjob.Name + ', '
                $return_state = 2
                $output_jobs_failed_counter++
            }
        }
        else {
            $output_jobs_disabled += $confjob.Name + ', '
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
            $IsEnabled = $Job.IsScheduleEnabled

            if ($IsEnabled) {
                $LastSession = $Job.FindLastSession()
                $runtime = $LastSession.CreationTime.ToString('dd.MM.yyyy')
                $state = $job.GetLastState()

                if ($job.JobType -eq 'SimpleBackupCopyPolicy') {
                    $latestStatus = $job.Info.LatestStatus

                    if ($latestStatus -eq 'Failed') {
                        $lastStatus = 2
                    } elseif ($latestStatus -eq 'Warning') {
                        $lastStatus = 3
                    } else {
                        if ($LastSession.HasAnyTaskSession() -eq $false) {
                            # No TaskSessions found
                            $lastSessionDetails = $LastSession.GetDetails()
                            $HasErrors = $lastSessionDetails -match '.*(Error)(.*)$|.*(Failed)(.*)$'
        
                            if ($HasErrors) {
                                $lastStatus = 2
                            }
                        } else {
                            $taskSessions = Get-VBRTaskSession -Session $LastSession
                            [Veeam.Backup.Model.ESessionStatus]$lastStatus = 'Success'
                            foreach ($task in $taskSessions) {
                                $currentTaskStatus = $task.Status

                                if ($currentTaskStatus -eq 2) {
                                    $lastStatus = $currentTaskStatus
                                } elseif ($currentTaskStatus -eq 3) {
                                    if ($lastStatus -ne 2) {
                                        $lastStatus = $currentTaskStatus
                                    }
                                }
                            }
                        }
                    }
                } else {
                    $taskSessions = Get-VBRTaskSession -Session $LastSession
                    [Veeam.Backup.Model.ESessionStatus]$lastStatus = 'Success'
                    foreach ($task in $taskSessions) {
                        $currentTaskStatus = $task.Status

                        if ($currentTaskStatus -eq 2) {
                            $lastStatus = $currentTaskStatus
                        } elseif ($currentTaskStatus -eq 3) {
                            if ($lastStatus -ne 2) {
                                $lastStatus = $currentTaskStatus
                            }
                        }
                    }
                }

                if ($lastStatus -eq 2) {
                    $output_jobs_failed += $job.Name + ' (' + $runtime + '), '
                    $return_state = 2
                    $output_jobs_failed_counter++
                }
                elseif ($lastStatus -eq 3) {
                    $output_jobs_warning += $job.Name + ' (' + $runtime + '), '
                    if ($return_state -ne 2) {
                        $return_state = 1
                    }
                
                    $output_jobs_warning_counter ++
                }
                else {
                    $output_jobs_success_counter ++
                }
            }
            # If Job is Working but has errors or warnings 
            elseif (($state -eq 'Working') -and (($HasErrors -eq $true) -or ($HasWarnings -eq $true))) {
                if ($HasErrors) {
                    $output_jobs_failed += $job.Name + ' (' + $runtime + '), '
                    $return_state = 2
                    $output_jobs_failed_counter++
                }
                elseif ($HasWarnings) {
                    $output_jobs_warning += $job.Name + ' (' + $runtime + '), '
                    if ($return_state -ne 2) {
                        $return_state = 1
                    }
                
                    $output_jobs_warning_counter ++
                }
            } else {
                $output_jobs_disabled += $job.Name + ', '
                if ($return_state -ne 2) {
                    $return_state = 1
                }
                $output_jobs_disabled_counter++
            }
        }
    }

    #We could display currently running jobs, but if we'd like to use the Nagios stalking option we just summarize "ok" and "working"
    $output_jobs_success_counter = $output_jobs_working_counter + $output_jobs_success_counter

    if ($output_jobs_failed -ne '') {
        $output_jobs_failed = $output_jobs_failed.Substring(0, $output_jobs_failed.Length - 2)
	
        $return_output += "`nFailed: " + $output_jobs_failed
    }

    if ($output_jobs_warning -ne '') {
        $output_jobs_warning = $output_jobs_warning.Substring(0, $output_jobs_warning.Length - 2)
	
        $return_output += "`nWarning: " + $output_jobs_warning
    }

    if ($output_jobs_disabled -ne '') {
        $output_jobs_disabled = $output_jobs_disabled.Substring(0, $output_jobs_disabled.Length - 2)
	
        $return_output += "`nDisabled: " + $output_jobs_disabled
    }

    if ($return_state -eq 1 -or $return_state -eq 2) {
        Write-Host 'Backup Status - Failed: '$output_jobs_failed_counter" / Warning: "$output_jobs_warning_counter" / OK: "$output_jobs_success_counter" / None: "$output_jobs_none_counter" / Skipped: "$output_jobs_skipped_counter" / Disabled: "$output_jobs_disabled_counter $return_output
    }
    elseif ($output_jobs_disabled_counter -gt 0) {
        Write-Host 'Backup Status - Disabled: '$output_jobs_disabled_counter" backups stopped"
    }
    else {
        Write-Host 'Backup Status - All '$output_jobs_success_counter" backups successful"
    }

    exit $return_state
}
catch [System.SystemException] {
    Write-Host $_
    exit 3
}
