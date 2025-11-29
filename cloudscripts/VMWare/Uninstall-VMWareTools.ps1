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
    .\Uninstall-VMWareTools.ps1
    
.EXAMPLE
    .\Uninstall-VMWareTools.ps1 -NoReboot -Force

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
    
    $detectionPoints = 0
    
    # Check for VMware Tools service
    $vmToolsService = Get-Service -Name "VMTools" -ErrorAction SilentlyContinue
    if ($vmToolsService) {
        $detectionPoints++
        Write-Log "Detection: VMTools service found" -Level Info
    }
    
    # Check registry for installation
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $regPaths) {
        $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { 
            $_.DisplayName -like "*VMware Tools*" 
        }
        if ($apps) {
            $detectionPoints++
            Write-Log "Detection: Registry uninstall entry found" -Level Info
            break
        }
    }
    
    # Check for VMware directories
    $vmwarePaths = @(
        "C:\Program Files\VMware",
        "C:\Program Files (x86)\VMware",
        "C:\ProgramData\VMware"
    )
    
    foreach ($vmPath in $vmwarePaths) {
        if (Test-Path $vmPath) {
            $detectionPoints++
            Write-Log "Detection: VMware directory found at $vmPath" -Level Info
            break
        }
    }
    
    # Check for VMware registry keys
    $vmwareRegKeys = @(
        "HKLM:\SOFTWARE\VMware, Inc.",
        "HKLM:\SOFTWARE\WOW6432Node\VMware, Inc."
    )
    
    foreach ($regKey in $vmwareRegKeys) {
        if (Test-Path $regKey) {
            $detectionPoints++
            Write-Log "Detection: VMware registry key found at $regKey" -Level Info
            break
        }
    }
    
    if ($detectionPoints -gt 0) {
        Write-Log "VMware Tools installation detected ($detectionPoints indicators found)" -Level Success
        return $true
    } else {
        Write-Log "VMware Tools not found on this system" -Level Success
        return $false
    }
}

function Stop-VMwareProcesses {
    Write-Log "Terminating VMware processes..."
    
    $vmwareProcesses = @(
        "vmtoolsd",
        "VMwareUser",
        "vmware-tray",
        "VMwareHostOpen",
        "vmware-usbarbitrator64",
        "vmware-tray.exe"
    )
    
    foreach ($procName in $vmwareProcesses) {
        $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($processes) {
            try {
                Write-Log "Terminating process: $procName"
                $processes | Stop-Process -Force -ErrorAction Stop
                Write-Log "Process terminated: $procName" -Level Success
            } catch {
                Write-Log "Failed to terminate process $procName : $_" -Level Warning
            }
        }
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
                
                # Delete the service
                Write-Log "Deleting service: $serviceName"
                $deleteResult = Start-Process -FilePath "sc.exe" -ArgumentList "delete","$serviceName" -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
                if ($deleteResult.ExitCode -eq 0) {
                    Write-Log "Service deleted: $serviceName" -Level Success
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
        $arguments = "/x `"$ProductCode`" /qn /norestart REBOOT=ReallySuppress /l*v `"$LogPath.msi.log`""
        
        Write-Log "Executing: msiexec.exe $arguments"
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        # Exit codes: 0=success, 1605=product not found, 1614=product uninstalled, 3010=reboot required
        if ($process.ExitCode -in @(0, 1605, 1614, 3010)) {
            Write-Log "MSI uninstallation completed successfully (Exit Code: $($process.ExitCode))" -Level Success
            return $true
        } else {
            Write-Log "MSI uninstallation returned exit code: $($process.ExitCode)" -Level Warning
            if ($process.ExitCode -eq 1603) {
                Write-Log "Exit code 1603: Fatal error during uninstallation. This may indicate:" -Level Warning
                Write-Log "  - Another installation is in progress" -Level Warning
                Write-Log "  - Insufficient permissions" -Level Warning
                Write-Log "  - Corrupt installation" -Level Warning
                Write-Log "Check the MSI log at: $LogPath.msi.log" -Level Info
            }
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
        # Skip if it's an install command (MsiExec.exe /I) rather than uninstall
        if ($UninstallString -match '/I\{') {
            Write-Log "Uninstall string appears to be an install command, skipping EXE method" -Level Warning
            return $false
        }
        
        # Parse the uninstall string
        if ($UninstallString -match '^"?([^"]+)"?\s*(.*)$') {
            $exePath = $Matches[1]
            $arguments = $Matches[2].Trim()
            
            # Verify the executable exists
            if (-not (Test-Path $exePath)) {
                Write-Log "Uninstall executable not found: $exePath" -Level Warning
                return $false
            }
            
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

function Uninstall-VMwareToolsSetup {
    Write-Log "Attempting direct setup.exe uninstallation..."
    
    $setupPaths = @(
        "C:\Program Files\VMware\VMware Tools\setup64.exe",
        "C:\Program Files (x86)\VMware\VMware Tools\setup.exe",
        "C:\Program Files\VMware\VMware Tools\setup.exe"
    )
    
    foreach ($setupPath in $setupPaths) {
        if (Test-Path $setupPath) {
            try {
                Write-Log "Found setup at: $setupPath"
                $arguments = "/S /c /l `"$LogPath.setup.log`""
                Write-Log "Executing: $setupPath $arguments"
                $process = Start-Process -FilePath $setupPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Log "Setup.exe uninstallation completed successfully" -Level Success
                    return $true
                } else {
                    Write-Log "Setup.exe returned exit code: $($process.ExitCode)" -Level Warning
                }
            } catch {
                Write-Log "Setup.exe uninstallation failed: $_" -Level Warning
            }
        }
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
        "HKLM:\SYSTEM\CurrentControlSet\Services\VMwareCAFCommAmqpListener",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9709436B-5A41-4946-8BE7-2AA433CAF108}",
        "HKCU:\SOFTWARE\VMware, Inc."
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
    
    # Remove all VMware Tools uninstall entries dynamically
    Write-Log "Searching for VMware Tools uninstall entries..."
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $uninstallPaths) {
        try {
            $vmwareEntries = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { 
                $_.DisplayName -like "*VMware Tools*" 
            }
            
            foreach ($entry in $vmwareEntries) {
                $keyPath = $entry.PSPath
                try {
                    Write-Log "Removing VMware uninstall entry: $keyPath"
                    Remove-Item -Path $keyPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed: $keyPath" -Level Success
                } catch {
                    Write-Log "Failed to remove $keyPath : $_" -Level Warning
                }
            }
        } catch {
            Write-Log "Error searching uninstall entries: $_" -Level Warning
        }
    }
    
    # Remove Windows Installer cache entries
    Write-Log "Cleaning Windows Installer cache entries..."
    try {
        $installerPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\*"
        $products = Get-ChildItem $installerPath -ErrorAction SilentlyContinue
        
        foreach ($product in $products) {
            $installProps = Get-ItemProperty "$($product.PSPath)\InstallProperties" -ErrorAction SilentlyContinue
            if ($installProps.DisplayName -like "*VMware Tools*") {
                try {
                    Write-Log "Removing installer cache for: $($installProps.DisplayName)"
                    Remove-Item -Path $product.PSPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed installer cache entry" -Level Success
                } catch {
                    Write-Log "Failed to remove installer cache: $_" -Level Warning
                }
            }
        }
    } catch {
        Write-Log "Error cleaning installer cache: $_" -Level Warning
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

function Remove-VMwareScheduledTasks {
    Write-Log "Removing VMware scheduled tasks..."
    
    try {
        $vmwareTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
            $_.TaskName -like "*VMware*" 
        }
        
        if ($vmwareTasks) {
            foreach ($task in $vmwareTasks) {
                try {
                    Write-Log "Removing scheduled task: $($task.TaskName)"
                    Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
                    Write-Log "Removed scheduled task: $($task.TaskName)" -Level Success
                } catch {
                    Write-Log "Failed to remove scheduled task $($task.TaskName): $_" -Level Warning
                }
            }
        } else {
            Write-Log "No VMware scheduled tasks found" -Level Success
        }
    } catch {
        Write-Log "Failed to enumerate scheduled tasks: $_" -Level Warning
    }
}

function Remove-VMwareEnvironmentVariables {
    Write-Log "Removing VMware environment variables..."
    
    try {
        $vmwareEnvVars = [Environment]::GetEnvironmentVariables("Machine").GetEnumerator() | Where-Object { 
            $_.Key -like "*VMware*" 
        }
        
        if ($vmwareEnvVars) {
            foreach ($envVar in $vmwareEnvVars) {
                try {
                    Write-Log "Removing environment variable: $($envVar.Key)"
                    [Environment]::SetEnvironmentVariable($envVar.Key, $null, "Machine")
                    Write-Log "Removed environment variable: $($envVar.Key)" -Level Success
                } catch {
                    Write-Log "Failed to remove environment variable $($envVar.Key): $_" -Level Warning
                }
            }
        } else {
            Write-Log "No VMware environment variables found" -Level Success
        }
    } catch {
        Write-Log "Failed to enumerate environment variables: $_" -Level Warning
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
    
    # Terminate VMware processes
    Stop-VMwareProcesses
    Start-Sleep -Seconds 2
    
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
    
    # Try direct setup.exe uninstall if other methods failed
    if (-not $uninstallSuccess) {
        $uninstallSuccess = Uninstall-VMwareToolsSetup
    }
    
    # If uninstall failed and Force is specified, continue with cleanup
    if (-not $uninstallSuccess) {
        if ($Force) {
            Write-Log "Uninstallation failed, but -Force specified. Proceeding with manual cleanup..." -Level Warning
        } else {
            Write-Log "Uninstallation failed. Use -Force to continue with manual cleanup" -Level Error
            Write-Log "Example: .\Uninstall-VMWareTools.ps1 -Force" -Level Info
            exit 1
        }
    }
    
    # Wait for uninstaller to complete
    Write-Log "Waiting for uninstaller processes to complete..."
    Start-Sleep -Seconds 5
    
    # Clean up residual files
    Remove-VMwareResidualFiles
    
    # Clean up registry
    Remove-VMwareRegistryEntries
    
    # Remove scheduled tasks
    Remove-VMwareScheduledTasks
    
    # Remove environment variables
    Remove-VMwareEnvironmentVariables
    
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