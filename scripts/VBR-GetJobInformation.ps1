# Define script version - used by Zabbix to check if there is a newer version available
$scriptVersion = "2025.05.05"
# Define the path to the Veeam Backup PowerShell module
$modulePath = "C:\Program Files\Veeam\Backup and Replication\Console\Veeam.Backup.PowerShell\Veeam.Backup.PowerShell.psd1"

# Do all the core logic in a try-catch loop to ensure errors are caught correctly
try {
  # Check if the Veeam Backup PowerShell module exists at the specified path
  if (-not (Test-Path $modulePath)) {
    throw "The Veeam Backup PowerShell module is not installed at the expected path: $modulePath"
  }
  # Import the Veeam Backup & Replication PowerShell module
  try {
    Import-Module $modulePath -DisableNameChecking
  }
  catch {
    throw "The Veeam Backup PowerShell module could not be loaded: $($_.Exception.Message)"
  }
  $module = Get-Module -Name Veeam.Backup.PowerShell
  # Verify the module is loaded
  if (-not ($module)) {
    throw "Failed to load the Veeam Backup PowerShell module after attempting import."
  }

  # Get module and script version
  $moduleVersion = $module.Version.ToString()

  # Create script and module version info
  $scriptInfo = @{
    "version"            = $scriptVersion
    "veeamModuleVersion" = $moduleVersion
  }

  # Veeam has separated the retrieval of VM based jobs and Agent based jobs; some versions of the PowerShell module will throw a warning the below commands will get the relevant items, and suppress warnings
  $vmJobs = Get-VBRJob -WarningAction SilentlyContinue
  $agentJobs = Get-VBRComputerBackupJob -WarningAction SilentlyContinue
  # Combine vmJobs and agentJobs only if they are not null or empty
  $jobs = @()
  if ($vmJobs) {
    $jobs += $vmJobs
  }
  if ($agentJobs) {
    $jobs += $agentJobs
  }
  $jobsInfo = @()
  # Initialize an error hash table to capture unsupported job types by job name
  $errorList = @{}
  $warningList = @{}
  foreach ($job in $jobs) {
    # Get basic job details
    $jobDetails = [PSCustomObject]@{
      JobName              = $job.Name                                                   # Capture Job Name
      JobType              = $job.TypeToString                                           # Capture TypeToString for Job Type
      JobID                = $job.Id                                                     # Capture the JobID for use in session queries
      JobIsScheduleEnabled = $job.IsScheduleEnabled                                      # Capture State of Job (Enabled/Disabled)
      JobStatus            = if ($job.isRunning) { 10 } else { $job.info.LatestStatus }  # Capture Latest Status of runtime
    }
    if ($job.isVmCopy) {
      # If the job type is something else, add it to the error list
      $warningList[$job.Name] = "Error: $($job.TypeToString) - Job type currently unsupported"
      continue  # Skip to the next job
    }
    else {
      # Regular VM backup job - use Get-VBRSession
      $latestSession = Get-VBRSession -Job $job -Last -WarningAction SilentlyContinue
    }
    if ($latestSession) {
      # Format Date Strings for ease of import to Zabbix
      $jobDetails | Add-Member -MemberType NoteProperty -Name "LastRun" -Value $latestSession.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
      # Check if the job has finished; add relevant data
      if ($latestSession.EndTime -gt $latestSession.CreationTime) {
        $jobDetails | Add-Member -MemberType NoteProperty -Name "LastEnd" -Value $latestSession.EndTime.ToString("yyyy-MM-dd HH:mm:ss")
        $duration = (New-TimeSpan -Start $latestSession.CreationTime -End $latestSession.EndTime).TotalSeconds
        $jobDetails | Add-Member -MemberType NoteProperty -Name "Duration" -Value ([math]::Round($duration, 2))
      }
      else {
        # Job is still running
        $jobDetails | Add-Member -MemberType NoteProperty -Name "LastEnd" -Value ""
        $duration = (New-TimeSpan -Start $latestSession.CreationTime -End (Get-Date)).TotalSeconds
        $jobDetails | Add-Member -MemberType NoteProperty -Name "Duration" -Value ([math]::Round($duration, 2))
      }
      # LastResult Mappings:
      # 0 to "Success"
      # 1 to "Failed"
      # 2 to "Warning"
      # 3 to "In Progress"
      $jobDetails | Add-Member -MemberType NoteProperty -Name "LastResult" -Value $latestSession.Result
      # Percentage of current job completed
      $jobDetails | Add-Member -MemberType NoteProperty -Name "Progress" -Value $latestSession.Progress
    }
    else {
      # If no sessions, assign empty or default values
      $jobDetails | Add-Member -MemberType NoteProperty -Name "LastRun" -Value "No sessions"
      $jobDetails | Add-Member -MemberType NoteProperty -Name "LastEnd" -Value "No sessions"
      $jobDetails | Add-Member -MemberType NoteProperty -Name "Duration" -Value 0
      $jobDetails | Add-Member -MemberType NoteProperty -Name "LastResult" -Value 0
      $jobDetails | Add-Member -MemberType NoteProperty -Name "Progress" -Value 0
    }
    # Add job details to the results array
    $jobsInfo += $jobDetails
  }

  # Form up JSON
  $scriptResult = @{
    "scriptInfo" = $scriptInfo
    "jobs"       = $jobsInfo
    "errors"     = $errorList
    "warnings"   = $warningList
  }
  # Return the combined data in JSON format with compression
  $scriptResult | ConvertTo-Json -Compress

}
catch {
  # Catch any errors that occur and return the error details in JSON format
  $scriptResult = @{
    "scriptInfo" = $scriptInfo
    "jobs"       = @()
    "warnings"   = @()
    "errors"     = @{
      "error"        = "An error occurred while retrieving Veeam data."
      "errorMessage" = $_.Exception.Message
      "stackTrace"   = $_.ScriptStackTrace
    }
  }
  # Return the error details as JSON
  $scriptResult | ConvertTo-Json -Compress
}