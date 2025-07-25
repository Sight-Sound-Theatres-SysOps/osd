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

# Function to set registry value
function Set-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [string]$Description
    )
    
    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
        Write-Host "✓ Set $Description = $Value" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Failed to set $Description" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
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

if (New-RegistryKeyIfNotExists -Path $passportPath) {
    Set-RegistryValueSafe -Path $passportPath -Name "Enabled" -Value 1 -Description "PassportForWork Enabled"
}

Write-Host ""

# Configuration 2: AllowDomainPINLogon
Write-Host "2. Configuring Allow Domain PIN Logon..." -ForegroundColor Yellow
$systemPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"

if (New-RegistryKeyIfNotExists -Path $systemPath) {
    Set-RegistryValueSafe -Path $systemPath -Name "AllowDomainPINLogon" -Value 1 -Description "AllowDomainPINLogon"
}

Write-Host ""

# Verify the configuration
Write-Host "Verifying Configuration..." -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan
Write-Host ""

$verification1 = Test-RegistryValue -Path $passportPath -Name "Enabled" -ExpectedValue 1 -Description "PassportForWork Enabled"
$verification2 = Test-RegistryValue -Path $systemPath -Name "AllowDomainPINLogon" -ExpectedValue 1 -Description "AllowDomainPINLogon"

Write-Host ""

# Summary
if ($verification1 -and $verification2) {
    Write-Host "SUCCESS: Windows Hello for local accounts has been enabled!" -ForegroundColor Green
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
        
        # Give user a chance to cancel
        try {
            Start-Sleep -Seconds 10
            Write-Host "Restarting now..." -ForegroundColor Red
            Restart-Computer -Force
        }
        catch {
            Write-Host "Restart cancelled by user." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Restart skipped. Please restart manually when convenient." -ForegroundColor Yellow
    }
}
else {
    Write-Host "WARNING: Some settings may not have been applied correctly!" -ForegroundColor Red
    Write-Host "Please check the errors above and try running the script again." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Script completed." -ForegroundColor Cyan
