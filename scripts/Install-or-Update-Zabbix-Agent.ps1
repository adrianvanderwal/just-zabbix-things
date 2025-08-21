<#
.SYNOPSIS
  Automates the installation of the Zabbix Agent (or Zabbix Agent2) MSI
  Defaults to installing Zabbix Agent 2 version 7 LTS
  The script is designed to be run as part of a scheduled task through Group Policy
.DESCRIPTION
  Comprehensive script that automates the installation and upgrade of the Zabbix Agent (or Zabbix Agent2)

  1. Checks for proper PowerShell Version - must run in V5, else some cmdlets don't work/aren't available
  2. Checks for Administrator access - else the msi removal/install doesn't work
  3. Creates a log file for historical purposes (Parameters to set number of log files to keep - default is 52, on the assumption that the script will be run by GPO once a week); automatically rotates said logs
  4. Can install from local msi file or from Zabbix CDN (will automatically get the latest version for the MajorVersion specified)
  5. Can do a completely fresh install - removes all other Zabbix Agent/Zabbix Agent 2 installations before installing the new agent
  6. Will check for connection to the Zabbix Server/Proxy specified before actioning any removals/installations - this check can be overridden
  7. Will check for an existing installation of Zabbix Agent/Zabbix Agent 2; if set to upgrade, will check if the specified agent type matches and can be installed over the existing install
  8. Will automatically get the host FQDN, and set as the HostName for the Zabbix Agent, and prompt to set this in Zabbix Admin console - this can be set as a parameter on script run
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer 1.2.3.4
  Download and install the latest Zabbix Agent 2 version 7 LTS agent
  If an existing agent is installed, upgrade compatibility checks are performed
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server -MajorVersion 6.4
  Installs the latest available agent of the specific Major Version
  Allowed values include: 6.0, 6.2, 6.4, 7.0
  Defaults to 7.0
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server -agenttype agent
  Installs the specific agent type (agent or agent2)
  Defaults to agent2
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server -LocalMSIFile "\\path\to\MSI\zabbix_agent2-7.0.3-windows-amd64-openssl.msi"
  Uses a local MSI file instead of the Zabbix CDN
  MSI File name must follow the regex pattern:
  zabbix_(agent|agent2)-\d\.\d\.\d-windows-amd64-openssl\.msi
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server -FreshInstall $true
  Indiscriminately removes all existing Zabbix Agent AND Zabbix Agent 2 installations before installing the new version
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server -ZabbixServerPort 12345
  Specify a custom port for the Zabbix Server/Proxy communication
  Defaults to 10051
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server -LogPath \\some\path\to\logging\directory
  Specifies a directory for keeping log files
  Defaults to c:\temp
.EXAMPLE
  Install-or-Update-Zabbix-Agent.ps1 -ZabbixServer zabbix.server -LogsToKeep 5
  Specifies the number of previous log files to keep
  Defaults to 52
#>

[CmdletBinding()]
Param (
  [Parameter (Mandatory = $false, HelpMessage = "Removes all other installations of the Zabbix Agent/Zabbix Agent 2 and installs the latest available version")]
  $FreshInstall = $false, # Default to false
  [Parameter (Mandatory = $false, HelpMessage = "Which Major Version?")]
  [ValidateSet('6.0', '6.2', '6.4', '7.0')]
  [string]$MajorVersion = "7.0", # Default to latest LTS
  [Parameter (Mandatory = $false, HelpMessage = "agent or agent2")]
  [ValidateSet('agent', 'agent2')]
  [string]$agenttype = "agent2", # Default to agent2
  [Parameter (Mandatory = $false, HelpMessage = "Provide a local .msi installer path, leave blank to download the latest version from the Zabbix CDN - please note the installer name must match the pattern: zabbix_agent2-7.0.3-windows-amd64-openssl.msi")]
  [string]$localMSIPath,
  [Parameter (Mandatory = $true, HelpMessage = "IP or DNS Name of the Zabbix Server or Proxy that this agent will register with")]
  [string]$ZabbixServer, # Zabbix Server/Proxy IP
  [Parameter (Mandatory = $false, HelpMessage = "Communication Port")]
  [int32]$ZabbixServerPort = 10051, # Default is 10051
  [Parameter (Mandatory = $false, HelpMessage = "Host name for Zabbix Agent")]
  [string]$hostName = ([System.Net.Dns]::GetHostByName(($env:computerName))).HostName, # Default to the FQDN of the machine; this needs to be unique in Zabbix and match, case sensitive for monitoring to work
  [Parameter (Mandatory = $false, HelpMessage = "Force installation, even if Server/Proxy cannot be contacted?")]
  $ForceInstall = $false,
  [Parameter(Mandatory = $false)]
  [string]$LogPath = ("c:\temp\"), # LogFile path for the transcript to be written to
  [Parameter (Mandatory = $false)]
  [int32]$LogsToKeep = 52, # keep last 52 (a years worth if ran every week)
  [Parameter(Mandatory = $false)]
  [string]$remoteRepositoryURL = "https://raw.githubusercontent.com/adrianvanderwal/just-zabbix-things/refs/heads/master/scripts/Install-or-Update-Zabbix-Agent.ps1"
)

# Local Script Version; for checking if there is an updated script
$localVersion = [System.Version]"2025.04.23"

# Normalise Log Path
if ($LogPath[-1] -ne "\") {
  $LogPath = "$LogPath\"
}

if (-not (Test-Path $LogPath)) {
  New-Item -ItemType Directory -Force -Path $LogPath
}

Write-Host "[INFO]"(Start-Transcript -Path ($LogPath + "Zabbix Agent Installer - " + (get-date -format "yyyyMMdd-hhmmss") + '.log')) -ForegroundColor Yellow
# Clear old log files,
$oldLogs = Get-ChildItem ($logPath + "Zabbix Agent Installer - *.log")
if (($oldLogs).Count -ge $LogsToKeep ) {
  Write-Host "------" -ForegroundColor Yellow
  Write-Host "[INFO] Removing old log files:"
  $logstoRemove = $oldLogs | Sort-Object Name | Select-Object Name -First (($oldLogs).Count - $LogsToKeep)
  $logstoRemove | ForEach-Object { Write-Host "[INFO] $($_.Name)" ; Remove-Item $LogPath$($_.Name) -ErrorAction SilentlyContinue }
}

# Check PowerShell Version
if ($PSVersionTable.PSVersion.Major -ne 5) {
  Write-Host "------" -ForegroundColor Red
  Write-Host "[ERRR] This script must be run in PowerShell Version 5." -ForegroundColor Red
  Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
  exit 0
}
# Check Running as Admin
if (-not ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
  Write-Host "------" -ForegroundColor Red
  Write-Host "[ERRR] This script must be run as Administrator" -ForegroundColor Red
  Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
  exit 0
}

# set tls verison
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Script Version Check
Write-Host "------" -ForegroundColor Yellow
Write-Host "[INFO] Checking Script Version" -ForegroundColor Yellow
try {
  Write-Host "[INFO] Script version: $localVersion" -ForegroundColor Yellow

  # Fetch the remote script content
  $remoteScriptContent = Invoke-WebRequest -Uri $remoteRepositoryURL -UseBasicParsing
  # Ensure content is split into lines to avoid entire script capture
  $remoteScriptLines = $remoteScriptContent.Content -split "`r?`n"
  # Define a regex pattern to match the version line
  $versionPattern = '\$localVersion\s*=\s*\[System\.Version\]\s*"?(?<Version>\d+\.\d+\.\d+)"?'
  # Extract the version using regex matching
  $remoteVersionString = ($remoteScriptLines | Where-Object { $_ -match $versionPattern }) -replace $versionPattern, '${Version}'
  $remoteVersion = [System.Version]$remoteVersionString

  Write-Host "[INFO] Remote Repository version: $remoteVersion" -ForegroundColor Yellow
  if ($remoteVersion -gt $localVersion) {
    Write-Host "[INFO] A new version ($remoteVersion) is available, please download from it from:" -ForegroundColor Yellow
    Write-Host "       $($remoteRepositoryURL)" -ForegroundColor Yellow
  }
}
catch {
  Write-Host "[WARN] Unable to determine remote script version." -ForegroundColor DarkYellow
}

# Check if connection test required
if ($ForceInstall) {
  # install will be forced without checking
  Write-Host "------" -ForegroundColor DarkYellow
  Write-Host "[WARN] The ForceInstall Parameter was set, connection the Zabbix Server/Proxy was not tested" -ForegroundColor DarkYellow
  Write-Host "[WARN] This may result in a broken installation" -ForegroundColor DarkYellow
}
else {
  Write-Host "[INFO] A TCP Connection on port $ZabbixServerPort to $ZabbixServer will be attempted to establish connectivity to the Zabbix Server/Proxy before continuing" -ForegroundColor Yellow
  try {
    $connection = New-Object System.Net.Sockets.TcpClient($ZabbixServer, $ZabbixServerPort) -ErrorAction SilentlyContinue
    if ($connection.Connected) {
      # server/proxy responds, continue with installation
      Write-Host "[SUCC] A connection was successful" -ForegroundColor Green
      $connection.Close()
    }
  }
  catch {
    Write-Host "[ERRR] The Zabbix Server/Proxy could not be contacted" -ForegroundColor Red
    Write-Host "[ERRR] $_"
    Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
    exit 0
  }
}

# set required Agent Name String for comparisons
$agentString = if ($agenttype -eq 'agent') { "Zabbix Agent (64-bit)" } elseif ($agenttype -eq 'agent2') { "Zabbix Agent 2 (64-bit)" }

# this needs to be set to the currently available version
$agentVersion = $MajorVersion

if ($localMSIPath) {
  # check if LocalMSI matches the installer pattern
  if ($localMSIPath -match "zabbix_(agent|agent2)-\d+\.\d+\.\d+-windows-amd64-openssl\.msi$") {
    # test the path first, if it doesn't exist, error out
    if (Test-Path $localMSIPath) {
      # path exists, get details from msi
      $localMSI = Get-Item $localMSIPath
      $explodedName = $localMSI.Name.Split('-')
      if ($explodedName[0].split('_')[1] -ne $agenttype) {
        # installer does not exist or is not accessible; write error and end
        Write-Host "[ERRR] The MSI file does not match the agent type requested: $agenttype" -ForegroundColor Red
        Write-Host "[ERRR] $localMSIPath" -ForegroundColor Red
        Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
        exit 0
      }
      $installerLocation = $localMSIPath
      $agentVersion = $explodedName[1]
      if ([System.Version]$agentVersion.Major -ne [System.Version]$MajorVersion.Major) {
        # installer does not exist or is not accessible; write error and end
        Write-Host "[ERRR] The MSI file does not match the requested MajorVersion $MajorVersion" -ForegroundColor Red
        Write-Host "[ERRR] $localMSIPath" -ForegroundColor Red
        Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
        exit 0
      }
    }
    else {
      # installer does not exist or is not accessible; write error and end
      Write-Host "[ERRR] The MSI file could not be found or is not accessible, please check your settings and try again" -ForegroundColor Red
      Write-Host "[ERRR] $localMSIPath" -ForegroundColor Red
      Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
      exit 0
    }
  }
  else {
    # installer does not exist or is not accessible; write error and end
    Write-Host "[ERRR] The MSI file does not match the installer pattern " -ForegroundColor Red
    Write-Host "[ERRR] zabbix_(agent|agent2)-\d+\.\d+\.\d+-windows-amd64-openssl\.msi$" -ForegroundColor Red
    Write-Host "[ERRR] $localMSIPath" -ForegroundColor Red
    Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
    exit 0
  }
}
else {
  try {
    # base URL for Zabbix CDN
    Write-Host "------" -ForegroundColor Yellow
    Write-Host "[INFO] Attempting to build a download URL" -ForegroundColor Yellow
    $installerLocation = "https://cdn.zabbix.com/zabbix/binaries/stable/$MajorVersion/latest/zabbix_$agenttype-$MajorVersion-latest-windows-amd64-openssl.msi"

    ### due to the fact that the Zabbix Agent
    # get content of the zabbix cdn page
    # $HTML = Invoke-RestMethod $baseURL
    # Version Pattern
    # $Pattern = '\d+\.\d+\.\d+'
    # get latest version
    # $agentVersion = (($HTML | Select-String $Pattern -AllMatches).Matches | Select-Object -Unique value | Sort-Object { $_.value -as [Version] } | Select-Object -Last 1).Value
    # $installerLocation = "$baseURL/$agentVersion/zabbix_$agenttype-$agentVersion-windows-amd64-openssl.msi"

    Write-Host "[INFO] Build URL is:" -ForegroundColor Yellow
    Write-Host "       $installerLocation" -ForegroundColor Yellow
  }
  catch {
    Write-Host "[ERRR] There was an error when attempting to access the Zabbix CDN" -ForegroundColor Red
    Write-Host "[ERRR] $_" -ForegroundColor Red
    Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
    exit 0
  }
}

Write-Host "------" -ForegroundColor Yellow
Write-Host "[INFO] Checking 'FreshInstall' flag" -ForegroundColor Yellow
if ($FreshInstall) {
  # get any installed Zabbix Agents
  $installedAgents = Get-Package -Name "Zabbix Agent*" -ErrorAction SilentlyContinue
  Write-Host "------" -ForegroundColor DarkYellow
  Write-Host "[WARN] The Fresh Installation flag was set, $($installedAgents.count) currently installed version(s) of the Zabbix Agent / Zabbix Agent 2 will be removed before proceeding" -ForegroundColor DarkYellow
  # Force uninstall all agent versions
  foreach ($agent in $installedAgents) {
    Write-Host "[INFO] Attempting Removal of $($agent.Name) version $($agent.Version)" -ForegroundColor Red
    Write-Host "[INFO] MsiExec.exe /x $($agent.FastPackageReference) /qn /norestart" -ForegroundColor Yellow
    MsiExec.exe /x $agent.FastPackageReference /qn /norestart | Out-Default # Piped to Out-Default to ensure script waits for completion
    Write-Host "[SUCC] Removing $($agent.Name) version $($agent.Version) was successful" -ForegroundColor Green
  }
}
Write-Host "------" -ForegroundColor Yellow
Write-Host "[INFO] Checking for already installed agents" -ForegroundColor Yellow
$installedAgents = Get-Package -Name "Zabbix Agent*" -ErrorAction SilentlyContinue
if ($installedAgents.count -gt 1) {
  Write-Host "[ERRR] Too many agents installed, please manually review" -ForegroundColor Red
  Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
  exit 0
}
elseif ($installedAgents.count -eq 1) {
  # check if the currently installed agent is the same type and a version is below the one to install
  #foreach ($agent in $installedAgents) {
  #  Write-Host "[INFO] Checking if installed agent: $($agent.Name) version $($agent.Version) can be upgraded to $agentVersion" -ForegroundColor Yellow
  #  if ($agent.Name -ne $agentString) {
  #    Write-Host "[ERRR] The installed agent ($($agent.Name)) cannot be upgraded" -ForegroundColor Red
  #    Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
  #    exit 0
  #  }
  #  if (-not (([System.Version]$agent.version) -le ([System.Version]$agentVersion))) {
  #    Write-Host "[ERRR] The installed agent version $($agent.version) cannot be upgraded to $agentVersion" -ForegroundColor Red
  #    Write-Host "[ERRR] The script has terminated without making changes" -ForegroundColor Red
  #    exit 0
  #  }
  #}
}
# if script makes it here, either 0 agents are installed, or the agent installed can be upgraded
try {
  # actually do the install!
  Write-Host "[INFO] The following Zabbix Agent will be installed: $agentString $agentVersion" -ForegroundColor Yellow
  Write-Host "[INFO] Attempting to run the following command:" -ForegroundColor Yellow
  Write-Host "       msiexec /i $installerLocation /qn SERVER=$ZabbixServer SERVERACTIVE=$ZabbixServer HOSTNAME=$hostName" -ForegroundColor Yellow
  msiexec /i $installerLocation /qn SERVER=$ZabbixServer SERVERACTIVE=$ZabbixServer HOSTNAME=$hostName | Out-Default # Out-Default to pause script until installation is completed
  Write-Host "[SUCC] The installation of $agentString $agentVersion was successful" -ForegroundColor Green
  Write-Host "------"-ForegroundColor Yellow
  Write-Host "[INFO] Please make sure to update the Host Name in Zabbix Admin Console to:" -ForegroundColor Yellow
  Write-Host "       $hostName" -ForegroundColor Yellow
  try {
    $hostIPs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Where-Object { $_.IPAddress -notlike '169.*' } | Sort-Object IfIndex
    Write-Host "------" -ForegroundColor Yellow
    Write-Host "[INFO] Please make sure to update the Host IP Address in Zabbix Admin Console to one of the following, please choose an IP Address that is accessible from the Zabbix Proxy $($ZabbixServer) (preferrably the primary IP address): " -ForegroundColor Yellow
    Write-Host "------" -ForegroundColor Yellow
    foreach ($ip in $hostIPs) {
      Write-Host "       $($IP.IPAddress)" -ForegroundColor Yellow
    }
    Write-Host "------" -ForegroundColor Yellow
  }
  catch {
    Write-Host "[WARN] There was an error when attempting to get the local IP Addresses" -ForegroundColor DarkYellow
  }
  Write-Host "[INFO]"(Stop-Transcript) -ForegroundColor Green
}
catch {
  Write-Host "[ERRR] There was an issue installing the Zabbix Agent" -ForegroundColor Red
  Write-Host "[ERRR] $_"
}