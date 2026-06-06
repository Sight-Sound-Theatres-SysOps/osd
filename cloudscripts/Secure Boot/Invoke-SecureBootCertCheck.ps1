#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Interactive admin tool to assess, remediate, and track Secure Boot certificate
    update status on Dell devices ahead of the June 2026 Microsoft cert expiration.

.DESCRIPTION
    Performs a full assessment of a device's Secure Boot certificate status by combining
    three data sources:

      1. Firmware ground truth  -- Get-UEFICertificate (Richard Hicks, PSGallery) reads
         PK, KEK, and DB entries directly from UEFI NVRAM.

      2. Windows registry       -- Servicing keys under SecureBoot\Servicing report the
         deployment state, error codes, and compatibility classification Windows assigned.

      3. System event log       -- Event IDs 1795, 1796, 1800, 1803, 1808 from Windows
         are the definitive indicators Microsoft points to for troubleshooting.

    Also performs a Dell BIOS check using the OSD module (Get-MyDellBIOS / Get-DellCatalogPC)
    which queries Dell's CatalogPC.xml directly -- no API key required.

    A persistent status file is maintained at C:\ProgramData\SecureBootCertCheck\status.json
    to track run history, phase, and reboot count across sessions.  An intern running this
    on multiple devices can use this history to determine next actions without needing to
    understand the underlying registry values.

    Expiring certs being replaced:
      KEK  -- Microsoft Corporation KEK CA 2011       expires 2026-06-24
      DB   -- Microsoft Corporation UEFI CA 2011      expires 2026-06-27
      DB   -- Microsoft Windows Production PCA 2011   expires 2026-10-19

.PARAMETER StatusFilePath
    Override the default status file path.
    Default: C:\ProgramData\SecureBootCertCheck\status.json

.PARAMETER SkipFirmwareScan
    Skip Get-UEFICertificate firmware scan.  Use when PSGallery is blocked.

.PARAMETER SkipBiosCheck
    Skip OSD module BIOS version check.  Use when internet access is unavailable.

.EXAMPLE
    .\Invoke-SecureBootCertCheck.ps1

.EXAMPLE
    .\Invoke-SecureBootCertCheck.ps1 -SkipBiosCheck

.NOTES
    PSVersion  : 5.1+
    Context    : Interactive admin tool -- run by a tech or intern at each device
    Requires   : Administrator rights
    References :
      https://support.microsoft.com/en-us/topic/5068202          (registry key deployment)
      https://support.microsoft.com/en-us/topic/5085046          (MS troubleshooting guide)
      https://directaccess.richardhicks.com/2025/12/04/          (Richard Hicks blog)
      https://github.com/richardhicks/uefi                       (Get-UEFICertificate)
      https://www.dell.com/support/kbdoc/en-us/000347876         (Dell supported models)
      https://www.dell.com/support/kbdoc/en-us/000378734         (Dell out-of-scope models)
      https://osd.osdeploy.com/docs/trash/dell/get-mydellbios    (OSD module BIOS check)
#>

[CmdletBinding()]
param (
    [string]$StatusFilePath  = 'C:\ProgramData\SecureBootCertCheck\status.json',
    [switch]$SkipFirmwareScan,
    [switch]$SkipBiosCheck
)

# ── PS7 / PowerShell Core relaunch guard ─────────────────────────────────────
# This script requires Windows PowerShell 5.1 for full compatibility with
# PSGallery, the OSD module, and the SecureBoot cmdlets.  If running under
# PowerShell 7 (Core), automatically relaunch in powershell.exe 5.1.
# -Verb RunAs also handles elevation in case the tech forgot to run as admin.
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host ''
    Write-Host '  [INFO] PowerShell 7 detected.  Relaunching in Windows PowerShell 5.1...' -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        Write-Host '  [FAIL] Could not determine script path for relaunch.' -ForegroundColor Red
        Write-Host '         Please run this script from Windows PowerShell 5.1 (powershell.exe).' -ForegroundColor Red
        exit 1
    }

    # Build parameter string to pass through to the relaunched session
    $passParams = ''
    if ($StatusFilePath -ne 'C:\ProgramData\SecureBootCertCheck\status.json') {
        $passParams += " -StatusFilePath '$StatusFilePath'"
    }
    if ($SkipFirmwareScan) { $passParams += ' -SkipFirmwareScan' }
    if ($SkipBiosCheck)    { $passParams += ' -SkipBiosCheck' }

    # Use -Command instead of -File so we can append a pause after the script
    # finishes.  -File ignores anything after the script path, but -Command
    # lets us chain statements with semicolons.
    $cmd = "& { & '$scriptPath'$passParams; Write-Host ''; Write-Host '  Press any key to close this window...' -ForegroundColor DarkGray; `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }"
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $cmd" `
        -Verb RunAs -Wait
    exit
}

$ErrorActionPreference = 'Stop'

# ── Registry paths ────────────────────────────────────────────────────────────
$sbPath        = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
$servicingPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing'

# ── 2023 cert identification ──────────────────────────────────────────────────
# Match on subject name (CN) as primary -- thumbprints can vary across OEM-specific
# cert packages.  Thumbprints are kept for logging and secondary confirmation only.
$kekSubject2023    = 'Microsoft Corporation KEK 2K CA 2023'
$kekThumbprint2023 = '5DCA954671E1A2EA78D8CC8A60AC3BCDE8CD0F87'   # for logging only

$dbSubjects2023 = [ordered]@{
    'Windows UEFI CA 2023'              = '45A0FA32604773C82433C3B7D59E7466B3AC0C67'
    'Microsoft UEFI CA 2023'            = 'B5EEB4A6706048073F0ED296E7F580A790B59EAA'
    'Microsoft Option ROM UEFI CA 2023' = '3FB39E2B8BD183BF9E4594E72183CA60AFCD4277'
}
# Keep thumbprint lookup for display tagging (used in the table rendering)
$dbThumbprints2023 = [ordered]@{
    'Windows UEFI CA 2023'              = '45A0FA32604773C82433C3B7D59E7466B3AC0C67'
    'Microsoft UEFI CA 2023'            = 'B5EEB4A6706048073F0ED296E7F580A790B59EAA'
    'Microsoft Option ROM UEFI CA 2023' = '3FB39E2B8BD183BF9E4594E72183CA60AFCD4277'
}

# ── Expiring 2011 cert thumbprints ────────────────────────────────────────────
$expiring2011 = @{
    '31590BFD89C9D74ED087DFAC66334B3931254B30' = 'Microsoft Corporation KEK CA 2011  (expires 2026-06-24)'
    '46DEF63B5CE61CF8BA0DE2E6639C1019D0ED14F3' = 'Microsoft Corporation UEFI CA 2011  (expires 2026-06-27)'
    '580A6F4CC4E4B669B9EBDC1B2B3E087B80D0678D' = 'Microsoft Windows Production PCA 2011  (expires 2026-10-19)'
}

# ── Dell KB URLs for dynamic compatibility lookup ─────────────────────────────
$dellKbSupported   = 'https://www.dell.com/support/kbdoc/en-us/000347876/microsoft-2011-secure-boot-certificate-expiration'
$dellKbOutOfScope  = 'https://www.dell.com/support/kbdoc/en-us/000378734/microsoft-2011-secure-boot-certificates-expiration-for-out-of-scope-platforms-for-bios-updates'

# Cache lives alongside the status file so it survives across runs on the same device
$dellKbCacheDir    = Split-Path $StatusFilePath
$dellKbCache347    = Join-Path $dellKbCacheDir 'dell_kb347876.html'
$dellKbCache378    = Join-Path $dellKbCacheDir 'dell_kb378734.html'
$dellKbCacheMinutes = 1440   # Re-fetch once per day at most

# ── Dell KB page fetcher with local cache ────────────────────────────────────
function Get-DellKbPage {
    param(
        [string]$Url,
        [string]$CachePath,
        [int]$CacheMinutes
    )

    # Return cached copy if still fresh
    if (Test-Path $CachePath) {
        $age = (Get-Date) - (Get-Item $CachePath).LastWriteTime
        if ($age.TotalMinutes -lt $CacheMinutes) {
            Write-Verbose "Using cached Dell KB page: $CachePath (age: $([int]$age.TotalMinutes) min)"
            return Get-Content $CachePath -Raw -Encoding utf8
        }
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 `
            -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36' } `
            -ErrorAction Stop
        $html = $response.Content
        $html | Out-File -FilePath $CachePath -Encoding utf8 -Force
        Write-Log "Dell KB page fetched and cached: $Url"
        return $html
    }
    catch {
        Write-Log "WARN: Could not fetch Dell KB page $Url -- $($_.Exception.Message)"
        # Fall back to stale cache if available rather than returning nothing
        if (Test-Path $CachePath) {
            Write-Verbose "Falling back to stale cache: $CachePath"
            return Get-Content $CachePath -Raw -Encoding utf8
        }
        return $null
    }
}

# ── Dell KB HTML model name parser ───────────────────────────────────────────
function Get-DellModelsFromHtml {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) { return @() }

    $models = [System.Collections.Generic.List[string]]::new()

    # Dell KB pages render model names in <td> and <code> tags inside tables.
    # Extract all <td> cell text, strip inner HTML, and filter to model-shaped strings.
    $tdMatches = [regex]::Matches($Html, '(?s)<td[^>]*>(.*?)</td>')
    foreach ($m in $tdMatches) {
        $text = $m.Groups[1].Value `
            -replace '<[^>]+>', '' `
            -replace '&amp;',   '&' `
            -replace '&nbsp;',  ' ' `
            -replace '\s+',     ' '
        $text = $text.Trim()

        # Keep only strings that look like model names:
        # 5-80 chars, contain letters, not version strings, not headers, not URLs
        if ($text.Length -ge 5 -and
            $text.Length -le 80 -and
            $text -match  '[A-Za-z]' -and
            $text -notmatch '^\d+\.\d+' -and
            $text -notmatch '^https?' -and
            $text -notmatch '^\s*$' -and
            $text -notmatch '^(Platform|Minimum|BIOS|Version|Model|Certificate|Affected)') {
            $models.Add($text)
        }
    }

    # Also capture <code>-tagged model names which Dell uses in the supported list
    $codeMatches = [regex]::Matches($Html, '<code[^>]*>(.*?)</code>')
    foreach ($m in $codeMatches) {
        $text = ($m.Groups[1].Value -replace '<[^>]+>', '' -replace '\s+', ' ').Trim()
        if ($text.Length -ge 5 -and $text -match '[A-Za-z0-9]' -and -not $models.Contains($text)) {
            $models.Add($text)
        }
    }

    return $models.ToArray()
}

# ── Fuzzy model name matcher ──────────────────────────────────────────────────
function Test-DellModelMatch {
    param(
        [string]  $DeviceModel,
        [string[]]$ModelList
    )

    # Normalize both sides: strip leading "Dell ", collapse whitespace
    $normalized = ($DeviceModel -replace '^Dell\s+', '' -replace '\s+', ' ').Trim()

    foreach ($entry in $ModelList) {
        $entryNorm = ($entry -replace '^Dell\s+', '' -replace '\s+', ' ').Trim()
        if ($normalized -ieq $entryNorm)          { return $true }
        if ($normalized -ilike "*$entryNorm*")    { return $true }
        if ($entryNorm  -ilike "*$normalized*")   { return $true }
    }
    return $false
}

# ── Dell compatibility lookup (called once, results cached in variables) ──────
function Get-DellCompatibility {
    param([string]$DeviceModel)

    # Returns a hashtable with keys:
    #   IsSupported    -- $true if on KB 000347876
    #   IsOutOfScope   -- $true if on KB 000378734
    #   LookupWorked   -- $false if both pages failed to fetch
    #   SupportedCount -- number of models parsed from supported page
    #   OutOfScopeCount-- number of models parsed from out-of-scope page

    $result = @{
        IsSupported     = $false
        IsOutOfScope    = $false
        LookupWorked    = $false
        SupportedCount  = 0
        OutOfScopeCount = 0
    }

    $htmlSupported  = Get-DellKbPage -Url $dellKbSupported  -CachePath $dellKbCache347 -CacheMinutes $dellKbCacheMinutes
    $htmlOutOfScope = Get-DellKbPage -Url $dellKbOutOfScope -CachePath $dellKbCache378 -CacheMinutes $dellKbCacheMinutes

    if ($null -eq $htmlSupported -and $null -eq $htmlOutOfScope) {
        return $result   # LookupWorked stays $false
    }

    $result.LookupWorked = $true

    if ($htmlSupported) {
        $supportedModels       = Get-DellModelsFromHtml -Html $htmlSupported
        $result.SupportedCount = $supportedModels.Count
        $result.IsSupported    = Test-DellModelMatch -DeviceModel $DeviceModel -ModelList $supportedModels
    }

    if ($htmlOutOfScope) {
        $outOfScopeModels       = Get-DellModelsFromHtml -Html $htmlOutOfScope
        $result.OutOfScopeCount = $outOfScopeModels.Count
        $result.IsOutOfScope    = Test-DellModelMatch -DeviceModel $DeviceModel -ModelList $outOfScopeModels
    }

    return $result
}

# ── Console output helpers ────────────────────────────────────────────────────
function Write-Step  { param([string]$m) Write-Host "`n  [ $m ]" -ForegroundColor Yellow }
function Write-Pass  { param([string]$m) Write-Host "  [PASS] $m" -ForegroundColor Green }
function Write-Fail  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Warn  { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info  { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Cyan }
function Write-Fatal { param([string]$m) Write-Host "  [!!]   $m" -ForegroundColor Magenta }
function Write-Detail{ param([string]$m) Write-Host "         $m" -ForegroundColor Gray }

function Write-SectionLine {
    Write-Host ('  ' + ('-' * 66)) -ForegroundColor DarkGray
}

function Write-Log {
    param([string]$Message)
    $logDir = Split-Path $StatusFilePath
    $logFile = Join-Path $logDir 'check.log'
    try {
        '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message |
            Out-File -FilePath $logFile -Append -Encoding utf8
    }
    catch { }
}

function Prompt-YesNo {
    param([string]$Question, [string]$Default = 'N')
    $hint = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    Write-Host ''
    Write-Host "  $Question $hint " -ForegroundColor White -NoNewline
    $response = Read-Host
    if ([string]::IsNullOrWhiteSpace($response)) { $response = $Default }
    return $response -match '^[Yy]'
}

# ── Status file helpers ───────────────────────────────────────────────────────
function Read-StatusFile {
    if (Test-Path $StatusFilePath) {
        try {
            return Get-Content $StatusFilePath -Raw | ConvertFrom-Json
        }
        catch { }
    }
    return $null
}

function Write-StatusFile {
    param([hashtable]$Data)
    try {
        $dir = Split-Path $StatusFilePath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $Data | ConvertTo-Json -Depth 5 | Out-File -FilePath $StatusFilePath -Encoding utf8 -Force
    }
    catch {
        Write-Warn "Could not write status file: $($_.Exception.Message)"
    }
}

# ── PowerShellGet bootstrap ───────────────────────────────────────────────────
# PowerShellGet v2/v3 side-by-side conflicts are common on managed endpoints.
# Force-import the highest available version once before any gallery operations,
# then cache whether gallery cmdlets are usable so we don't repeat this per call.
$script:PSGetAvailable = $false
function Initialize-PSGet {
    if ($script:PSGetAvailable) { return $true }
    try {
        # Prefer v3 (PSResourceGet) if present, fall back to v2
        $psget = Get-Module -ListAvailable -Name 'PowerShellGet' |
                 Sort-Object Version -Descending |
                 Select-Object -First 1
        if ($null -ne $psget) {
            Import-Module PowerShellGet -RequiredVersion $psget.Version -Force -ErrorAction Stop
        }
        # Smoke-test that Find-Module is callable
        $null = Get-Command Find-Module -ErrorAction Stop
        $script:PSGetAvailable = $true
        return $true
    }
    catch {
        Write-Log "WARN: PowerShellGet could not be loaded -- $($_.Exception.Message)"
        return $false
    }
}

# ── PSGallery trust helper ────────────────────────────────────────────────────
function Set-PSGalleryTrusted {
    try {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($null -ne $repo -and $repo.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

# ── Module install/update helpers ─────────────────────────────────────────────
function Ensure-Module {
    param([string]$ModuleName)

    $installed = Get-Module -ListAvailable -Name $ModuleName |
                 Sort-Object Version -Descending |
                 Select-Object -First 1

    if ($null -ne $installed) {
        # Try gallery version check -- skip gracefully if PSGet unavailable
        if (Initialize-PSGet) {
            try {
                $gallery = Find-Module -Name $ModuleName -ErrorAction Stop
                if ([version]$gallery.Version -gt [version]$installed.Version) {
                    Write-Info "$ModuleName $($installed.Version) installed.  Newer version $($gallery.Version) available.  Updating..."
                    # Remove old versions first to avoid side-by-side conflicts
                    Get-Module -ListAvailable -Name $ModuleName | ForEach-Object {
                        try { Uninstall-Module -Name $ModuleName -RequiredVersion $_.Version -Force -ErrorAction SilentlyContinue } catch { }
                    }
                    Set-PSGalleryTrusted
                    Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                    Write-Pass "$ModuleName updated to $($gallery.Version)."
                }
                else {
                    Write-Pass "$ModuleName $($installed.Version) is current."
                }
            }
            catch {
                # Non-fatal -- module is installed, version check just failed
                Write-Pass "$ModuleName $($installed.Version) is installed.  (Version check skipped: $($_.Exception.Message))"
                Write-Log  "WARN: $ModuleName version check failed -- $($_.Exception.Message)"
            }
        }
        else {
            Write-Pass "$ModuleName $($installed.Version) is installed.  (PSGallery unavailable -- version check skipped)"
        }
        return $true
    }

    # Module not installed -- need PSGet to install it
    if (-not (Initialize-PSGet)) {
        Write-Warn "$ModuleName is not installed and PowerShellGet could not be loaded to install it."
        Write-Info 'Run: Install-Module -Name OSD -Scope CurrentUser  in a fresh PowerShell session, then re-run this script.'
        Write-Log  "WARN: Cannot install $ModuleName -- PowerShellGet unavailable"
        return $false
    }

    Write-Info "$ModuleName not found.  Installing from PSGallery..."
    try {
        Set-PSGalleryTrusted
        Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        Write-Pass "$ModuleName installed."
        return $true
    }
    catch {
        Write-Warn "Could not install $ModuleName : $($_.Exception.Message)"
        Write-Log  "ERROR: Install $ModuleName failed -- $($_.Exception.Message)"
        return $false
    }
}

function Ensure-Script {
    param([string]$ScriptName)

    # Check if script is already on PATH (installed via Install-Script)
    $installedPath = Get-Command "$ScriptName.ps1" -ErrorAction SilentlyContinue
    $installed      = $null
    if (Initialize-PSGet) {
        try { $installed = Get-InstalledScript -Name $ScriptName -ErrorAction SilentlyContinue } catch { }
    }

    if ($null -ne $installed -or $null -ne $installedPath) {
        if (Initialize-PSGet -and $null -ne $installed) {
            try {
                $gallery = Find-Script -Name $ScriptName -ErrorAction Stop
                if ([version]$gallery.Version -gt [version]$installed.Version) {
                    Write-Info "$ScriptName $($installed.Version) installed.  Updating to $($gallery.Version)..."
                    try { Uninstall-Script -Name $ScriptName -Force -ErrorAction SilentlyContinue } catch { }
                    Set-PSGalleryTrusted
                    Install-Script -Name $ScriptName -Force -Scope CurrentUser -ErrorAction Stop
                    Write-Pass "$ScriptName updated to $($gallery.Version)."
                }
                else {
                    Write-Pass "$ScriptName $($installed.Version) is current."
                }
            }
            catch {
                Write-Pass "$ScriptName is installed.  (Version check skipped: $($_.Exception.Message))"
                Write-Log  "WARN: $ScriptName version check failed -- $($_.Exception.Message)"
            }
        }
        else {
            Write-Pass "$ScriptName is installed.  (PSGallery unavailable -- version check skipped)"
        }
        return $true
    }

    # Script not installed
    if (-not (Initialize-PSGet)) {
        Write-Warn "$ScriptName is not installed and PowerShellGet could not be loaded to install it."
        Write-Info "Run: Install-Script -Name $ScriptName -Scope CurrentUser  in a fresh PowerShell session, then re-run this script."
        Write-Log  "WARN: Cannot install $ScriptName -- PowerShellGet unavailable"
        return $false
    }

    Write-Info "$ScriptName not found.  Installing from PSGallery..."
    try {
        Set-PSGalleryTrusted
        Install-Script -Name $ScriptName -Force -Scope CurrentUser -ErrorAction Stop
        Write-Pass "$ScriptName installed."
        return $true
    }
    catch {
        Write-Warn "Could not install $ScriptName : $($_.Exception.Message)"
        Write-Log  "ERROR: Install $ScriptName failed -- $($_.Exception.Message)"
        return $false
    }
}

# ── Reboot helper ─────────────────────────────────────────────────────────────
function Invoke-RebootPrompt {
    param([string]$Reason)
    Write-Host ''
    Write-Warn "A reboot is required: $Reason"
    if (Prompt-YesNo -Question 'Reboot now?' -Default 'N') {
        Write-Host ''
        Write-Info 'Rebooting in 15 seconds.  Close any open applications now.'
        Write-Info 'After reboot, re-run this script to confirm status.'
        for ($i = 15; $i -gt 0; $i--) {
            Write-Host "`r  Rebooting in $i seconds...  (Ctrl+C to cancel)" -NoNewline
            Start-Sleep -Seconds 1
        }
        Write-Host ''
        Restart-Computer -Force
    }
    else {
        Write-Info 'Reboot skipped.  Remember to reboot this device before re-running the script.'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN SCRIPT
# ─────────────────────────────────────────────────────────────────────────────

# Ensure status/log directory exists
try {
    $statusDir = Split-Path $StatusFilePath
    if (-not (Test-Path $statusDir)) { New-Item -ItemType Directory -Force -Path $statusDir | Out-Null }
}
catch { }

# ── Header ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  ================================================================' -ForegroundColor Cyan
Write-Host '   Secure Boot Certificate Assessment and Remediation Tool' -ForegroundColor Cyan
Write-Host '   Sight and Sound Theatres -- Systems Engineering' -ForegroundColor Cyan
Write-Host "   $env:COMPUTERNAME  --  $(Get-Date -Format 'yyyy-MM-dd  HH:mm:ss')" -ForegroundColor Cyan
Write-Host '  ================================================================' -ForegroundColor Cyan

Write-Log "=== Run started on $env:COMPUTERNAME ==="

# ── Hardware info ─────────────────────────────────────────────────────────────
Write-Step 'Device Information'

$cs      = Get-CimInstance -ClassName Win32_ComputerSystem   -ErrorAction SilentlyContinue
$bios    = Get-CimInstance -ClassName Win32_BIOS              -ErrorAction SilentlyContinue
$os      = Get-CimInstance -ClassName Win32_OperatingSystem   -ErrorAction SilentlyContinue
$hotfix  = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1 -ErrorAction SilentlyContinue

$manufacturer  = $cs.Manufacturer
$model         = $cs.Model
$serviceTag    = $bios.SerialNumber
$biosVersion   = $bios.SMBIOSBIOSVersion
$biosDateRaw   = $bios.ReleaseDate
$biosDate      = if ($biosDateRaw) { ([datetime]$biosDateRaw).ToString('yyyy-MM-dd') } else { 'Unknown' }
$winVersion    = $os.Caption
$winBuild      = $os.BuildNumber
$winUbr        = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR
$latestKB      = if ($hotfix) { "$($hotfix.HotFixID)  (installed $($hotfix.InstalledOn.ToString('yyyy-MM-dd')))" } else { 'Unknown' }

# Join type detection
$joinType = 'Workgroup'
try {
    $dsreg = dsregcmd /status 2>$null
    $aadJoined     = ($dsreg | Select-String 'AzureAdJoined\s*:\s*YES')
    $domainJoined  = ($dsreg | Select-String 'DomainJoined\s*:\s*YES')
    if ($aadJoined -and $domainJoined) { $joinType = 'Hybrid (AD + Entra)' }
    elseif ($aadJoined)                { $joinType = 'Entra ID joined' }
    elseif ($domainJoined)             { $joinType = 'Domain joined' }
}
catch { }

$isDell = $manufacturer -match 'Dell'

Write-SectionLine
Write-Detail "  Manufacturer   : $manufacturer"
Write-Detail "  Model          : $model"
Write-Detail "  Service Tag    : $serviceTag"
Write-Detail "  BIOS Version   : $biosVersion  ($biosDate)"
Write-Detail "  OS             : $winVersion  (Build $winBuild.$winUbr)"
Write-Detail "  Latest KB      : $latestKB"
Write-Detail "  Join Type      : $joinType"
Write-SectionLine

Write-Log "Hardware: $manufacturer $model | ST: $serviceTag | BIOS: $biosVersion ($biosDate) | OS: $winBuild.$winUbr | Join: $joinType"

# ── Previous run history ──────────────────────────────────────────────────────
$priorStatus = Read-StatusFile
if ($null -ne $priorStatus) {
    Write-Step 'Previous Run History'
    Write-Warn 'This device has a prior run record:'
    Write-SectionLine
    if ($priorStatus.LastRun)        { Write-Detail "  Last run       : $($priorStatus.LastRun)" }
    if ($priorStatus.Phase)          { Write-Detail "  Phase          : $($priorStatus.Phase)" }
    if ($priorStatus.RebootCount)    { Write-Detail "  Reboot count   : $($priorStatus.RebootCount)" }
    if ($priorStatus.LastOutcome)    { Write-Detail "  Last outcome   : $($priorStatus.LastOutcome)" }
    if ($priorStatus.ActionsTaken)   { Write-Detail "  Actions taken  : $($priorStatus.ActionsTaken -join ', ')" }
    if ($priorStatus.FlaggedForReplacement -eq $true) {
        Write-Fatal '  *** THIS DEVICE WAS PREVIOUSLY FLAGGED FOR REPLACEMENT ***'
    }
    Write-SectionLine
    Write-Info 'Continuing with fresh assessment...'
}

# ── Step 1: Prerequisites ─────────────────────────────────────────────────────
Write-Step 'Prerequisites'

$secureBootEnabled = $false
try { $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop } catch { }

if (-not $secureBootEnabled) {
    Write-Fail 'Secure Boot is not enabled or this is a legacy BIOS (non-UEFI) system.'
    Write-Info 'Certificate updates require UEFI with Secure Boot enabled.  No action taken.'
    Write-Log  'RESULT: Secure Boot not enabled -- exiting'

    Write-StatusFile @{
        ComputerName = $env:COMPUTERNAME
        LastRun      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Phase        = 'NotApplicable'
        LastOutcome  = 'SECURE_BOOT_DISABLED'
        ActionsTaken = @()
    }
    exit 0
}
Write-Pass 'Secure Boot is enabled.'

# Check scheduled task exists
$taskExists = $false
try {
    $task = Get-ScheduledTask -TaskName 'Secure-Boot-Update' -TaskPath '\Microsoft\Windows\PI\' -ErrorAction Stop
    $taskExists = $true
    Write-Pass "Secure Boot update scheduled task found  (state: $($task.State))"
}
catch {
    Write-Warn 'Scheduled task \Microsoft\Windows\PI\Secure-Boot-Update not found.'
    Write-Info 'Remediation via registry trigger will still be attempted, but the task may not run automatically.'
    Write-Log  'WARN: Secure-Boot-Update scheduled task not found'
}

# ── Step 2: Module and script installation ───────────────────────────────────
Write-Step 'Checking Required Modules and Scripts'

$osdAvailable  = $false
$uefiScriptAvailable = $false

if (-not $SkipBiosCheck) {
    if ($isDell) {
        $osdAvailable = Ensure-Module -ModuleName 'OSD'
    }
    else {
        Write-Info 'Non-Dell device.  Skipping OSD module (Dell BIOS check not applicable).'
    }
}
else {
    Write-Info '-SkipBiosCheck specified.  Skipping OSD module install.'
}

if (-not $SkipFirmwareScan) {
    $uefiScriptAvailable = Ensure-Script -ScriptName 'Get-UEFICertificate'
}
else {
    Write-Info '-SkipFirmwareScan specified.  Skipping Get-UEFICertificate install.'
}

# ── Step 3: BIOS version check ────────────────────────────────────────────────
$biosUpdateAvailable = $false
$latestBiosVersion   = $null

if ($isDell -and $osdAvailable -and -not $SkipBiosCheck) {
    Write-Step 'Dell BIOS Version Check'

    try {
        # Import OSD if not already loaded
        if (-not (Get-Module -Name OSD)) {
            Import-Module OSD -ErrorAction Stop
        }

        Write-Info 'Querying Dell CatalogPC.xml for latest BIOS...  (this may take a moment)'
        $dellBios = Get-MyDellBIOS -ErrorAction Stop

        if ($null -ne $dellBios) {
            $latestBiosVersion = $dellBios.DellVersion
            Write-SectionLine
            Write-Detail "  Current BIOS   : $biosVersion  ($biosDate)"
            Write-Detail "  Latest BIOS    : $latestBiosVersion"
            Write-Detail "  Release Date   : $($dellBios.ReleaseDate)"
            Write-Detail "  Package        : $($dellBios.Name)"
            Write-SectionLine

            # Simple string comparison -- versions like "1.32.0" vs "1.33.0"
            try {
                $current = [version]($biosVersion -replace '[^0-9.]')
                $latest  = [version]($latestBiosVersion -replace '[^0-9.]')
                if ($latest -gt $current) {
                    $biosUpdateAvailable = $true
                    Write-Warn "A newer BIOS is available: $latestBiosVersion  (current: $biosVersion)"
                    Write-Info 'A BIOS update may resolve Secure Boot certificate issues on this device.'

                    # Dynamic Dell compatibility lookup against live KB pages
                    Write-Info 'Checking Dell compatibility lists (KB 000347876 / KB 000378734)...'
                    $dellCompat = Get-DellCompatibility -DeviceModel $model
                    if ($dellCompat.LookupWorked) {
                        Write-Log "Dell KB lookup: Supported=$($dellCompat.IsSupported), OutOfScope=$($dellCompat.IsOutOfScope), SupportedCount=$($dellCompat.SupportedCount), OutOfScopeCount=$($dellCompat.OutOfScopeCount)"
                        if ($dellCompat.IsOutOfScope) {
                            Write-Warn "NOTE: '$model' is on Dell's out-of-scope list (KB 000378734)."
                            Write-Info 'Dell has no planned BIOS update with 2023 Secure Boot certs for this model.'
                            Write-Info 'A BIOS update may still exist but it may not resolve the KEK cert issue.'
                        }
                        elseif ($dellCompat.IsSupported) {
                            Write-Pass "'$model' is on Dell's supported list (KB 000347876)."
                            Write-Info 'A BIOS update with 2023 Secure Boot certs is confirmed available for this model.'
                        }
                        else {
                            Write-Info "'$model' was not found on either Dell list."
                            Write-Info 'This may be a newer model (all Dell BIOSes after Jan 2026 include 2023 certs).'
                        }
                    }
                    else {
                        Write-Warn 'Could not reach Dell KB pages to check compatibility lists.'
                        Write-Info "Check manually: $dellKbSupported"
                    }
                }
                else {
                    Write-Pass "BIOS is current ($biosVersion)."
                }
            }
            catch {
                # Version parse failed -- do string comparison
                if ($latestBiosVersion -ne $biosVersion) {
                    $biosUpdateAvailable = $true
                    Write-Warn "BIOS may be outdated.  Current: $biosVersion  Latest: $latestBiosVersion"
                }
                else {
                    Write-Pass "BIOS appears current ($biosVersion)."
                }
            }
        }
        else {
            Write-Info 'No BIOS update entry found in Dell catalog for this model.'
            Write-Pass 'BIOS appears current or model not in catalog.'
        }
        Write-Log "BIOS check: current=$biosVersion, latest=$latestBiosVersion, updateAvailable=$biosUpdateAvailable"
    }
    catch {
        Write-Warn "BIOS check failed: $($_.Exception.Message)"
        Write-Info 'Continuing without BIOS version check.'
        Write-Log  "WARN: BIOS check error -- $($_.Exception.Message)"
    }
}
elseif (-not $isDell) {
    Write-Step 'BIOS Version Check'
    Write-Info "Non-Dell device ($manufacturer).  Automated BIOS check not supported."
    Write-Info 'Check your OEM support site manually for firmware updates.'
}

# ── Step 4: Firmware certificate scan ────────────────────────────────────────
$firmwareScanDone       = $false
$firmwareKek2023Present = $false
$firmwareDbResults      = [ordered]@{}
$firmwareExpiringFound  = @()
$firmwareOemKekExpired  = $false
$firmwarePkSubject      = 'Unknown'

foreach ($k in $dbThumbprints2023.Keys) { $firmwareDbResults[$k] = $false }


# Track whether the 2011 predecessor certs were present.
# Microsoft only installs the 2023 replacements if the 2011 predecessor was
# already enrolled -- if absent, the 2023 replacement being missing is expected.
$firmware2011UefiCaPresent = $false
if (-not $SkipFirmwareScan -and $uefiScriptAvailable) {
    Write-Step 'Firmware Certificate Scan  (Get-UEFICertificate)'

    try {
        $ueficerts = & Get-UEFICertificate.ps1 -ErrorAction Stop
        $firmwareScanDone = $true

        Write-SectionLine
        Write-Host '    TYPE       STATUS      SUBJECT                                      EXPIRES' -ForegroundColor DarkGray
        Write-SectionLine

        foreach ($cert in $ueficerts) {
            $expired      = ($cert.Expires -lt (Get-Date))
            $expiringSoon = ($cert.Expires -lt (Get-Date).AddMonths(6) -and -not $expired)

            # Match 2023 certs by subject name (CN) -- thumbprints vary across OEM
            # cert packages so subject name is the reliable primary identifier
            $certCN = if ($cert.Subject -match 'CN=([^,]+)') { $Matches[1].Trim() } else { $cert.Subject }

            $is2023kek = ($cert.Type -eq 'KEK' -and $certCN -eq $kekSubject2023)
            $is2023db  = ($cert.Type -eq 'DB'  -and $dbSubjects2023.Keys -contains $certCN)

            # Fallback: also match by thumbprint in case subject CN format differs
            if (-not $is2023kek -and $cert.Type -eq 'KEK' -and $cert.Thumbprint -eq $kekThumbprint2023) {
                $is2023kek = $true
            }
            if (-not $is2023db -and $cert.Type -eq 'DB' -and $dbThumbprints2023.Values -contains $cert.Thumbprint) {
                $is2023db = $true
            }

            $isExpiring2011 = $expiring2011.ContainsKey($cert.Thumbprint)

            # Track state
            if ($cert.Type -eq 'PK') { $firmwarePkSubject = $cert.Subject }
            if ($is2023kek)           { $firmwareKek2023Present = $true }
            if ($is2023db) {
                # Find which named cert this matches -- try subject first, then thumbprint
                $certName = $dbSubjects2023.Keys | Where-Object { $_ -eq $certCN }
                if (-not $certName) {
                    $certName = $dbThumbprints2023.Keys | Where-Object { $dbThumbprints2023[$_] -eq $cert.Thumbprint }
                }
                if ($certName) { $firmwareDbResults[$certName] = $true }
            }
            if ($isExpiring2011)      { $firmwareExpiringFound += $expiring2011[$cert.Thumbprint] }
            if ($cert.Type -eq 'KEK' -and $expired -and -not $is2023kek) { $firmwareOemKekExpired = $true }
            # Track presence of 2011 UEFI CA -- its absence means the 2023 replacements are not expected
            if ($cert.Type -eq 'DB' -and $cert.Thumbprint -eq '46DEF63B5CE61CF8BA0DE2E6639C1019D0ED14F3') {
                $firmware2011UefiCaPresent = $true
            }

            # Display row
            $tag = if ($is2023kek -or $is2023db) { '[2023-OK] ' }
                   elseif ($expired)              { '[EXPIRED] ' }
                   elseif ($expiringSoon -or $isExpiring2011) { '[EXPIRING]' }
                   else                           { '[OK]      ' }

            $color = if ($is2023kek -or $is2023db) { 'Green' }
                     elseif ($expired)              { 'Red' }
                     elseif ($expiringSoon -or $isExpiring2011) { 'Yellow' }
                     else                           { 'Gray' }

            $subjectShort = if ($cert.Subject.Length -gt 44) { $cert.Subject.Substring(0,41) + '...' } else { $cert.Subject.PadRight(44) }
            $expStr = $cert.Expires.ToString('yyyy-MM-dd')
            Write-Host ("    {0,-4}  {1}  {2}  {3}" -f $cert.Type, $tag, $subjectShort, $expStr) -ForegroundColor $color

            Write-Log "UEFI $($cert.Type): $($cert.Subject) | Expires $($cert.Expires.ToString('yyyy-MM-dd')) | Thumb $($cert.Thumbprint)"
        }

        # Flag missing 2023 DB certs -- but only flag the two UEFI CA replacements as
        # MISSING if the 2011 predecessor was actually present.  If UEFI CA 2011 was
        # never enrolled, Windows intentionally skips installing its replacements.
        $optionalIfNo2011 = @('Microsoft UEFI CA 2023', 'Microsoft Option ROM UEFI CA 2023')
        $expectedDbCount  = $dbThumbprints2023.Count
        foreach ($certName in $dbThumbprints2023.Keys) {
            if (-not $firmwareDbResults[$certName]) {
                if ($certName -in $optionalIfNo2011 -and -not $firmware2011UefiCaPresent) {
                    # Expected absence -- 2011 predecessor was never enrolled on this device
                    Write-Host ("    DB    [N/A]       $certName  (not installed -- only needed if Microsoft UEFI CA 2011 was enrolled on this device)") -ForegroundColor DarkGray
                    Write-Log "UEFI DB N/A: $certName -- UEFI CA 2011 not present, replacement not expected"
                    $expectedDbCount--
                }
                else {
                    Write-Host ("    DB    [MISSING]   $certName") -ForegroundColor Red
                    Write-Log "UEFI DB MISSING: $certName"
                }
            }
        }
        if (-not $firmwareKek2023Present) {
            Write-Host '    KEK   [MISSING]   Microsoft Corporation KEK 2K CA 2023' -ForegroundColor Red
            Write-Log 'UEFI KEK MISSING: Microsoft Corporation KEK 2K CA 2023'
        }

        Write-SectionLine
        $dbCount = ($firmwareDbResults.Values | Where-Object { $_ }).Count
        Write-Info "PK Subject : $firmwarePkSubject"
        Write-Info "KEK 2023   : $(if ($firmwareKek2023Present) { 'PRESENT' } else { 'MISSING' })"
        if ($firmware2011UefiCaPresent) {
            Write-Info "DB 2023    : $dbCount of $($dbThumbprints2023.Count) certs present"
        }
        else {
            Write-Info "DB 2023    : $dbCount of $expectedDbCount applicable certs present  (2 optional certs skipped -- this device never had Microsoft UEFI CA 2011 enrolled, so Windows does not install its replacements)"
        }
        # Only surface expired OEM KEK warning when not already fully updated -- on a confirmed-updated device it is noise, not actionable.
        if ($firmwareOemKekExpired -and -not $firmwareKek2023Present) {
            Write-Warn 'One or more OEM KEK entries have already expired.  This may cause Firmware_Unknown errors.'
        }
    }
    catch {
        Write-Warn "Firmware scan failed: $($_.Exception.Message)"
        Write-Info 'Continuing with registry data only.'
        Write-Log  "WARN: Firmware scan error -- $($_.Exception.Message)"
    }
}
elseif ($SkipFirmwareScan) {
    Write-Step 'Firmware Certificate Scan'
    Write-Info 'Skipped by parameter.'
}
else {
    Write-Step 'Firmware Certificate Scan'
    Write-Info 'Get-UEFICertificate not available.  Skipping firmware scan.'
}

# ── Step 5: Servicing registry ────────────────────────────────────────────────
Write-Step 'Windows Servicing Registry'

$servicing = $null
try {
    $servicing = Get-ItemProperty -Path $servicingPath -ErrorAction Stop
}
catch {
    Write-Warn 'Servicing registry key not found.'
    Write-Info 'The required cumulative update may not be installed yet.'
    Write-Info 'Install all pending Windows Updates and re-run this script.'
    Write-Log  'RESULT: Servicing key missing -- CU needed'

    Write-StatusFile @{
        ComputerName = $env:COMPUTERNAME
        Model        = $model
        ServiceTag   = $serviceTag
        BiosVersion  = $biosVersion
        LastRun      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Phase        = 'NoCU'
        LastOutcome  = 'SERVICING_KEY_MISSING'
        ActionsTaken = @('None -- servicing key absent')
        RebootCount  = if ($priorStatus.RebootCount) { $priorStatus.RebootCount } else { 0 }
        FlaggedForReplacement = $false
    }
    exit 0
}

$uefiStatus      = $servicing.UEFICA2023Status
$uefiError       = $servicing.UEFICA2023Error
$capable         = $servicing.WindowsUEFICA2023Capable
$kekErrorReason  = $servicing.KEKLastUpdateErrorReason
$confidenceLevel = $servicing.ConfidenceLevel
$availableUpdates = (Get-ItemProperty -Path $sbPath -ErrorAction SilentlyContinue).AvailableUpdates

Write-SectionLine
Write-Detail ("  {'UEFICA2023Status',-28}: $uefiStatus")
Write-Detail ("  {'WindowsUEFICA2023Capable',-28}: $capable  $(if ($capable -eq 2) { '(update applied)' } elseif ($capable -eq 1) { '(capable, not yet high-confidence)' } else { '' })")
Write-Detail ("  {'ConfidenceLevel',-28}: $confidenceLevel")
Write-Detail ("  {'AvailableUpdates',-28}: $(if ($null -ne $availableUpdates) { '0x{0:X4}' -f $availableUpdates } else { 'not set' })")
if ($uefiError)      { Write-Detail ("  {'UEFICA2023Error',-28}: $uefiError") }
if ($kekErrorReason) { Write-Detail ("  {'KEKLastUpdateErrorReason',-28}: $kekErrorReason") }
Write-SectionLine

Write-Log "Registry: Status=$uefiStatus, Capable=$capable, AvailableUpdates=$(if ($null -ne $availableUpdates) { '0x{0:X4}' -f $availableUpdates } else { 'null' }), KEKErrorReason=$kekErrorReason"

# ── Step 6: Event log check ───────────────────────────────────────────────────
Write-Step 'System Event Log  (Secure Boot Events)'

$relevantEventIds = @(1795, 1796, 1800, 1803, 1808)
$sbEvents = @()
try {
    $sbEvents = Get-WinEvent -LogName System -ErrorAction Stop |
        Where-Object { $_.Id -in $relevantEventIds } |
        Select-Object -First 20
}
catch {
    Write-Info 'Could not read event log, or no matching events found.'
}

$event1803Count = 0

if ($sbEvents.Count -gt 0) {
    Write-SectionLine
    Write-Host '    EVENT ID   TIME                   MESSAGE SUMMARY' -ForegroundColor DarkGray
    Write-SectionLine

    $eventMeanings = @{
        1795 = 'Error when handing off certs to firmware'
        1796 = 'Error during Secure Boot cert update'
        1800 = 'Reboot required to apply update'
        1803 = 'KEK update could not be applied  (hardware/firmware block)'
        1808 = 'Secure Boot cert update completed successfully'
    }

    foreach ($ev in ($sbEvents | Sort-Object TimeCreated -Descending | Select-Object -First 10)) {
        $meaning = $eventMeanings[$ev.Id]
        $color   = switch ($ev.Id) {
            1808    { 'Green' }
            1800    { 'Yellow' }
            1795    { 'Red' }
            1796    { 'Red' }
            1803    { 'Magenta' }
            default { 'Gray' }
        }
        if ($ev.Id -eq 1803) { $event1803Count++ }
        Write-Host ("    {0,-10} {1}   {2}" -f $ev.Id, $ev.TimeCreated.ToString('yyyy-MM-dd HH:mm'), $meaning) -ForegroundColor $color
        Write-Log "Event $($ev.Id) at $($ev.TimeCreated): $meaning"
    }
    Write-SectionLine
}
else {
    Write-Info 'No Secure Boot events found in System log.'
}

# ── Step 7: Determine compatibility and outcome ──────────────────────────────
Write-Step 'Compatibility Assessment'

# Determine if hardware is flagged as incompatible
$hardwareIncompatible = $false
$incompatibleReason   = ''
$incompatibleContext  = ''

# Signal 1: KEKLastUpdateErrorReason from registry
if ($kekErrorReason -eq 'Firmware_MissingKEKInPackage') {
    $hardwareIncompatible = $true
    $incompatibleReason   = 'Firmware_MissingKEKInPackage'
    $incompatibleContext  = "The OEM PK is not present in Microsoft's KEKUpdateCombined.bin.  No signed KEK update package exists for this firmware."
}
elseif ($kekErrorReason -eq 'Firmware_Unknown') {
    $hardwareIncompatible = $true
    $incompatibleReason   = 'Firmware_Unknown'
    $incompatibleContext  = 'Windows cannot classify KEK compatibility for this firmware.'
    if ($firmwareOemKekExpired) {
        $incompatibleContext += '  An expired OEM KEK entry in firmware is likely causing this classification.'
    }
}

# Signal 2: AvailableUpdates KEK bit (0x0004) stuck after multiple reboots
$priorRebootCount = if ($priorStatus.RebootCount) { [int]$priorStatus.RebootCount } else { 0 }
$kekBitStuck = ($null -ne $availableUpdates) -and (($availableUpdates -band 0x0004) -ne 0) -and ($priorRebootCount -ge 2)
if ($kekBitStuck -and -not $hardwareIncompatible) {
    $hardwareIncompatible = $true
    $incompatibleReason   = 'KEK_BIT_STUCK'
    $incompatibleContext  = "AvailableUpdates bit 0x0004 (KEK) has not cleared after $priorRebootCount reboots.  This matches the hardware-incompatible pattern described in the Microsoft Secure Boot troubleshooting guide."
}

# Signal 3: Event 1803 repeated (corroborates hardware block)
if ($event1803Count -gt 0 -and -not $hardwareIncompatible) {
    Write-Warn "Event ID 1803 detected ($event1803Count times).  KEK update is being blocked at the firmware level."
    Write-Info 'This is a strong indicator of a hardware compatibility issue.  Check for a BIOS update.'
}

# Check Dell out-of-scope via dynamic lookup (only if Dell and not already done above)
$dellCompat   = $null
$isOutOfScope = $false
if ($isDell) {
    # Re-use cached pages if BIOS check already ran, otherwise fetch now
    if (-not $SkipBiosCheck) {
        # Already ran during BIOS check -- re-run is cheap since pages are cached
        $dellCompat = Get-DellCompatibility -DeviceModel $model
    }
    else {
        Write-Info 'Running Dell compatibility lookup (BIOS check was skipped)...'
        $dellCompat = Get-DellCompatibility -DeviceModel $model
    }

    if ($null -ne $dellCompat -and $dellCompat.LookupWorked) {
        $isOutOfScope = $dellCompat.IsOutOfScope
        if ($isOutOfScope) {
            Write-Warn "'$model' is on Dell's out-of-scope list (KB 000378734) -- no BIOS update planned with 2023 certs."
        }
        elseif ($dellCompat.IsSupported) {
            Write-Pass "'$model' confirmed on Dell's supported list (KB 000347876)."
        }
        else {
            Write-Info "'$model' not found on either Dell list -- may be newer hardware."
        }
    }
    else {
        Write-Warn "Could not reach Dell KB pages.  Manual check recommended: $dellKbOutOfScope"
    }
}

# Determine if fully updated already
# When UEFI CA 2011 was never enrolled, the two replacement certs are not expected.
# Adjust the required count accordingly before evaluating allDbPresent.
$requiredDbCount = $dbThumbprints2023.Count
if (-not $firmware2011UefiCaPresent) { $requiredDbCount -= 2 }
$actualDbCount  = ($firmwareDbResults.Values | Where-Object { $_ }).Count
$allDbPresent   = $firmwareScanDone -and ($actualDbCount -ge $requiredDbCount)
$fullyUpdated   = ($uefiStatus -eq 'Updated') -or ($firmwareScanDone -and $firmwareKek2023Present -and $allDbPresent)

# ── Determine action ──────────────────────────────────────────────────────────
$actionsTaken          = @()
$flagForReplacement    = $false
$verdictCode           = ''
$verdictMessage        = ''
$verdictColor          = 'Green'

# ── OUTCOME A: Fully up to date ───────────────────────────────────────────────
if ($fullyUpdated -and -not $hardwareIncompatible) {
    $verdictCode    = 'FULLY_UP_TO_DATE'
    $verdictMessage = 'FULLY UP TO DATE -- No action needed.'
    $verdictColor   = 'Green'
    Write-Pass 'All 2023 Secure Boot certificates are present and current.'
    Write-Log  'OUTCOME: FULLY_UP_TO_DATE'
}

# ── OUTCOME D/E: Hardware incompatible ───────────────────────────────────────
elseif ($hardwareIncompatible) {
    $verdictCode    = 'HARDWARE_INCOMPATIBLE'
    $verdictMessage = 'HARDWARE INCOMPATIBLE -- Document and flag for replacement.'
    $verdictColor   = 'Red'
    $flagForReplacement = $true

    Write-Host ''
    Write-Host '  ================================================================' -ForegroundColor Red
    Write-Host '   HARDWARE INCOMPATIBLE -- KEK UPDATE CANNOT BE APPLIED'         -ForegroundColor Red
    Write-Host '  ================================================================' -ForegroundColor Red
    Write-Fatal "  Device       : $env:COMPUTERNAME"
    Write-Fatal "  Model        : $manufacturer $model"
    Write-Fatal "  Service Tag  : $serviceTag"
    Write-Fatal "  BIOS         : $biosVersion  ($biosDate)"
    Write-Fatal "  Error Reason : $incompatibleReason"
    if ($incompatibleContext) { Write-Fatal "  Context      : $incompatibleContext" }
    Write-Host ''
    Write-Fatal '  WHAT THIS MEANS:'
    Write-Fatal '    The Microsoft Corporation KEK 2K CA 2023 certificate cannot be'
    Write-Fatal '    enrolled on this device by any software means.  Windows Update,'
    Write-Fatal '    Set-SecureBootUEFI, and registry triggers all fail at the'
    Write-Fatal '    firmware level (STATUS_EFI_SECURITY_VIOLATION, 0xC0000454).'
    Write-Fatal '    The device will permanently show KEK as "Not up to date" in Intune.'
    Write-Host ''
    Write-Fatal '  RECOMMENDED ACTION:'
    Write-Fatal '    1. Confirm no newer BIOS is available from the OEM.'
    Write-Fatal '    2. Document as a known hardware limitation.'
    Write-Fatal '    3. Exclude from Intune compliance policies checking KEK status.'
    Write-Fatal '    4. Flag for hardware refresh at next refresh cycle.'
    if ($isDell) {
        Write-Fatal "    5. Reference: https://www.dell.com/support/kbdoc/en-us/000378734"
    }
    Write-Host '  ================================================================' -ForegroundColor Magenta

    Write-Log "OUTCOME: HARDWARE_INCOMPATIBLE -- $incompatibleReason"

    # Still offer BIOS update if available -- it may change compatibility on next run
    if ($biosUpdateAvailable) {
        Write-Host ''
        Write-Warn 'A BIOS update is available.  Updating may resolve compatibility on the next run.'
        if (Prompt-YesNo -Question 'Update BIOS now?' -Default 'N') {
            Write-Host ''
            Write-Warn 'IMPORTANT: After selecting Yes:'
            Write-Info '  - BitLocker will be suspended automatically for one reboot cycle.'
            Write-Info '  - The BIOS update will stage now and apply on the next reboot.'
            Write-Info '  - After reboot, the screen may be black for 1-3 minutes during the flash.  This is normal.'
            Write-Info '  - After reboot, re-run this script to reassess compatibility.'
            Write-Host ''

            if (Prompt-YesNo -Question 'Confirm BIOS update?' -Default 'N') {
                try {
                    Update-MyDellBIOS -ErrorAction Stop
                    $actionsTaken += "BIOS update staged ($latestBiosVersion)"
                    Write-Pass 'BIOS update staged successfully.'
                    Write-Log  "BIOS update staged: $latestBiosVersion"
                    Invoke-RebootPrompt -Reason 'BIOS update staged -- reboot to apply'
                }
                catch {
                    Write-Fail "BIOS update failed: $($_.Exception.Message)"
                    Write-Log  "ERROR: BIOS update failed -- $($_.Exception.Message)"
                }
            }
        }
    }
}

# ── OUTCOME B: BIOS update available, may resolve KEK ───────────────────────
elseif ($biosUpdateAvailable -and -not $fullyUpdated) {
    $verdictCode    = 'BIOS_UPDATE_AVAILABLE'
    $verdictMessage = 'BIOS UPDATE AVAILABLE -- Update BIOS first, then reboot and re-run.'
    $verdictColor   = 'Yellow'

    Write-Warn "BIOS update available: $biosVersion -> $latestBiosVersion"
    Write-Info 'Updating the BIOS may resolve Secure Boot certificate issues.'
    Write-Info 'After the BIOS update and reboot, re-run this script to check cert status.'
    Write-Host ''
    Write-Warn 'IMPORTANT notes about BIOS update:'
    Write-Info '  - BitLocker will be suspended automatically for one reboot cycle.'
    Write-Info '  - The update stages now and applies on the next reboot.'
    Write-Info '  - The screen may be black for 1-3 minutes after reboot during the flash.  This is normal.'
    Write-Info '  - Do NOT power off the device during this time.'

    if (Prompt-YesNo -Question 'Update BIOS now?' -Default 'N') {
        if (Prompt-YesNo -Question 'Confirm -- understood the above warnings?' -Default 'N') {
            try {
                Update-MyDellBIOS -ErrorAction Stop
                $actionsTaken += "BIOS update staged ($latestBiosVersion)"
                Write-Pass 'BIOS update staged successfully.'
                Write-Log  "BIOS update staged: $latestBiosVersion"
                $verdictCode    = 'BIOS_UPDATE_STAGED'
                $verdictMessage = 'BIOS UPDATE STAGED -- Reboot required, then re-run this script.'
                Invoke-RebootPrompt -Reason 'BIOS update staged -- reboot to apply firmware flash'
            }
            catch {
                Write-Fail "BIOS update failed: $($_.Exception.Message)"
                Write-Log  "ERROR: BIOS update failed -- $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Info 'BIOS update skipped.  Re-run this script after manually updating the BIOS.'
    }
    Write-Log "OUTCOME: $verdictCode"
}

# ── OUTCOME C: Certs missing, needs remediation ──────────────────────────────
elseif (-not $fullyUpdated -and -not $hardwareIncompatible) {

    # Check if InProgress and already had a prior run
    $alreadyInProgress = ($uefiStatus -eq 'InProgress') -and ($null -ne $priorStatus)

    if ($alreadyInProgress) {
        Write-Warn "Status is InProgress and a prior run was recorded ($priorRebootCount reboot(s) since remediation)."
        if ($priorRebootCount -ge 2) {
            Write-Warn 'This device has been through 2+ reboots and is still InProgress.'
            Write-Info 'This may indicate the device needs more time, or there is a deeper compatibility issue.'
            Write-Info 'If it remains InProgress after one more reboot, escalate to supervisor for replacement review.'
        }
        else {
            Write-Info 'This is normal -- some devices require 2-3 reboots to complete cert deployment.'
            Write-Info 'Reboot the device, then re-run this script.'
        }
    }

    if ($uefiStatus -eq 'InProgress' -and $null -eq $priorStatus) {
        # First time seeing InProgress -- deployment may already be in progress from Windows Update
        Write-Info 'Status is InProgress.  Deployment may have been triggered by Windows Update.'
        Write-Info 'Reboot the device, then re-run this script to check if it completes.'
        $verdictCode    = 'REBOOT_PENDING'
        $verdictMessage = 'REBOOT PENDING -- Reboot now, then re-run this script.'
        $verdictColor   = 'Yellow'
        Invoke-RebootPrompt -Reason 'Secure Boot cert update in progress'
    }
    else {
        # Needs remediation trigger
        $needsRemediation = $true

        if ($uefiStatus -eq 'InProgress') {
            Write-Info 'Re-triggering deployment to ensure all registry flags are set correctly...'
        }
        else {
            Write-Info "Current status: $uefiStatus.  Remediation trigger needed."
        }

        if (Prompt-YesNo -Question 'Apply Secure Boot cert remediation now?' -Default 'Y') {
            Write-Host ''

            try {
                if (-not (Test-Path $sbPath)) { New-Item -Path $sbPath -Force | Out-Null }

                Set-ItemProperty -Path $sbPath -Name 'AvailableUpdates'            -Value 0x5944 -Type DWord -Force
                Set-ItemProperty -Path $sbPath -Name 'MicrosoftUpdateManagedOptIn' -Value 1      -Type DWord -Force
                Set-ItemProperty -Path $sbPath -Name 'HighConfidenceOptOut'        -Value 0      -Type DWord -Force

                $actionsTaken += 'Registry keys set (AvailableUpdates=0x5944)'
                Write-Pass 'Registry keys set: AvailableUpdates=0x5944, MicrosoftUpdateManagedOptIn=1, HighConfidenceOptOut=0'
                Write-Log  'Registry keys written'

                if ($taskExists) {
                    Start-ScheduledTask -TaskName 'Secure-Boot-Update' -TaskPath '\Microsoft\Windows\PI\' -ErrorAction SilentlyContinue
                    $actionsTaken += 'Scheduled task triggered'
                    Write-Pass 'Triggered scheduled task: \Microsoft\Windows\PI\Secure-Boot-Update'
                    Write-Log  'Scheduled task triggered'
                }
                else {
                    Write-Warn 'Scheduled task not found.  Registry keys set.  Task will run automatically within ~12 hours.'
                    Write-Log  'WARN: Scheduled task not available -- registry-only trigger'
                }

                $verdictCode    = 'REMEDIATION_APPLIED'
                $verdictMessage = 'REMEDIATION APPLIED -- Reboot required, then re-run this script.'
                $verdictColor   = 'Yellow'

                Write-Log "OUTCOME: REMEDIATION_APPLIED"
                Invoke-RebootPrompt -Reason 'Secure Boot cert remediation applied'
            }
            catch {
                Write-Fail "Remediation failed: $($_.Exception.Message)"
                Write-Log  "ERROR: Remediation failed -- $($_.Exception.Message)"
                $verdictCode    = 'REMEDIATION_FAILED'
                $verdictMessage = 'REMEDIATION FAILED -- Check log for details.'
                $verdictColor   = 'Red'
            }
        }
        else {
            Write-Info 'Remediation skipped by operator.'
            $verdictCode    = 'REMEDIATION_SKIPPED'
            $verdictMessage = 'REMEDIATION SKIPPED -- Re-run when ready to remediate.'
            $verdictColor   = 'Yellow'
            Write-Log 'OUTCOME: REMEDIATION_SKIPPED'
        }
    }
}

# ── Step 8: Write status file ─────────────────────────────────────────────────
$newRebootCount = $priorRebootCount
# Increment reboot count if we just triggered a reboot or if InProgress with prior run
if ($actionsTaken -match 'staged|triggered|applied' -or $alreadyInProgress) {
    $newRebootCount++
}

Write-StatusFile @{
    ComputerName          = $env:COMPUTERNAME
    Manufacturer          = $manufacturer
    Model                 = $model
    ServiceTag            = $serviceTag
    BiosVersion           = $biosVersion
    BiosDate              = $biosDate
    LatestBiosAvailable   = if ($latestBiosVersion) { $latestBiosVersion } else { 'Not checked' }
    WindowsVersion        = "$winVersion (Build $winBuild.$winUbr)"
    LastRun               = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Phase                 = $verdictCode
    LastOutcome           = $verdictCode
    ActionsTaken          = if ($actionsTaken.Count -gt 0) { $actionsTaken } else { @('None') }
    RebootCount           = $newRebootCount
    FlaggedForReplacement = $flagForReplacement
    FirmwareScanDone      = $firmwareScanDone
    KekCa2023Present      = $firmwareKek2023Present
    DbCa2023Count         = ($firmwareDbResults.Values | Where-Object { $_ }).Count
    KEKErrorReason        = $kekErrorReason
    RegistryStatus        = $uefiStatus
    DellCompatibility     = if ($null -ne $dellCompat -and $dellCompat.LookupWorked) {
                                if ($isOutOfScope)              { 'OUT_OF_SCOPE' }
                                elseif ($dellCompat.IsSupported){ 'SUPPORTED' }
                                else                            { 'NOT_FOUND' }
                            } else { 'LOOKUP_FAILED' }
    Event1803Count        = $event1803Count
}

Write-Log "Status file written: Phase=$verdictCode, RebootCount=$newRebootCount, FlaggedForReplacement=$flagForReplacement"

# ── Step 9: Verdict box ───────────────────────────────────────────────────────
Write-Host ''
Write-Host '  ================================================================' -ForegroundColor $verdictColor
Write-Host '   VERDICT' -ForegroundColor $verdictColor
Write-Host '  ================================================================' -ForegroundColor $verdictColor
Write-Host "   $verdictMessage" -ForegroundColor $verdictColor
Write-Host ''

switch ($verdictCode) {
    'FULLY_UP_TO_DATE' {
        Write-Host '   Next step: No action needed.  Device is fully updated.' -ForegroundColor Green
    }
    'BIOS_UPDATE_STAGED' {
        Write-Host '   Next step: Reboot complete.  Re-run this script to check cert status.' -ForegroundColor Yellow
    }
    'BIOS_UPDATE_AVAILABLE' {
        Write-Host '   Next step: Update BIOS, reboot, then re-run this script.' -ForegroundColor Yellow
    }
    'REMEDIATION_APPLIED' {
        Write-Host '   Next step: Reboot complete.  Re-run this script to confirm status.' -ForegroundColor Yellow
    }
    'REBOOT_PENDING' {
        Write-Host '   Next step: Reboot complete.  Re-run this script to confirm status.' -ForegroundColor Yellow
    }
    'HARDWARE_INCOMPATIBLE' {
        Write-Host '   Next step: Document this device as a hardware limitation exception.' -ForegroundColor Red
        Write-Host '              Exclude from Intune KEK compliance policies and flag for refresh.' -ForegroundColor Red
    }
    'REMEDIATION_FAILED' {
        Write-Host '   Next step: Escalate to supervisor.  Check log for error details.' -ForegroundColor Red
    }
    default {
        Write-Host '   Next step: Re-run this script or escalate to supervisor.' -ForegroundColor Yellow
    }
}

Write-Host '  ================================================================' -ForegroundColor $verdictColor
Write-Host ''
Write-Host "  Status file : $StatusFilePath" -ForegroundColor DarkGray
Write-Host "  Log file    : $(Join-Path (Split-Path $StatusFilePath) 'check.log')" -ForegroundColor DarkGray
Write-Host ''

<#
VALIDATION STEPS
----------------
1.  Fully updated device (UEFICA2023Status=Updated, all 2023 certs in firmware)
      --> PASS verdict, no prompts, status file written with FULLY_UP_TO_DATE

2.  NUC8 or device with Firmware_MissingKEKInPackage
      --> HARDWARE_INCOMPATIBLE block, flag for replacement, BIOS update offered if available

3.  Dell 3050 Micro with Firmware_Unknown + expired OEM KEK
      --> HARDWARE_INCOMPATIBLE block, expired KEK context shown

4.  AvailableUpdates 0x0004 stuck after 2+ reboots (priorStatus.RebootCount >= 2)
      --> HARDWARE_INCOMPATIBLE block with KEK_BIT_STUCK reason

5.  Device needing first-time remediation
      --> Prompt to remediate, registry keys set, task triggered, reboot prompt

6.  InProgress on first run (no prior status file)
      --> REBOOT_PENDING, reboot prompt

7.  InProgress with prior run (1 reboot)
      --> Warn still in progress, normal for 1 reboot, advise another reboot

8.  InProgress with prior run (2+ reboots)
      --> Stronger warning, escalate if persists after one more reboot

9.  Newer BIOS available, certs missing, non-incompatible device
      --> BIOS_UPDATE_AVAILABLE, offer to update via Update-MyDellBIOS

10. Servicing registry key missing (no CU installed)
      --> Exit with NoCU message, status file written

11. -SkipFirmwareScan -SkipBiosCheck flags
      --> Firmware scan and BIOS check sections skipped gracefully

12. Non-Dell device
      --> OSD/BIOS section skipped, all other steps proceed normally

13. Run a second time on a device with a status file
      --> Prior run history displayed at top before new assessment
#>