<#
.SYNOPSIS
    Windows Setup Complete automation script for post-installation configuration.

.DESCRIPTION
    This script runs after Windows installation completes and performs the following tasks:
    - Configures power settings to prevent sleep during updates
    - Updates Windows Defender definitions and platform
    - Installs Windows Updates
    - Installs driver updates
    - Restores power plan settings
    - Logs all activities and reboots the system

.NOTES
    Author: Matthew Miles
    Last Modified: January 17, 2026
#>

Write-Output 'Starting SetupComplete Script Process'
Set-ExecutionPolicy RemoteSigned -Force -Scope CurrentUser

# Ensure log directory exists
$LogPath = 'C:\Windows\Temp\osdcloud-logs'
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path "$LogPath\SetupComplete.log" -ErrorAction Ignore

$StartTime = Get-Date
Write-Host "Start Time: $($StartTime.ToString('hh:mm:ss'))"

# Load remote functions
try {
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/refs/heads/main/functions/setupcomplete_functions.ps1' -ErrorAction Stop)
    Write-Output 'Successfully loaded remote functions from GitHub'
}
catch {
    Write-Output "Failed to load remote functions: $($_.Exception.Message)"
    Write-Output 'WARNING: Continuing with locally available functions...'
}

Start-Sleep -Seconds 5

# Configure Power Plan for Updates
Write-Output 'Setting PowerPlan to High Performance'
powercfg /setactive DED574B5-45A0-4F42-8737-46345C09C238
Write-Output 'Confirming PowerPlan [powercfg /getactivescheme]'
powercfg /getactivescheme
powercfg -x -standby-timeout-ac 0
powercfg -x -standby-timeout-dc 0
powercfg -x -hibernate-timeout-ac 0
powercfg -x -hibernate-timeout-dc 0
Set-PowerSettingSleepAfter -PowerSource AC -Minutes 0
Set-PowerSettingTurnMonitorOffAfter -PowerSource AC -Minutes 0

# Configure Delivery Optimization for Microsoft Connected Cache
Write-Output 'Configuring Delivery Optimization for Microsoft Connected Cache'
$DORegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
if (!(Test-Path $DORegPath)) {
    New-Item -Path $DORegPath -Force | Out-Null
}

# Set to use DHCP Option 235 for cache host
Set-ItemProperty -Path $DORegPath -Name 'DOCacheHostSource' -Value 1 -Type DWord -Force
Write-Output 'Delivery Optimization configured to retrieve cache server from DHCP Option 235'

# Renew DHCP lease to ensure we have latest options
Write-Output 'Renewing DHCP lease'
ipconfig /release | Out-Null
Start-Sleep -Seconds 2
ipconfig /renew | Out-Null
Start-Sleep -Seconds 2
Write-Output 'DHCP lease renewed'

# Run Defender Update Stack
Write-Output "Running Defender Update Stack Function [Update-DefenderStack] | Time: $($(Get-Date).ToString('hh:mm:ss'))"
Update-DefenderStack
Write-Output "Completed Section [Update-DefenderStack] | Time: $($(Get-Date).ToString('hh:mm:ss'))"
Write-Output '-------------------------------------------------------------'

# Run Windows Updates
Write-Output "Running Windows Update Function [Start-WindowsUpdate] | Time: $($(Get-Date).ToString('hh:mm:ss'))"
try {
    Start-WindowsUpdate
    Write-Output "Completed Section [Start-WindowsUpdate] | Time: $($(Get-Date).ToString('hh:mm:ss'))"
}
catch {
    Write-Output "ERROR in Start-WindowsUpdate: $($_.Exception.Message)"
}
Write-Output '-------------------------------------------------------------'

# Run Driver Updates
Write-Output "Running Windows Update Drivers Function [Start-WindowsUpdateDriver] | Time: $($(Get-Date).ToString('hh:mm:ss'))"
try {
    Start-WindowsUpdateDriver
    Write-Output "Completed Section [Start-WindowsUpdateDriver] | Time: $($(Get-Date).ToString('hh:mm:ss'))"
}
catch {
    Write-Output "ERROR in Start-WindowsUpdateDriver: $($_.Exception.Message)"
}
Write-Output '-------------------------------------------------------------'

# Install WinGet
Write-Output "Installing WinGet | Time: $($(Get-Date).ToString('hh:mm:ss'))"
try {
    $wingetScript = Invoke-RestMethod -Uri "https://asheroto.com/winget" -ErrorAction Continue
    
    if ($wingetScript) {
        # Save script to temporary file
        $tempScript = "$env:TEMP\winget_install_$(Get-Random).ps1"
        $wingetScript | Out-File -FilePath $tempScript -Force
        
        # Run in a separate PowerShell process to contain any Exit calls
        $result = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript
        
        # Clean up
        Remove-Item -Path $tempScript -Force -ErrorAction Ignore
        
        Write-Output "Successfully installed WinGet | Time: $($(Get-Date).ToString('hh:mm:ss'))"
    }
    else {
        Write-Output "WARNING: Failed to retrieve WinGet installation script - script content was empty"
    }
}
catch {
    Write-Output "WARNING: Failed to install WinGet: $($_.Exception.Message)"
}
Write-Output '-------------------------------------------------------------'


# Restore Power Plan
Write-Output 'Setting PowerPlan to Balanced'
Set-PowerSettingTurnMonitorOffAfter -PowerSource AC -Minutes 15
powercfg /setactive 381B4222-F694-41F0-9685-FF5BB260DF2E

# Completion
$EndTime = Get-Date
Write-Host "End Time: $($EndTime.ToString('hh:mm:ss'))"
$TotalTime = New-TimeSpan -Start $StartTime -End $EndTime
$RunTimeMinutes = [math]::Round($TotalTime.TotalMinutes, 0)
Write-Host "Run Time: $RunTimeMinutes Minutes"
Stop-Transcript
Restart-Computer -Force