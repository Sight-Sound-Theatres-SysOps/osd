<#
.SYNOPSIS
    Removes VMware Tools from a Windows Server VM.

.DESCRIPTION
    This script comprehensively removes VMware Tools including:
    - Stopping VMware services
    - Uninstalling via MSI or setup.exe
    - Cleaning up residual files and folders
    - Removing registry entries
    - Optional system reboot

.PARAMETER LogPath
    Path where the log file will be created. Default: C:\Windows\Temp\VMwareToolsRemoval.log

.PARAMETER NoReboot
    Prevents automatic reboot after removal. Default: $false

.PARAMETER Force
    Forces removal even if uninstaller reports errors. Default: $false

.EXAMPLE
    .\Remove-VMwareTools.ps1
    
.EXAMPLE
    .\Remove-VMwareTools.ps1 -NoReboot -Force

.NOTES
    Author: System Administrator
    Requires: Administrator privileges
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Windows\Temp\VMwareToolsRemoval.log",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoReboot,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

#Requires -RunAsAdministrator

#region Functions

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output with color
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # File output
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

function Test-VMwareToolsInstalled {
    Write-Log "Checking if VMware Tools is installed..."
    
    # Check for VMware Tools service
    $vmToolsService = Get-Service -Name "VMTools" -ErrorAction SilentlyContinue
    
    # Check registry for installation
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    $vmwareInstalled = $false
    foreach ($path in $regPaths) {
        $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { 
            $_.DisplayName -like "*VMware Tools*" 
        }
        if ($apps) {
            $vmwareInstalled = $true
            break
        }
    }
    
    if ($vmToolsService -or $vmwareInstalled) {
        Write-Log "VMware Tools installation detected" -Level Success
        return $true
    } else {
        Write-Log "VMware Tools not found on this system" -Level Warning
        return $false
    }
}

function Stop-VMwareServices {
    Write-Log "Stopping VMware services..."
    
    $vmwareServices = @(
        "VMTools",
        "VGAuthService",
        "VMwareCAFManagementAgentHost",
        "VMwareCAFCommAmqpListener"
    )
    
    foreach ($serviceName in $vmwareServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            try {
                if ($service.Status -eq 'Running') {
                    Write-Log "Stopping service: $serviceName"
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Log "Service stopped: $serviceName" -Level Success
                } else {
                    Write-Log "Service already stopped: $serviceName" -Level Info
                }
            } catch {
                Write-Log "Failed to stop service $serviceName : $_" -Level Warning
            }
        }
    }
}

function Get-VMwareToolsUninstallInfo {
    Write-Log "Retrieving VMware Tools uninstall information..."
    
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $regPaths) {
        $uninstallInfo = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { 
            $_.DisplayName -like "*VMware Tools*" 
        } | Select-Object -First 1
        
        if ($uninstallInfo) {
            Write-Log "Found: $($uninstallInfo.DisplayName) - Version: $($uninstallInfo.DisplayVersion)"
            return $uninstallInfo
        }
    }
    
    return $null
}

function Uninstall-VMwareToolsMSI {
    param([string]$ProductCode)
    
    Write-Log "Attempting MSI uninstallation with product code: $ProductCode"
    
    try {
        $arguments = "/x `"$ProductCode`" /qn /norestart /l*v `"$LogPath.msi.log`""
        
        Write-Log "Executing: msiexec.exe $arguments"
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "MSI uninstallation completed successfully (Exit Code: $($process.ExitCode))" -Level Success
            return $true
        } else {
            Write-Log "MSI uninstallation returned exit code: $($process.ExitCode)" -Level Warning
            return $false
        }
    } catch {
        Write-Log "MSI uninstallation failed: $_" -Level Error
        return $false
    }
}

function Uninstall-VMwareToolsEXE {
    param([string]$UninstallString)
    
    Write-Log "Attempting EXE uninstallation with command: $UninstallString"
    
    try {
        # Parse the uninstall string
        if ($UninstallString -match '^"?([^"]+)"?\s*(.*)$') {
            $exePath = $Matches[1]
            $arguments = $Matches[2].Trim()
            
            # Add silent parameters if not present
            if ($arguments -notmatch '/S|/silent|/quiet|/qn') {
                $arguments += " /S"
            }
            
            Write-Log "Executing: $exePath $arguments"
            $process = Start-Process -FilePath $exePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-Log "EXE uninstallation completed successfully" -Level Success
                return $true
            } else {
                Write-Log "EXE uninstallation returned exit code: $($process.ExitCode)" -Level Warning
                return $false
            }
        }
    } catch {
        Write-Log "EXE uninstallation failed: $_" -Level Error
        return $false
    }
    
    return $false
}

function Remove-VMwareResidualFiles {
    Write-Log "Removing residual VMware files and folders..."
    
    $pathsToRemove = @(
        "C:\Program Files\VMware",
        "C:\Program Files (x86)\VMware",
        "C:\ProgramData\VMware",
        "$env:TEMP\vmware*"
    )
    
    foreach ($path in $pathsToRemove) {
        if (Test-Path $path) {
            try {
                Write-Log "Removing: $path"
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed: $path" -Level Success
            } catch {
                Write-Log "Failed to remove $path : $_" -Level Warning
            }
        }
    }
}

function Remove-VMwareRegistryEntries {
    Write-Log "Cleaning up VMware registry entries..."
    
    $registryPaths = @(
        "HKLM:\SOFTWARE\VMware, Inc.",
        "HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.",
        "HKLM:\SYSTEM\CurrentControlSet\Services\VMTools",
        "HKLM:\SYSTEM\CurrentControlSet\Services\VGAuthService",
        "HKLM:\SYSTEM\CurrentControlSet\Services\VMwareCAFManagementAgentHost",
        "HKLM:\SYSTEM\CurrentControlSet\Services\VMwareCAFCommAmqpListener"
    )
    
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                Write-Log "Removing registry key: $regPath"
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed: $regPath" -Level Success
            } catch {
                Write-Log "Failed to remove registry key $regPath : $_" -Level Warning
            }
        }
    }
}

function Remove-VMwareDrivers {
    Write-Log "Checking for VMware drivers..."
    
    try {
        $vmwareDrivers = Get-WmiObject Win32_PnPSignedDriver | Where-Object { 
            $_.DeviceName -like "*VMware*" -or $_.Manufacturer -like "*VMware*"
        }
        
        if ($vmwareDrivers) {
            Write-Log "Found $($vmwareDrivers.Count) VMware driver(s)"
            foreach ($driver in $vmwareDrivers) {
                Write-Log "Driver: $($driver.DeviceName) - $($driver.DriverVersion)" -Level Info
            }
            Write-Log "Note: Manual driver removal may be required through Device Manager" -Level Warning
        } else {
            Write-Log "No VMware drivers found" -Level Success
        }
    } catch {
        Write-Log "Failed to enumerate drivers: $_" -Level Warning
    }
}

#endregion

#region Main Script

try {
    Write-Log "========================================" -Level Info
    Write-Log "VMware Tools Removal Script Started" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "Script executed by: $env:USERNAME on $env:COMPUTERNAME"
    
    # Check if VMware Tools is installed
    if (-not (Test-VMwareToolsInstalled)) {
        Write-Log "VMware Tools is not installed. Exiting." -Level Warning
        exit 0
    }
    
    # Get uninstall information
    $uninstallInfo = Get-VMwareToolsUninstallInfo
    
    if (-not $uninstallInfo) {
        Write-Log "Could not retrieve uninstall information" -Level Error
        if (-not $Force) {
            Write-Log "Use -Force parameter to attempt manual cleanup" -Level Warning
            exit 1
        }
    }
    
    # Stop VMware services
    Stop-VMwareServices
    Start-Sleep -Seconds 2
    
    # Attempt uninstallation
    $uninstallSuccess = $false
    
    if ($uninstallInfo) {
        # Try MSI uninstall first
        if ($uninstallInfo.PSChildName -match "^\{.*\}$") {
            $uninstallSuccess = Uninstall-VMwareToolsMSI -ProductCode $uninstallInfo.PSChildName
        }
        
        # Try EXE uninstall if MSI failed or not available
        if (-not $uninstallSuccess -and $uninstallInfo.UninstallString) {
            $uninstallSuccess = Uninstall-VMwareToolsEXE -UninstallString $uninstallInfo.UninstallString
        }
    }
    
    # If uninstall failed and Force is specified, continue with cleanup
    if (-not $uninstallSuccess -and -not $Force) {
        Write-Log "Uninstallation failed. Use -Force to continue with manual cleanup" -Level Error
        exit 1
    }
    
    # Wait for uninstaller to complete
    Write-Log "Waiting for uninstaller processes to complete..."
    Start-Sleep -Seconds 5
    
    # Clean up residual files
    Remove-VMwareResidualFiles
    
    # Clean up registry
    Remove-VMwareRegistryEntries
    
    # Check for drivers
    Remove-VMwareDrivers
    
    # Final verification
    Write-Log "Verifying removal..."
    Start-Sleep -Seconds 2
    
    if (Test-VMwareToolsInstalled) {
        Write-Log "VMware Tools may still be partially installed. Manual intervention may be required." -Level Warning
    } else {
        Write-Log "VMware Tools has been successfully removed!" -Level Success
    }
    
    Write-Log "========================================" -Level Info
    Write-Log "VMware Tools Removal Script Completed" -Level Success
    Write-Log "========================================" -Level Info
    Write-Log "Log file location: $LogPath"
    
    # Handle reboot
    if (-not $NoReboot) {
        Write-Log "System will reboot in 60 seconds. Use -NoReboot to prevent automatic reboot." -Level Warning
        Write-Host "`nPress Ctrl+C to cancel reboot..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
        Write-Log "Initiating system reboot..."
        Restart-Computer -Force
    } else {
        Write-Log "Reboot skipped. Please reboot the system manually to complete the removal." -Level Warning
    }
    
} catch {
    Write-Log "Critical error occurred: $_" -Level Error
    Write-Log $_.ScriptStackTrace -Level Error
    exit 1
}

#endregion