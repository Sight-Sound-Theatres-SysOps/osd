#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Checks for UEFI CA 2023 Secure Boot certificates and triggers deployment if missing.

.DESCRIPTION
    Checks whether the updated 2023 Secure Boot certificates have been applied to this device.
    If missing and the device is capable, triggers deployment via the Windows Secure Boot
    update mechanism (AvailableUpdates registry key + scheduled task).

    Also detects firmware-level KEK incompatibility (Firmware_MissingKEKInPackage) and
    flags the device as hardware-incompatible rather than attempting a doomed remediation.

    Expiring certificates being replaced:
      - Microsoft Corporation KEK CA 2011  (KEK) -- expires June 2026
      - Microsoft Corporation UEFI CA 2011 (DB)  -- expires June 2026
      - Microsoft Windows Production PCA 2011 (DB) -- expires October 2026

.PARAMETER LogPath
    Path to write a log file.  Defaults to C:\ProgramData\SecureBootCertCheck\check.log.

.EXAMPLE
    .\Invoke-SecureBootCertCheck.ps1

.EXAMPLE
    .\Invoke-SecureBootCertCheck.ps1 -LogPath "C:\Logs\SecureBoot.log"

.NOTES
    PSVersion : 5.1+
    Context   : Interactive admin tool or Intune remediation (run as SYSTEM/admin)
    Requires  : Administrator rights (Get-SecureBootUEFI requires elevation)
    References:
      https://support.microsoft.com/en-us/topic/5068202
      https://directaccess.richardhicks.com/2025/12/04/windows-secure-boot-uefi-certificates-expiring-june-2026/
      https://github.com/richardhicks/uefi
#>

[CmdletBinding()]
param (
    [string]$LogPath = "$env:ProgramData\SecureBootCertCheck\check.log"
)

$ErrorActionPreference = 'Stop'

# ── Registry paths ────────────────────────────────────────────────────────────
$sbPath        = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
$servicingPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing'

# ── Console helpers ───────────────────────────────────────────────────────────
function Write-Step  { param([string]$m) Write-Host "`n[ $m ]" -ForegroundColor Yellow }
function Write-Pass  { param([string]$m) Write-Host "  [PASS] $m" -ForegroundColor Green }
function Write-Fail  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Warn  { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info  { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Cyan }
function Write-Fatal { param([string]$m) Write-Host "  [!!]   $m" -ForegroundColor Magenta }

function Write-Log {
    param([string]$Message)
    $entry = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Verbose $entry
    try {
        $entry | Out-File -FilePath $LogPath -Append -Encoding utf8
    }
    catch {
        # Non-fatal -- log write failure should not abort the check
    }
}

# Ensure log directory exists
try {
    New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
}
catch { }

# ── Header ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '  Secure Boot Certificate Check and Remediation'     -ForegroundColor Cyan
Write-Host "  $env:COMPUTERNAME  --  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan

Write-Log "Starting check on $env:COMPUTERNAME"

# ── Step 1: Prerequisites ─────────────────────────────────────────────────────
Write-Step 'Checking Prerequisites'

$secureBootEnabled = $false
try {
    $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop
}
catch {
    # Non-UEFI system or cmdlet unavailable
}

if (-not $secureBootEnabled) {
    Write-Fail 'Secure Boot is not enabled or this is a non-UEFI system.'
    Write-Info  'Certificate updates require UEFI with Secure Boot enabled.  No action taken.'
    Write-Log   'RESULT: Secure Boot not enabled -- skipped'
    exit 0
}

Write-Pass 'Secure Boot is enabled.'
Write-Log  'Secure Boot enabled: True'

# ── Step 2: Read servicing registry ──────────────────────────────────────────
Write-Step 'Reading Servicing Registry'

$servicing = $null
try {
    $servicing = Get-ItemProperty -Path $servicingPath -ErrorAction Stop
}
catch {
    Write-Warn 'Servicing registry key not found.  Device may not have the required cumulative update.'
    Write-Info  'Install the latest Windows cumulative update and re-run this script.'
    Write-Log   'RESULT: Servicing key missing -- CU may be needed'
    exit 0
}

$uefiStatus    = $servicing.UEFICA2023Status
$uefiError     = $servicing.UEFICA2023Error
$capable       = $servicing.WindowsUEFICA2023Capable
$kekError      = $servicing.KEKLastUpdateError
$kekErrorReason = $servicing.KEKLastUpdateErrorReason
$confidenceLevel = $servicing.ConfidenceLevel

Write-Info "UEFICA2023Status          : $uefiStatus"
Write-Info "WindowsUEFICA2023Capable  : $capable"
Write-Info "ConfidenceLevel           : $confidenceLevel"
if ($uefiError) { Write-Info "UEFICA2023Error           : $uefiError" }
if ($kekError)  { Write-Info "KEKLastUpdateError        : $kekError" }
if ($kekErrorReason) { Write-Info "KEKLastUpdateErrorReason  : $kekErrorReason" }

Write-Log "Status=$uefiStatus, Capable=$capable, KEKErrorReason=$kekErrorReason"

# ── Step 3: KEK hardware incompatibility check ────────────────────────────────
Write-Step 'Checking KEK Hardware Compatibility'

if ($kekErrorReason -eq 'Firmware_MissingKEKInPackage') {
    Write-Fatal '-----------------------------------------------------------------------'
    Write-Fatal ' HARDWARE INCOMPATIBLE -- KEK UPDATE CANNOT BE APPLIED'
    Write-Fatal '-----------------------------------------------------------------------'
    Write-Fatal " Device    : $env:COMPUTERNAME"

    # Try to get model info for the operator
    try {
        $cs   = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
        $bios = Get-WmiObject -Class Win32_BIOS           -ErrorAction SilentlyContinue
        Write-Fatal " Model     : $($cs.Manufacturer) $($cs.Model)"
        Write-Fatal " BIOS      : $($bios.SMBIOSBIOSVersion)  (Released: $($bios.ReleaseDate))"
    }
    catch { }

    Write-Fatal ''
    Write-Fatal ' ROOT CAUSE:'
    Write-Fatal '   The device firmware (UEFI) does not contain a KEK entry that matches'
    Write-Fatal '   any package in Microsoft''s KEKUpdateCombined.bin.  This means the'
    Write-Fatal '   OEM Platform Key (PK) was never enrolled in Microsoft''s KEK update'
    Write-Fatal '   map, or the OEM has not released a firmware update that adds it.'
    Write-Fatal ''
    Write-Fatal ' WHAT THIS MEANS:'
    Write-Fatal '   - The Microsoft Corporation KEK 2K CA 2023 certificate CANNOT be'
    Write-Fatal '     enrolled on this device by any software means.'
    Write-Fatal '   - Windows Update, Set-SecureBootUEFI, and registry triggers all fail'
    Write-Fatal '     with STATUS_EFI_SECURITY_VIOLATION (0xC0000454) at the firmware level.'
    Write-Fatal '   - The device will permanently show KEK as "Not up to date" in Intune.'
    Write-Fatal ''
    Write-Fatal ' RECOMMENDED ACTION:'
    Write-Fatal '   1. Confirm no newer BIOS/firmware is available from the OEM.'
    Write-Fatal '   2. If no firmware fix exists, document as a hardware limitation.'
    Write-Fatal '   3. Exclude device from Intune compliance policies that check KEK status.'
    Write-Fatal '   4. Flag device for hardware refresh at next refresh cycle.'
    Write-Fatal '-----------------------------------------------------------------------'

    Write-Log "RESULT: HARDWARE INCOMPATIBLE -- Firmware_MissingKEKInPackage -- no remediation possible"
    exit 0
}

Write-Pass 'No KEK hardware incompatibility detected.'

# ── Step 4: Check current status ──────────────────────────────────────────────
Write-Step 'Evaluating Certificate Status'

# Already updated
if ($uefiStatus -eq 'Updated') {
    Write-Pass 'Secure Boot 2023 certificates are already up to date.'
    Write-Log  'RESULT: Already updated -- no action needed'
    exit 0
}

# Completed but boot manager update still pending reboot
if ($uefiStatus -eq 'InProgress') {
    $sbReg = Get-ItemProperty -Path $sbPath -ErrorAction SilentlyContinue
    if ($sbReg.AvailableUpdates -eq 0x4100) {
        Write-Warn 'Certificates applied.  A reboot is needed to finish the boot manager update.'
        Write-Info 'Action: Reboot this device, then re-run this script to confirm completion.'
        Write-Log  'RESULT: InProgress (0x4100) -- reboot needed'
        exit 0
    }
    Write-Warn 'Status is InProgress.  Deployment may already be running or waiting on a reboot.'
    Write-Info 'Action: Reboot the device and re-run this script.'
    Write-Log  'RESULT: InProgress -- reboot recommended'
    exit 0
}

# Prior error recorded
if ($null -ne $uefiError -and $uefiError -ne 0) {
    Write-Fail "Deployment previously attempted but recorded an error: UEFICA2023Error=$uefiError"
    Write-Info 'Check Event Viewer > Windows Logs > System for Secure Boot events (IDs 1795, 1796).'
    Write-Info 'This may indicate a firmware compatibility issue.  Check for a BIOS/firmware update from your OEM.'
    Write-Log  "RESULT: Prior error -- UEFICA2023Error=$uefiError"
    # Fall through to attempt remediation anyway
}

# Device not in high-confidence bucket yet
if ($capable -eq 1) {
    Write-Warn "Device is capable but not yet in Microsoft's high-confidence bucket."
    Write-Info "ConfidenceLevel: $confidenceLevel"
    Write-Info 'Proceeding with manual trigger...'
    Write-Log  'Capable=1, not yet high-confidence -- will attempt trigger'
}

# ── Step 5: Remediation ───────────────────────────────────────────────────────
Write-Step 'Triggering Deployment'

$remediationSuccess = $true

try {
    if (-not (Test-Path $sbPath)) {
        New-Item -Path $sbPath -Force | Out-Null
    }

    Set-ItemProperty -Path $sbPath -Name 'AvailableUpdates'            -Value 0x5944 -Type DWord -Force
    Set-ItemProperty -Path $sbPath -Name 'MicrosoftUpdateManagedOptIn' -Value 1      -Type DWord -Force
    Set-ItemProperty -Path $sbPath -Name 'HighConfidenceOptOut'        -Value 0      -Type DWord -Force

    Write-Pass 'Registry keys set: AvailableUpdates=0x5944, MicrosoftUpdateManagedOptIn=1, HighConfidenceOptOut=0'
    Write-Log  'Registry keys written successfully'
}
catch {
    Write-Fail "Failed to set registry keys: $($_.Exception.Message)"
    Write-Log  "ERROR setting registry: $($_.Exception.Message)"
    $remediationSuccess = $false
}

if ($remediationSuccess) {
    try {
        Start-ScheduledTask -TaskName 'Secure-Boot-Update' -TaskPath '\Microsoft\Windows\PI\' -ErrorAction Stop
        Write-Pass 'Triggered scheduled task: \Microsoft\Windows\PI\Secure-Boot-Update'
        Write-Log  'Scheduled task triggered successfully'
    }
    catch {
        Write-Warn "Could not trigger scheduled task: $($_.Exception.Message)"
        Write-Info 'The task will run automatically within 12 hours.'
        Write-Log  "WARN: Scheduled task trigger failed -- $($_.Exception.Message)"
    }
}

# ── Step 6: Next steps ────────────────────────────────────────────────────────
Write-Step 'Next Steps'

if ($remediationSuccess) {
    Write-Host @"

  Deployment has been triggered.  Complete the following steps:

  1.  REBOOT this device now.
  2.  After reboot, re-run this script to confirm status.
  3.  If status is still InProgress after reboot, reboot once more.
  4.  Final status should show "Updated" or AvailableUpdates = 0x4000.

  To check status after reboot:
    Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing |
      Select-Object UEFICA2023Status, KEKLastUpdateErrorReason

"@ -ForegroundColor Cyan
    Write-Log 'RESULT: Remediation triggered -- reboot required'
}
else {
    Write-Fail 'Remediation could not be applied.  Check the log for details.'
    Write-Log  'RESULT: Remediation failed'
}

# ── Footer ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host "Log written to: $LogPath" -ForegroundColor DarkGray
Write-Host ''

<#
VALIDATION STEPS
----------------
1.  Run on a device with UEFICA2023Status = Updated           -- should exit with PASS, no action
2.  Run on a device with UEFICA2023Status = InProgress        -- should advise reboot, no registry change
3.  Run on a NUC8 or device with Firmware_MissingKEKInPackage -- should display HARDWARE INCOMPATIBLE block
4.  Run on a device needing remediation                       -- should set registry keys and trigger task
5.  Run without admin rights                                  -- #Requires should block execution
6.  Check $LogPath after each run to confirm log entries
#>