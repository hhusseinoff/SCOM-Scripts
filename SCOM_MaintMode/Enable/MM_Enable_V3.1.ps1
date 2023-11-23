<#
.SYNOPSIS
This script initiates maintenance mode on a specified System Center Operations Manager (SCOM) server.

.DESCRIPTION
The script establishes a connection with the specified SCOM server and sets a server (usually the machine on which this script is running) into maintenance mode for a given duration, with a specified comment for the downtime reason.

.PARAMETER TargetSCOM_MSServer
The target SCOM Management Server to connect to. This parameter is mandatory.

.PARAMETER TargetDowntimeMinutes
The duration, in minutes, for which the server should be set in maintenance mode. This parameter is mandatory.

.PARAMETER TargetDowntimeComment
A comment that explains the reason for the downtime. This parameter is mandatory.

.PARAMETER TargetSCOMAccountName
Account used for establishing connection to the SCOM Management server, format DOMAIN\Username. This parameter is mandatory.

.PARAMETER TargetSCOMAccountCred
Password used for the account under which a connection to the SCOM Management server is made. This parameter is mandatory.

.DEPENDENCIES
This script requires the 'OperationsManager' PS module to be installed. Ensure the script has appropriate permissions on the target SCOM server and can create directories & write logs to 'C:\Temp\OperationsLogs'.
Also, this script must run under an account that has the SCOM Administrator role set up on the Management server.

.USECASE
This can be used during scheduled maintenance activities, OS patches, or any other operation where the server needs to be temporarily set in maintenance mode in SCOM, ensuring no false alerts are generated.

.EXAMPLE
PS C:\> .\MM_Enable.ps1 -TargetSCOM_MSServer "SCOMServer01" -TargetDowntimeMinutes 60 -TargetDowntimeComment "OS Patching"

.EXECUTION EXIT CODES
0   - Script executed successfully without errors.
1   - Error occurred while loading the OperationsManager PS Module.
2   - Failed to set up a new Management Group Connection with the specified SCOM server.
3   - Failed to retrieve SCOM Object for the given Agent FQDN.
4   - Failed to start Maintenance mode for the specified Agent.

.NOTES
Last Edit Date: Oct 18th 2023
Version: 3.0

Edit V3 - added in-script support for specifying runas account and creds.
Edit V3.1 - PSCredential creation typo fix

.LINK
Based on info provided from here
  https://kevinjustin.com/blog/2017/08/24/scom-maintenance-mode-powershell/
#>


param(
    [Parameter(Mandatory=$true)]
    [string]$TargetSCOM_MSServer,
    [Parameter(Mandatory=$true)]
    [long]$TargetDowntimeMinutes,
    [Parameter(Mandatory=$true)]
    [string]$TargetDowntimeComment,
    [Parameter(Mandatory=$true)]
    [string]$TargetSCOMAccountName,
    [Parameter(Mandatory=$true)]
    [string]$TargetSCOMAccountCred
)

# Capture script directory
$ScriptDir = $PSScriptRoot

$AgentNameFQDN = ([System.Net.Dns]::GetHostByName($env:computerName)).HostName

# Define log folder root
$LogFolderRoot = "C:\Temp\OperationsLogs"

# Define log folder path
$LogFolderPath = "C:\Temp\OperationsLogs\SCOM2022_MaintenanceMode"

# Define the log file path
$logFilePath = "C:\Temp\OperationsLogs\SCOM2022_MaintenanceMode\MM_Enable_$(Get-Date -Format yyyy_MM_dd__HH).log"

# Create Log Folder Root if it doesn't exist
if(!(Test-Path -Path $LogFolderRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $LogFolderRoot -Confirm:$false
}

# Create Log Folder if it doesn't exist
if(!(Test-Path -Path $LogFolderPath -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $LogFolderPath -Confirm:$false
}

# Custom logging function
function debug($message) {
    $logMessage = "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message"
    Write-Host $logMessage
    Add-Content -Path $logFilePath -Value $logMessage -Force
}

debug "------------------------------------------------------------------------------------------------------------------------------------------------"

debug "Script initated."

debug "Importing OperationsManager PS Module..."

try
{
    Import-Module -Name OperationsManager -Force
}
catch
{
    debug "ERROR: Failed to load OperationsManager PS Module."

    debug "Details: $($Error[0].Exception.Message)"

    debug "Exiting with error code 1..."

    $Error.Clear()

    debug "------------------------------------------------------------------------------------------------------------------------------------------------"

    exit 1
}

debug "OperationsManager Module imported successfully."

debug "Setting up new Management Group Connection under target account $TargetSCOMAccountName..."

debug "Converting credential to a secure string..."

$SecureCred = ConvertTo-SecureString -String $TargetSCOMAccountCred -AsPlainText -Force

debug "Constructing a PSCredential object..."

$SCOMCred = New-Object System.Management.Automation.PSCredential ("$TargetSCOMAccountName", $SecureCred)

debug "Establishing connection..."

try
{
    $ConnectionCheck = New-SCOMManagementGroupConnection -ComputerName $TargetSCOM_MSServer -Credential $SCOMCred
}
catch
{
    debug "ERROR: Failed to Setup a new Management Group Connection with server $TargetSCOM_MSServer"

    debug "Details: $($Error[0].Exception.Message)"

    debug "Exiting with error code 2..."

    $Error.Clear()

    debug "------------------------------------------------------------------------------------------------------------------------------------------------"

    exit 2
}

debug "Connection Established."

debug "Retrieving SCOM Object for $AgentNameFQDN..."

try
{
    $AllWindowsServerInstances = Get-SCOMClass -Name Microsoft.Windows.Computer | Get-SCOMClassInstance

    $CurrentSeverObj = $AllWindowsServerInstances | Where-Object -Property DisplayName -eq $AgentNameFQDN
}
catch
{
    debug "ERROR: Failed to retrieve SCOM Object for $AgentNameFQDN."

    debug "Details: $($Error[0].Exception.Message)"

    debug "Exiting with error code 3..."

    $Error.Clear()

    Remove-SCOMManagementGroupConnection -Connection $ConnectionCheck -Confirm:$false

    debug "------------------------------------------------------------------------------------------------------------------------------------------------"

    exit 3
}

debug "Object Retrieved Successfully."

debug "Starting Maintenance Mode, input Downtime in minutes is $TargetDowntimeMinutes"

$Downtime = (Get-Date).AddMinutes($TargetDowntimeMinutes)

try
{
    Start-SCOMMaintenanceMode -Instance $CurrentSeverObj -EndTime $Downtime -Comment $TargetDowntimeComment -Reason PlannedOperatingSystemReconfiguration -Confirm:$false
}
catch
{
    debug "ERROR: Failed to start Maintenance mode for $AgentNameFQDN."

    debug "Details: $($Error[0].Exception.Message)"

    debug "Exiting with error code 4..."

    $Error.Clear()

    Remove-SCOMManagementGroupConnection -Connection $ConnectionCheck -Confirm:$false

    debug "------------------------------------------------------------------------------------------------------------------------------------------------"

    exit 4
}

debug "Maintenance Mode successfuly started."

debug "Script Execution completed successfully. Exiting..."

debug "------------------------------------------------------------------------------------------------------------------------------------------------"

exit 0
