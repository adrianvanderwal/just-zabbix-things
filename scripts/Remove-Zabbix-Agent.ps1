# Check PowerShell Version
if ($PSVersionTable.PSVersion.Major -ne 5) {
  Write-Host "[ERRR] This script must be run in PowerShell Version 5." -ForegroundColor Red
  Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
  exit 0
}
# Check Running as Admin
if (-not ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
  Write-Host "[ERRR] This script must be run as Administrator" -ForegroundColor Red
  Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
  exit 0
}

# Get any installed Zabbix Agents
$installedAgents = Get-Package -Name "Zabbix Agent*" -ErrorAction SilentlyContinue
# Force uninstall all agent versions
foreach ($agent in $installedAgents) {
  Write-Host "[INFO] Attempting Removal of $($agent.Name) version $($agent.Version)" -ForegroundColor Red
  Write-Host "[INFO] MsiExec.exe /x $($agent.FastPackageReference) /qn /norestart" -ForegroundColor Blue
  MsiExec.exe /x $agent.FastPackageReference /qn /norestart | Out-Default # Piped to Out-Default to ensure script waits for completion
  Write-Host "[SUCC] Removing $($agent.Name) version $($agent.Version) was successful" -ForegroundColor Green
}

# Remove Scheduled Task for Automatic Update
Unregister-ScheduledTask -TaskName "Install or Update Zabbix Agent" -Confirm:$false -ErrorAction SilentlyContinue