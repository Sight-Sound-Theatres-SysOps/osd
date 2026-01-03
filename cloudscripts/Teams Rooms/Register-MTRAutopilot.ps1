#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers a Teams Room device with Windows Autopilot using encrypted app credentials.

.DESCRIPTION
    This script prompts for device details, decrypts stored Azure AD app credentials,
    and registers the device with Windows Autopilot for Teams Rooms deployment.

.NOTES
    Author: Matthew Miles
    Use Case: Teams Rooms on Windows - Autopilot Registration

.EXAMPLE
    .\Register-MTRAutopilot.ps1
    
    GroupTag Examples:
        MTR-BR-TheArk
        MTR-LA-TheCommission
        MTR-BR-BoardRoom1
#>

[CmdletBinding()]
param()

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

function Test-ComputerName {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    $errors = @()
    
    # Check length (max 15 characters)
    if ($Name.Length -gt 15) {
        $errors += "Computer name exceeds 15 characters (currently $($Name.Length))"
    }
    
    # Check for invalid characters (only a-z, A-Z, 0-9, and hyphens allowed)
    if ($Name -notmatch '^[a-zA-Z0-9-]+$') {
        $errors += "Computer name contains invalid characters. Only letters, numbers, and hyphens are allowed"
    }
    
    # Check if name is only numbers
    if ($Name -match '^\d+$') {
        $errors += "Computer name cannot contain only numbers"
    }
    
    # Check for spaces (caught by regex above, but explicit message)
    if ($Name -match '\s') {
        $errors += "Computer name cannot contain spaces"
    }
    
    # Check if starts or ends with hyphen
    if ($Name -match '^-|-$') {
        $errors += "Computer name cannot start or end with a hyphen"
    }
    
    # Check minimum length
    if ($Name.Length -lt 1) {
        $errors += "Computer name cannot be empty"
    }
    
    return $errors
}

function Test-GroupTag {
    param (
        [Parameter(Mandatory)]
        [string]$Tag
    )
    
    $errors = @()
    
    # Check for spaces
    if ($Tag -match '\s') {
        $errors += "Group tag cannot contain spaces"
    }
    
    # Check for problematic special characters that may cause Azure AD query issues
    if ($Tag -match '["\[\]{}|\\^`]') {
        $errors += "Group tag contains special characters that may cause issues with Azure AD dynamic groups"
    }
    
    # Recommended max length (no hard limit, but keep reasonable)
    if ($Tag.Length -gt 100) {
        $errors += "Group tag exceeds recommended maximum of 100 characters"
    }
    
    # Check minimum length
    if ($Tag.Length -lt 1) {
        $errors += "Group tag cannot be empty"
    }
    
    # Check for valid characters (letters, numbers, hyphens, underscores)
    if ($Tag -notmatch '^[a-zA-Z0-9_-]+$') {
        $errors += "Group tag should only contain letters, numbers, hyphens, and underscores"
    }
    
    return $errors
}

function Get-DecryptedCredentials {
    param (
        [Parameter(Mandatory)]
        [string]$Password
    )
    
    $blobUrl = "https://ssintunedata.blob.core.windows.net/autopilot/autopilot.json.enc"
    $tempFile = "$env:TEMP\autopilot.json.enc"
    
    try {
        Write-Host -ForegroundColor Yellow "[-] Downloading encrypted credentials..."
        Invoke-WebRequest -Uri $blobUrl -OutFile $tempFile -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor Red "[!] Failed to download credentials file: $_"
        return $null
    }

    try {
        Write-Host -ForegroundColor Yellow "[-] Decrypting credentials..."
        $encryptedBytesWithSaltAndIV = [System.IO.File]::ReadAllBytes($tempFile)
        $salt = $encryptedBytesWithSaltAndIV[0..15]
        $iv = $encryptedBytesWithSaltAndIV[16..31]
        $encryptedBytes = $encryptedBytesWithSaltAndIV[32..($encryptedBytesWithSaltAndIV.Length - 1)]

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

        $passphraseBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
        $keyDerivation = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passphraseBytes, $salt, 100000)
        $aes.Key = $keyDerivation.GetBytes(32)
        $aes.IV = $iv

        $decryptor = $aes.CreateDecryptor()
        $memoryStream = New-Object System.IO.MemoryStream
        $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($memoryStream, $decryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)

        $cryptoStream.Write($encryptedBytes, 0, $encryptedBytes.Length)
        $cryptoStream.FlushFinalBlock()

        $decryptedBytes = $memoryStream.ToArray()
        $decryptedText = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)

        $cryptoStream.Close()
        $memoryStream.Close()
        $aes.Dispose()
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

        $jsonContent = $decryptedText | ConvertFrom-Json
        Write-Host -ForegroundColor Green "[+] Credentials decrypted successfully"
        return $jsonContent
    }
    catch {
        Write-Host -ForegroundColor Red "[!] Failed to decrypt credentials. Check your password."
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        return $null
    }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "       Teams Rooms - Windows Autopilot Registration         " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  GroupTag Examples: MTR-BR-TheArk, MTR-LA-TheCommission" -ForegroundColor DarkGray
Write-Host "  Computer Name: Max 15 chars, letters/numbers/hyphens only" -ForegroundColor DarkGray
Write-Host ""

# ============================================================================
# Prompt for Group (with default)
# ============================================================================
$defaultGroup = "AutoPilot_Devices-TeamsRooms"
$Group = Read-Host "Enter Entra Group Name [$defaultGroup]"
if ([string]::IsNullOrWhiteSpace($Group)) {
    $Group = $defaultGroup
}

# ============================================================================
# Prompt for GroupTag (prefix with MTR-, validate)
# ============================================================================
$tagValid = $false
while (-not $tagValid) {
    Write-Host ""
    Write-Host "  Examples: BR-TheArk, LA-TheCommission, BR-BoardRoom1" -ForegroundColor DarkGray
    $tagInput = Read-Host "Enter Room Identifier (will be prefixed with MTR-)"
    
    if ([string]::IsNullOrWhiteSpace($tagInput)) {
        Write-Host -ForegroundColor Red "[!] Room identifier is required."
        continue
    }
    
    # Build full tag
    $GroupTag = "MTR-$tagInput"
    
    # Validate
    $tagErrors = Test-GroupTag -Tag $GroupTag
    
    if ($tagErrors.Count -gt 0) {
        Write-Host -ForegroundColor Red "[!] Group tag validation failed:"
        foreach ($err in $tagErrors) {
            Write-Host -ForegroundColor Red "    - $err"
        }
        Write-Host -ForegroundColor Yellow "    Resulting tag would be: $GroupTag"
    }
    else {
        $tagValid = $true
        Write-Host -ForegroundColor Green "[+] Group tag valid: $GroupTag"
    }
}

# ============================================================================
# Prompt for Computer Name (force uppercase, validate)
# ============================================================================
$nameValid = $false
while (-not $nameValid) {
    Write-Host ""
    Write-Host "  Max 15 characters. Letters, numbers, hyphens only." -ForegroundColor DarkGray
    $computerInput = Read-Host "Enter Computer Name"
    
    if ([string]::IsNullOrWhiteSpace($computerInput)) {
        Write-Host -ForegroundColor Red "[!] Computer name is required."
        continue
    }
    
    # Force uppercase
    $ComputerName = $computerInput.ToUpper()
    
    # Validate
    $nameErrors = Test-ComputerName -Name $ComputerName
    
    if ($nameErrors.Count -gt 0) {
        Write-Host -ForegroundColor Red "[!] Computer name validation failed:"
        foreach ($err in $nameErrors) {
            Write-Host -ForegroundColor Red "    - $err"
        }
    }
    else {
        $nameValid = $true
        Write-Host -ForegroundColor Green "[+] Computer name valid: $ComputerName ($($ComputerName.Length)/15 characters)"
    }
}

# ============================================================================
# Prompt for decryption password (masked)
# ============================================================================
Write-Host ""
$securePassword = Read-Host "Enter decryption password" -AsSecureString
$Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
)

# ============================================================================
# Summary and Confirmation
# ============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Configuration Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Group:         $Group" -ForegroundColor White
Write-Host "  GroupTag:      $GroupTag" -ForegroundColor White
Write-Host "  Computer Name: $ComputerName ($($ComputerName.Length)/15 chars)" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Proceed with registration? (Y/N)"
if ($confirm -notmatch '^[Yy]') {
    Write-Host -ForegroundColor Yellow "[-] Registration cancelled."
    exit 0
}

Write-Host ""

# ============================================================================
# Decrypt credentials
# ============================================================================
$creds = Get-DecryptedCredentials -Password $Password
if (-not $creds) {
    Write-Host -ForegroundColor Red "[!] Cannot proceed without valid credentials."
    exit 1
}

$TenantID = $creds.TenantID
$AppID = $creds.appid
$AppSecret = $creds.appsecret

# ============================================================================
# Install Get-WindowsAutopilotInfo script
# ============================================================================
Write-Host -ForegroundColor Yellow "[-] Installing Get-WindowsAutopilotInfo script..."
try {
    Install-Script -Name Get-WindowsAutopilotInfo -Force -ErrorAction Stop
    Write-Host -ForegroundColor Green "[+] Script installed successfully"
}
catch {
    Write-Host -ForegroundColor Red "[!] Failed to install script: $_"
    exit 1
}

# ============================================================================
# Run Autopilot registration
# ============================================================================
Write-Host -ForegroundColor Yellow "[-] Registering device with Windows Autopilot..."
Write-Host ""

try {
    Get-WindowsAutopilotInfo.ps1 `
        -Online `
        -Assign `
        -GroupTag $GroupTag `
        -AssignedComputerName $ComputerName `
        -AddToGroup $Group `
        -TenantID $TenantID `
        -AppID $AppID `
        -AppSecret $AppSecret

    Write-Host ""
    Write-Host -ForegroundColor Green "[+] Autopilot registration completed successfully!"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Registration Complete" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Group:         $Group" -ForegroundColor Green
    Write-Host "  GroupTag:      $GroupTag" -ForegroundColor Green
    Write-Host "  Computer Name: $ComputerName" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host -ForegroundColor Cyan "Next steps:"
    Write-Host "  1. Verify device appears in Intune > Devices > Windows Autopilot devices"
    Write-Host "  2. Verify device is in group: $Group"
    Write-Host "  3. Install MTR from the CreateSrsMedia.ps1 script / USB media"
    Write-Host ""
}
catch {
    Write-Host -ForegroundColor Red "[!] Error during Autopilot registration: $_"
    exit 1
}