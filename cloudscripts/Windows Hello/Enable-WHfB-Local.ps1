# Enable Windows Hello for Local Accounts - PowerShell 5.1 and 7 Compatible
# Must be run as Administrator

# Check PowerShell version for compatibility
$psVersion = $PSVersionTable.PSVersion.Major
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# Check if running as administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal] $currentUser).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "Running as Administrator - OK" -ForegroundColor Green
Write-Host ""

# Function to create registry key if it doesn't exist
function New-RegistryKeyIfNotExists {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        try {
            New-Item -Path $Path -Force | Out-Null
            Write-Host "Created registry path: $Path" -ForegroundColor Yellow
            return $true
        }
        catch {
            Write-Host "ERROR: Failed to create registry path: $Path" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "Registry path already exists: $Path" -ForegroundColor Green
        return $true
    }
}


# Function to check and set registry value only if needed
function Ensure-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [string]$Description
    )
    $changed = $false
    try {
        $currentValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($currentValue -eq $Value) {
            Write-Host "✓ $Description is already set to $Value" -ForegroundColor Green
        } else {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
            Write-Host "✓ Set $Description = $Value" -ForegroundColor Yellow
            $changed = $true
        }
    } catch {
        # Value does not exist, so set it
        try {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
            Write-Host "✓ Set $Description = $Value" -ForegroundColor Yellow
            $changed = $true
        } catch {
            Write-Host "✗ Failed to set $Description" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    return $changed
}

# Function to verify registry value
function Test-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$ExpectedValue,
        [string]$Description
    )
    
    try {
        $currentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        if ($currentValue.$Name -eq $ExpectedValue) {
            Write-Host "✓ $Description is correctly set to $ExpectedValue" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ $Description is set to $($currentValue.$Name), expected $ExpectedValue" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ $Description is not set" -ForegroundColor Red
        return $false
    }
}

Write-Host "Configuring Windows Hello for Local Accounts..." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""


# Configuration 1: PassportForWork
Write-Host "1. Configuring Windows Hello for Business..." -ForegroundColor Yellow
$passportPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
$changed1 = $false
if (New-RegistryKeyIfNotExists -Path $passportPath) {
    $changed1 = Ensure-RegistryValue -Path $passportPath -Name "Enabled" -Value 1 -Description "PassportForWork Enabled"
}

Write-Host ""

# Configuration 2: AllowDomainPINLogon
Write-Host "2. Configuring Allow Domain PIN Logon..." -ForegroundColor Yellow
$systemPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
$changed2 = $false
if (New-RegistryKeyIfNotExists -Path $systemPath) {
    $changed2 = Ensure-RegistryValue -Path $systemPath -Name "AllowDomainPINLogon" -Value 1 -Description "AllowDomainPINLogon"
}

Write-Host ""


# Only prompt for restart if any value was changed
if ($changed1 -or $changed2) {
    Write-Host "SUCCESS: Windows Hello for local accounts has been enabled or updated!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Restart the computer for changes to take full effect" -ForegroundColor White
    Write-Host "2. Log in to your local administrator account" -ForegroundColor White
    Write-Host "3. Go to Settings > Accounts > Sign-in options" -ForegroundColor White
    Write-Host "4. Set up Windows Hello PIN and biometrics" -ForegroundColor White
    Write-Host ""
    # Prompt user for restart
    Write-Host "Would you like to restart the computer now? (Recommended)" -ForegroundColor Yellow
    Write-Host "Type 'Y' or 'Yes' to restart now, any other key to skip:" -ForegroundColor White
    $restartChoice = Read-Host
    if ($restartChoice -match '^(Y|Yes|y|yes)$') {
        Write-Host ""
        Write-Host "Restarting computer in 10 seconds..." -ForegroundColor Red
        Write-Host "Press Ctrl+C to cancel" -ForegroundColor Yellow
        try {
            Start-Sleep -Seconds 10
            Write-Host "Restarting now..." -ForegroundColor Red
            Restart-Computer -Force
        } catch {
            Write-Host "Restart cancelled by user." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Restart skipped. Please restart manually when convenient." -ForegroundColor Yellow
    }
} else {
    Write-Host "No changes were necessary. All Windows Hello settings were already correctly configured." -ForegroundColor Green
}

Write-Host ""
Write-Host "Script completed." -ForegroundColor Cyan
