<#PSScriptInfo
.GUID 9670c013-d1b1-4f5d-9bd0-0fa185b9f203
.AUTHOR David Segura @SeguraOSD
.EDITS Matthew Miles 
.COMPANYNAME osdcloud.com 
.COPYRIGHT (c) 2023 David Segura osdcloud.com. All rights reserved.
.TAGS OSDeploy OSDCloud WinPE OOBE Windows AutoPilot
.LICENSEURI 
.PROJECTURI https://github.com/OSDeploy/OSD
.ICONURI 
.EXTERNALMODULEDEPENDENCIES 
.REQUIREDSCRIPTS 
.EXTERNALSCRIPTDEPENDENCIES 
.RELEASENOTES
Script should be executed in a Command Prompt using the following command
powershell Invoke-Expression -Command (Invoke-RestMethod -Uri oobe.sight-sound.dev)
This is abbreviated as
powershell iex (irm oobe.sight-sound.dev)
#>
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PowerShell Script which supports the OSDCloud environment
.DESCRIPTION
    PowerShell Script which supports the OSDCloud environment
.LINK
    https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/subdomains/oobe.sight-sound.dev.ps1
.EXAMPLE
    powershell iex (irm oobe.sight-sound.dev)
#>
[CmdletBinding()]
param()
$ScriptName = 'oobe.sight-sound.dev'
$ScriptVersion = '25.6.28.2'

#region Initialize
$Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-$ScriptName.log"
$null = Start-Transcript -Path (Join-Path "$env:SystemRoot\Temp" $Transcript) -ErrorAction Ignore

if ($env:SystemDrive -eq 'X:') {
    $WindowsPhase = 'WinPE'
}
else {
    $ImageState = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction Ignore).ImageState
    if ($env:UserName -eq 'defaultuser0') {$WindowsPhase = 'OOBE'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE') {$WindowsPhase = 'Specialize'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_AUDIT') {$WindowsPhase = 'AuditMode'}
    else {$WindowsPhase = 'Windows'}
}

Write-Host -ForegroundColor Green "[+] $ScriptName $ScriptVersion ($WindowsPhase Phase)"
Invoke-Expression -Command (Invoke-RestMethod -Uri https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/oobeFunctions.ps1)
Invoke-Expression -Command (Invoke-RestMethod -Uri https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/oobe_menu_functions.ps1)
Invoke-Expression -Command (Invoke-RestMethod -Uri https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/oobe_menu.ps1)
#endregion

#region Admin Elevation
$whoiam = [system.security.principal.windowsidentity]::getcurrent().name
$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isElevated) {
    Write-Host -ForegroundColor Green "[+] Running as $whoiam (Admin Elevated)"
}
else {
    Write-Host -ForegroundColor Red "[!] Running as $whoiam (NOT Admin Elevated)"
    Break
}
#endregion

#region Transport Layer Security (TLS) 1.2
Write-Host -ForegroundColor Green "[+] Transport Layer Security (TLS) 1.2"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
#endregion

#region WinPE
if ($WindowsPhase -eq 'WinPE') {    
    #Stop the startup Transcript.  OSDCloud will create its own
    $null = Stop-Transcript -ErrorAction Ignore
}
#endregion

#region Specialize
if ($WindowsPhase -eq 'Specialize') {
    $null = Stop-Transcript -ErrorAction Ignore
}
#endregion

#region AuditMode
if ($WindowsPhase -eq 'AuditMode') {
    $null = Stop-Transcript -ErrorAction Ignore
}
#endregion

#region OOBE
if ($WindowsPhase -eq 'OOBE') {
    #Load everything needed to setup a new computer and register to AutoPilot
    step-PendingReboot | Out-Null
    step-installCertificates
    step-setTimeZoneFromIP
    step-SetExecutionPolicy
    step-SetPowerShellProfile
    step-InstallPackageManagement
    step-TrustPSGallery
    #step-InstallPowerSHellModule -Name Pester
    step-InstallPowerSHellModule -Name PSReadLine    
    #step-InstallPowerSHellModule -name Microsoft.WinGet.Client 
    #step-InstallWinget
    step-desktopWallpaper

    # --- Load OOBE Menu ---
        $valid = $false
        while (-not $valid) {
            $result = step-oobemenu

            if (-not $result) {
                Write-Host -ForegroundColor Yellow "[!] User cancelled OOBE menu. Exiting script."
                Stop-Transcript -ErrorAction Ignore
                exit
        }

            # --- Force Computer Name Uppercase ---
            if ($result.ComputerName) {
                $result.ComputerName = $result.ComputerName.ToUpper()
            }

            # --- Validate Computer Name Length ---
            if ($result.ComputerName -and $result.ComputerName.Length -gt 15) {
                [System.Windows.MessageBox]::Show(
                    "Computer Name must be 15 characters or less.",
                    "Input Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                continue # Go back to the menu for correction
            }

            $apPassed = $true
            if ($result.EnrollAutopilot) {
                $plainPass = $result.EnrollmentPassword
                $apTest = Test-AutopilotPassword -Password $plainPass
                if (-not $apTest) {
                    [System.Windows.MessageBox]::Show(
                        "Autopilot password is incorrect. Please try again.",
                        "Autopilot Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    ) | Out-Null
                    continue  # Loop again to retry the menu!
                }
                $apPassed = $apTest
            }
            $valid = $true
        }
        # Now outside the loop, run installs if the user didn't cancel
        if ($result) {
            if ($result.InstallOffice)   { step-oobeMenu_InstallM365Apps | Out-Null }
            if ($result.InstallUmbrella) { step-oobeMenu_InstallUmbrella | Out-Null }
            if ($result.InstallDellCmd)  { step-oobeMenu_InstallDellCmd | Out-Null }
            if ($result.ClearTPM)        { step-oobeMenu_ClearTPM | Out-Null }
            if ($result.EnrollAutopilot) {
                step-oobeMenu_RegisterAutopilot -GroupTag $result.GroupTag -Group $result.Group -ComputerName $result.ComputerName -EnrollmentPassword $result.EnrollmentPassword
                Write-Host GroupTag: $result.GroupTag
                Write-Host Group: $result.Group
                Write-Host ComputerName: $result.ComputerName
            }
        }

    step-oobeRemoveAppxPackageAllUsers
    step-oobeSetUserRegSettings
    step-oobeSetDeviceRegSettings   
    step-oobeCreateLocalUser
    step-oobeRestartComputer

    $null = Stop-Transcript -ErrorAction Ignore
}
#endregion

#region Windows
if ($WindowsPhase -eq 'Windows') {
    #Load OSD and Azure stuff
    $null = Stop-Transcript -ErrorAction Ignore

    Invoke-Expression (Invoke-RestMethod scripts.sight-sound.dev)
}

#endregion
