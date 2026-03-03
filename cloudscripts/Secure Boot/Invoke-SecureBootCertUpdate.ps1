<#
.SYNOPSIS
    Standalone Secure Boot Certificate Check and Remediation

.DESCRIPTION
    Designed for devices with no management infrastructure (workgroup, non-Entra/domain joined).
    Run elevated (as Administrator) directly on the device.

    Detection uses TWO methods in order of authority:
      1. Live UEFI firmware DB scan (ground truth - cert actually in firmware)
      2. Registry servicing keys (Windows deployment status)

    If the 2023 cert is not present and the device is capable, triggers deployment via:
      - Setting AvailableUpdates = 0x5944
      - Kicking the Secure-Boot-Update scheduled task immediately
      - Providing clear next-step instructions

    Expiring certificates being replaced:
      - Microsoft KEK CA 2011           (KEK) - expires June 2026
      - Windows UEFI CA 2011            (DB)  - expires June 2026
      - Microsoft Windows Production PCA 2011 (DB)  - expires October 2026

.NOTES
    Must run as Administrator (required for Get-SecureBootUEFI and registry writes)
    Run on: Windows 10/11 with Secure Boot enabled and May 2025+ cumulative updates
    A reboot may be required after triggering deployment - the script will advise
    References:
      https://support.microsoft.com/en-us/topic/5068202  (registry keys)
      https://directaccess.richardhicks.com/2025/12/04/windows-secure-boot-uefi-certificates-expiring-june-2026/
      https://github.com/richardhicks/uefi  (Get-UEFICertificate tool)
#>

#Requires -RunAsAdministrator

# ── Console formatting helpers ────────────────────────────────────────────────
function Write-Status {
    param([string]$Message, [string]$Color = 'Cyan')
    Write-Host "  $Message" -ForegroundColor $Color
}
function Write-Step {
    param([string]$Message)
    Write-Host "`n[ $Message ]" -ForegroundColor Yellow
}
function Write-Pass  { param([string]$m) Write-Host "  [PASS] $m" -ForegroundColor Green }
function Write-Fail  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Warn  { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info  { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Cyan }

# ── Registry paths ────────────────────────────────────────────────────────────
$sbPath        = "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot"
$servicingPath = "$sbPath\Servicing"

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "  Secure Boot Certificate Check & Remediation" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# ── Step 1: Basic prerequisites ───────────────────────────────────────────────
Write-Step "Checking Prerequisites"

# Secure Boot enabled?
$secureBootEnabled = $false
try {
    $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop
}
catch {
    # Non-UEFI or Secure Boot not available
}

if (-not $secureBootEnabled) {
    Write-Fail "Secure Boot is not enabled or this is a non-UEFI system."
    Write-Info "Certificate updates require UEFI with Secure Boot enabled."
    Write-Info "Enable Secure Boot in BIOS/UEFI firmware settings to proceed."
    exit 1
}
Write-Pass "Secure Boot is enabled (UEFI system confirmed)"

# Windows version check - need May 2025+ cumulative update for the cert delivery mechanism
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
Write-Info "OS: $($os.Caption) - Build $build"
if ($build -lt 19041) {
    Write-Fail "Windows 10 version 2004 (build 19041) or later required."
    exit 1
}

# ── Step 2: Ground truth - check UEFI firmware DB directly ───────────────────
Write-Step "Checking UEFI Firmware (Ground Truth)"

$certInFirmware = $false
$firmwareCheckError = $null

try {
    $dbBytes    = (Get-SecureBootUEFI -Name db -ErrorAction Stop).Bytes
    $dbString   = [System.Text.Encoding]::ASCII.GetString($dbBytes)
    $certInFirmware = $dbString -match 'Windows UEFI CA 2023'

    if ($certInFirmware) {
        Write-Pass "'Windows UEFI CA 2023' certificate IS present in UEFI Secure Boot DB."
    }
    else {
        Write-Fail "'Windows UEFI CA 2023' certificate NOT found in UEFI Secure Boot DB."
    }

    # Also check KEK for completeness (informational)
    try {
        $kekBytes  = (Get-SecureBootUEFI -Name KEK -ErrorAction Stop).Bytes
        $kekString = [System.Text.Encoding]::ASCII.GetString($kekBytes)
        $kek2023   = $kekString -match 'KEK 2K CA 2023|Corporation KEK 2K'
        if ($kek2023) {
            Write-Pass "Microsoft KEK 2023 certificate present in firmware KEK variable."
        } else {
            Write-Warn "Microsoft KEK 2023 not detected in firmware KEK variable (may update separately)."
        }
    }
    catch {
        Write-Warn "Could not read KEK variable: $($_.Exception.Message)"
    }
}
catch {
    $firmwareCheckError = $_.Exception.Message
    Write-Warn "Could not read UEFI DB variable: $firmwareCheckError"
    Write-Info "Falling back to registry-only detection."
}

# ── Step 3: Registry status keys ─────────────────────────────────────────────
Write-Step "Checking Registry Status"

function Get-RegValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path $Path)) { return $null }
    try { (Get-ItemProperty -Path $Path -Name $Key -ErrorAction Stop).$Key }
    catch { $null }
}

$availableUpdates     = Get-RegValue -Path $sbPath        -Key "AvailableUpdates"
$managedOptIn         = Get-RegValue -Path $sbPath        -Key "MicrosoftUpdateManagedOptIn"
$highConfidenceOptOut = Get-RegValue -Path $sbPath        -Key "HighConfidenceOptOut"
$uefiStatus           = Get-RegValue -Path $servicingPath -Key "UEFICA2023Status"
$uefiCapable          = Get-RegValue -Path $servicingPath -Key "WindowsUEFICA2023Capable"
$uefiError            = Get-RegValue -Path $servicingPath -Key "UEFICA2023Error"

Write-Info "AvailableUpdates:            $(if ($null -ne $availableUpdates) { '0x{0:X4}' -f $availableUpdates } else { '(not set)' })"
Write-Info "MicrosoftUpdateManagedOptIn: $(if ($null -ne $managedOptIn) { $managedOptIn } else { '(not set)' })"
Write-Info "HighConfidenceOptOut:        $(if ($null -ne $highConfidenceOptOut) { $highConfidenceOptOut } else { '(not set - defaults to 0)' })"
Write-Info "UEFICA2023Status:            $(if ($uefiStatus) { $uefiStatus } else { '(not set)' })"
Write-Info "WindowsUEFICA2023Capable:    $(if ($null -ne $uefiCapable) { $uefiCapable } else { '(not set)' })"
Write-Info "UEFICA2023Error:             $(if ($null -ne $uefiError -and $uefiError -ne 0) { $uefiError } else { 'None' })"

# ── Step 4: Decision ──────────────────────────────────────────────────────────
Write-Step "Assessment"

# Already done - cert confirmed in firmware
if ($certInFirmware) {
    Write-Pass "Device is COMPLIANT. The 2023 Secure Boot certificate is present in firmware."
    Write-Info "No action required."
    exit 0
}

# Registry says done but firmware check failed - treat as done if registry is authoritative
if ($null -eq $firmwareCheckError -and -not $certInFirmware -and $uefiStatus -eq 'Updated' -and $uefiCapable -eq 2) {
    Write-Warn "Registry shows 'Updated' but cert not found in firmware DB scan."
    Write-Warn "This can happen if the boot manager update is still pending a reboot."
    Write-Info "Recommendation: Reboot the device and re-run this script to confirm."
    exit 0
}

# In-progress state
if ($availableUpdates -eq 0x4100) {
    Write-Warn "Certificate deployment is IN PROGRESS (AvailableUpdates=0x4100)."
    Write-Info "Certificates have been applied. A reboot is needed to complete boot manager update."
    Write-Info "Action: Reboot the device, then re-run this script to confirm completion."
    exit 0
}

# Error state
if ($null -ne $uefiError -and $uefiError -ne 0) {
    Write-Fail "Deployment previously attempted but recorded an error: UEFICA2023Error=$uefiError"
    Write-Info "Check Event Viewer > Windows Logs > System for Secure Boot events (IDs 1795, 1796)."
    Write-Info "This may indicate a firmware compatibility issue. Check for a BIOS/firmware update from your OEM."
}

# Not started or needs triggering
Write-Warn "The 2023 Secure Boot certificate is NOT present. Attempting to trigger deployment..."

# ── Step 5: Remediation ───────────────────────────────────────────────────────
Write-Step "Triggering Deployment"

$remediationSuccess = $true

try {
    # Ensure registry path exists
    if (-not (Test-Path $sbPath)) {
        New-Item -Path $sbPath -Force | Out-Null
    }

    # Set all three keys
    Set-ItemProperty -Path $sbPath -Name "AvailableUpdates"            -Value 0x5944 -Type DWORD -Force
    Set-ItemProperty -Path $sbPath -Name "MicrosoftUpdateManagedOptIn" -Value 1      -Type DWORD -Force
    Set-ItemProperty -Path $sbPath -Name "HighConfidenceOptOut"        -Value 0      -Type DWORD -Force

    Write-Pass "Registry keys set: AvailableUpdates=0x5944, MicrosoftUpdateManagedOptIn=1, HighConfidenceOptOut=0"
}
catch {
    Write-Fail "Failed to set registry keys: $($_.Exception.Message)"
    $remediationSuccess = $false
}

# Kick the scheduled task immediately (normally runs every 12 hours)
if ($remediationSuccess) {
    try {
        $task = Get-ScheduledTask -TaskName "Secure-Boot-Update" -TaskPath "\Microsoft\Windows\PI\" -ErrorAction Stop
        Start-ScheduledTask -TaskName "Secure-Boot-Update" -TaskPath "\Microsoft\Windows\PI\" -ErrorAction Stop
        Write-Pass "Triggered scheduled task: \Microsoft\Windows\PI\Secure-Boot-Update"
    }
    catch {
        Write-Warn "Could not trigger scheduled task: $($_.Exception.Message)"
        Write-Info "The task will run automatically within 12 hours."
    }
}

# ── Step 6: Next steps ────────────────────────────────────────────────────────
Write-Step "Next Steps"

if ($remediationSuccess) {
    Write-Host @"

  Deployment has been triggered. The process takes two reboots to complete fully:

  Step 1 - After this script runs:
    - The Secure-Boot-Update task is processing certificates into firmware
    - AvailableUpdates will change from 0x5944 → 0x4100 when certs are applied
    - UEFICA2023Status will change: NotStarted → InProgress

  Step 2 - REBOOT the device, then:
    - Run the scheduled task again manually, OR wait up to 12 hours:
        Start-ScheduledTask -TaskName "\Microsoft\Windows\PI\Secure-Boot-Update"
    - This updates the boot manager to the 2023-signed version
    - AvailableUpdates will change from 0x4100 → 0x4000 (final state)
    - UEFICA2023Status will show: Updated

  Step 3 - Re-run this script to confirm completion.

  To monitor progress now:
    Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot" |
      Select-Object AvailableUpdates, MicrosoftUpdateManagedOptIn
    Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing" |
      Select-Object UEFICA2023Status, UEFICA2023Error, WindowsUEFICA2023Capable

"@ -ForegroundColor Cyan
}
else {
    Write-Fail "Remediation could not be applied. Verify this script is running as Administrator."
}

exit 0