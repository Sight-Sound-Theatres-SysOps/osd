<#
.SYNOPSIS
    Secure Boot Certificate Status Check - Read Only

.DESCRIPTION
    Reports the current state of Secure Boot certificate deployment.
    Makes NO changes to the device.

    Shows:
      - Whether the 2023 cert is present in UEFI firmware (ground truth)
      - All relevant registry values with human-readable explanations
      - Overall deployment status summary

.NOTES
    Must run as Administrator (required for Get-SecureBootUEFI)
#>

#Requires -RunAsAdministrator

# ── Registry paths ────────────────────────────────────────────────────────────
$sbPath        = "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot"
$servicingPath = "$sbPath\Servicing"

function Get-RegValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path $Path)) { return $null }
    try { (Get-ItemProperty -Path $Path -Name $Key -ErrorAction Stop).$Key }
    catch { $null }
}

# ── Header ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Secure Boot Certificate Status Report" -ForegroundColor Cyan
Write-Host "  $($env:COMPUTERNAME)  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# ── Section 1: Firmware (ground truth) ───────────────────────────────────────
Write-Host "`n---- UEFI Firmware (Ground Truth) ----" -ForegroundColor Yellow

$secureBootEnabled = $false
try { $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop } catch {}

if (-not $secureBootEnabled) {
    Write-Host "  Secure Boot : " -NoNewline
    Write-Host "DISABLED or non-UEFI system" -ForegroundColor Red
    Write-Host "  Certificate updates require UEFI with Secure Boot enabled." -ForegroundColor Gray
} else {
    Write-Host "  Secure Boot : " -NoNewline
    Write-Host "Enabled" -ForegroundColor Green

    # DB cert check
    try {
        $dbBytes        = (Get-SecureBootUEFI -Name db -ErrorAction Stop).Bytes
        $dbString       = [System.Text.Encoding]::ASCII.GetString($dbBytes)
        $certInFirmware = $dbString -match 'Windows UEFI CA 2023'

        Write-Host "  2023 Cert in Firmware DB : " -NoNewline
        if ($certInFirmware) {
            Write-Host "YES - Windows UEFI CA 2023 is present" -ForegroundColor Green
        } else {
            Write-Host "NO  - Windows UEFI CA 2023 not found" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  2023 Cert in Firmware DB : " -NoNewline
        Write-Host "Unable to read ($($_.Exception.Message))" -ForegroundColor Yellow
    }

    # KEK check
    try {
        $kekBytes  = (Get-SecureBootUEFI -Name KEK -ErrorAction Stop).Bytes
        $kekString = [System.Text.Encoding]::ASCII.GetString($kekBytes)
        $kek2023   = $kekString -match 'KEK 2K CA 2023|Corporation KEK 2K'

        Write-Host "  2023 KEK in Firmware     : " -NoNewline
        if ($kek2023) {
            Write-Host "YES - Microsoft KEK 2023 is present" -ForegroundColor Green
        } else {
            Write-Host "NO  - Microsoft KEK 2023 not found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  2023 KEK in Firmware     : " -NoNewline
        Write-Host "Unable to read ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

# ── Section 2: Registry values ────────────────────────────────────────────────
Write-Host "`n---- Registry Values ----" -ForegroundColor Yellow

# AvailableUpdates
$availableUpdates = Get-RegValue -Path $sbPath -Key "AvailableUpdates"

$auHex     = if ($null -ne $availableUpdates) { '0x{0:X4}' -f $availableUpdates } else { '(not set)' }
$auMeaning = switch ($availableUpdates) {
    $null    { "Not configured - deployment not triggered" }
    0x0000   { "0 - Cleared, no pending updates" }
    0x5944   { "Deployment triggered - task will process all cert updates and boot manager" }
    0x4100   { "Certs applied to firmware, reboot required to update boot manager" }
    0x4000   { "Complete - all updates processed, this is the expected final state" }
    0x4104   { "WARNING: KEK update stuck (0x0004 bit not clearing) - may need OEM firmware update" }
    default  { "Partial/in-progress - some bits still being processed" }
}

Write-Host ""
Write-Host "  AvailableUpdates" -ForegroundColor White
Write-Host "    Value   : $auHex  ($availableUpdates)" -ForegroundColor Cyan
Write-Host "    Meaning : $auMeaning" -ForegroundColor Gray
Write-Host "    Purpose : Bitmask that tells the Secure-Boot-Update scheduled task what" -ForegroundColor DarkGray
Write-Host "              operations to perform. Bits clear as each step completes." -ForegroundColor DarkGray

# MicrosoftUpdateManagedOptIn
$managedOptIn = Get-RegValue -Path $sbPath -Key "MicrosoftUpdateManagedOptIn"

$moiValue   = if ($null -ne $managedOptIn) { $managedOptIn } else { '(not set)' }
$moiMeaning = switch ($managedOptIn) {
    $null { "Not set - opted OUT of Microsoft controlled feature rollout (default)" }
    0     { "0 - Opted OUT of Microsoft controlled feature rollout" }
    1     { "1 - Opted IN to Microsoft managed rollout (requires diagnostic data enabled)" }
    default { "Unknown value: $managedOptIn" }
}

Write-Host ""
Write-Host "  MicrosoftUpdateManagedOptIn" -ForegroundColor White
Write-Host "    Value   : $moiValue" -ForegroundColor Cyan
Write-Host "    Meaning : $moiMeaning" -ForegroundColor Gray
Write-Host "    Purpose : Opts the device into Microsoft's Controlled Feature Rollout (CFR)" -ForegroundColor DarkGray
Write-Host "              where Microsoft manages and monitors the cert deployment." -ForegroundColor DarkGray

# HighConfidenceOptOut
$highConfOptOut = Get-RegValue -Path $sbPath -Key "HighConfidenceOptOut"

$hcoValue   = if ($null -ne $highConfOptOut) { $highConfOptOut } else { '(not set)' }
$hcoMeaning = switch ($highConfOptOut) {
    $null { "Not set - opted IN to high-confidence automatic updates via monthly patches (default)" }
    0     { "0 - Opted IN, device will receive cert updates automatically via monthly updates if eligible" }
    1     { "1 - Opted OUT, automatic deployment via monthly updates is blocked" }
    default { "Unknown value: $highConfOptOut" }
}

Write-Host ""
Write-Host "  HighConfidenceOptOut" -ForegroundColor White
Write-Host "    Value   : $hcoValue" -ForegroundColor Cyan
Write-Host "    Meaning : $hcoMeaning" -ForegroundColor Gray
Write-Host "    Purpose : Controls whether Microsoft can push cert updates automatically" -ForegroundColor DarkGray
Write-Host "              through monthly cumulative updates for validated devices." -ForegroundColor DarkGray

# ── Section 3: Servicing/status keys ─────────────────────────────────────────
Write-Host "`n---- Deployment Status (Servicing Keys) ----" -ForegroundColor Yellow

$uefiStatus  = Get-RegValue -Path $servicingPath -Key "UEFICA2023Status"
$uefiCapable = Get-RegValue -Path $servicingPath -Key "WindowsUEFICA2023Capable"
$uefiError   = Get-RegValue -Path $servicingPath -Key "UEFICA2023Error"

# UEFICA2023Status
$statusMeaning = switch ($uefiStatus) {
    $null        { "Not present - deployment has not started on this device" }
    "NotStarted" { "Deployment has not started yet" }
    "InProgress" { "Deployment is currently in progress" }
    "Updated"    { "Deployment completed successfully" }
    "Failed"     { "Deployment failed - check UEFICA2023Error for details" }
    default      { $uefiStatus }
}

Write-Host ""
Write-Host "  UEFICA2023Status" -ForegroundColor White
Write-Host "    Value   : $(if ($uefiStatus) { $uefiStatus } else { '(not set)' })" -ForegroundColor Cyan
Write-Host "    Meaning : $statusMeaning" -ForegroundColor Gray
Write-Host "    Purpose : Tracks the overall deployment state from start to completion." -ForegroundColor DarkGray

# WindowsUEFICA2023Capable
$capableMeaning = switch ($uefiCapable) {
    $null { "Not set - capability not yet evaluated" }
    0     { "0 - Device not capable of receiving the update" }
    1     { "1 - Device is capable, update is in progress" }
    2     { "2 - Update successfully applied" }
    default { "Unknown value: $uefiCapable" }
}

Write-Host ""
Write-Host "  WindowsUEFICA2023Capable" -ForegroundColor White
Write-Host "    Value   : $(if ($null -ne $uefiCapable) { $uefiCapable } else { '(not set)' })" -ForegroundColor Cyan
Write-Host "    Meaning : $capableMeaning" -ForegroundColor Gray
Write-Host "    Purpose : Indicates whether this device's firmware can accept the update." -ForegroundColor DarkGray

# UEFICA2023Error
$errorMeaning = if ($null -eq $uefiError -or $uefiError -eq 0) {
    "No errors recorded"
} else {
    "Error code $uefiError - check Event Viewer > Windows Logs > System for Secure Boot events (IDs 1795, 1796)"
}

Write-Host ""
Write-Host "  UEFICA2023Error" -ForegroundColor White
Write-Host "    Value   : $(if ($null -ne $uefiError -and $uefiError -ne 0) { $uefiError } else { '0 / None' })" -ForegroundColor Cyan
Write-Host "    Meaning : $errorMeaning" -ForegroundColor $(if ($null -ne $uefiError -and $uefiError -ne 0) { 'Red' } else { 'Gray' })
Write-Host "    Purpose : Records any error that occurred during the deployment process." -ForegroundColor DarkGray

# ── Section 4: Summary ────────────────────────────────────────────────────────
Write-Host "`n---- Summary ----" -ForegroundColor Yellow
Write-Host ""

$certInFirmwareFinal = $false
try {
    $bytes = (Get-SecureBootUEFI -Name db -ErrorAction Stop).Bytes
    $certInFirmwareFinal = ([System.Text.Encoding]::ASCII.GetString($bytes)) -match 'Windows UEFI CA 2023'
} catch {}

if (-not $secureBootEnabled) {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "NOT APPLICABLE - Secure Boot is not enabled" -ForegroundColor Yellow
} elseif ($certInFirmwareFinal) {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "COMPLETE - 2023 certificate confirmed in firmware" -ForegroundColor Green
} elseif ($availableUpdates -eq 0x4100) {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "IN PROGRESS - Reboot required to complete boot manager update" -ForegroundColor Yellow
} elseif ($availableUpdates -eq 0x5944) {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "IN PROGRESS - Deployment triggered, waiting for scheduled task to run" -ForegroundColor Yellow
} elseif ($null -ne $uefiError -and $uefiError -ne 0) {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "ERROR - Deployment attempted but failed (Error: $uefiError)" -ForegroundColor Red
} else {
    Write-Host "  STATUS: " -NoNewline
    Write-Host "NOT STARTED - Certificate not present, deployment not triggered" -ForegroundColor Red
}

Write-Host ""