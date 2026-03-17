
#Requires -RunAsAdministrator

# Verify script is running as ssLocalAdmin
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($currentUser -notlike '*\ssLocalAdmin') {
    Write-Host -ForegroundColor Red "[!] This script must be run as ssLocalAdmin. Current user: $currentUser"
    exit 1
}

# Clear the screen and display banner
Clear-Host
Write-Host "###############################################" -ForegroundColor Cyan
Write-Host "#   Microsoft Dynamics Store Commerce Setup   #" -ForegroundColor Cyan
Write-Host "###############################################" -ForegroundColor Cyan
Write-Host ""
Write-Host ""

# Create temp directory once for all downloads
$tempDir = "C:\temp"
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Check curl version and install if necessary
function Install-Curl {
    [CmdletBinding()]
    param ()
    if (-not (Get-Command 'curl.exe' -ErrorAction SilentlyContinue)) {
        Write-Host -ForegroundColor Yellow "[-] Installing Curl for Windows"
        $Uri = 'https://curl.se/windows/latest.cgi?p=win64-mingw.zip'
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile "$tempDir\curl.zip"
        Expand-Archive -Path "$tempDir\curl.zip" -DestinationPath "$tempDir\curl" -Force
        Get-ChildItem "$tempDir\curl" -Include 'curl.exe' -Recurse | ForEach-Object { Copy-Item $_ -Destination "$env:SystemRoot\System32\curl.exe" }
        Write-Host -ForegroundColor Green "[+] Curl installed"
    }
    else {
        $GetItemCurl = Get-Item -Path "$env:SystemRoot\System32\curl.exe" -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor Green "[+] Curl $($GetItemCurl.VersionInfo.FileVersion)"
    }
}

Install-Curl

# Check and install WinGet if not present
function Install-WinGetIfNeeded {
    [CmdletBinding()]
    param ()
    if (Get-Command 'winget.exe' -ErrorAction SilentlyContinue) {
        Write-Host -ForegroundColor Green "[+] WinGet is already installed"
        return
    }
    Write-Host -ForegroundColor Yellow "[-] WinGet not found. Installing..."
    try {
        $wingetScript = Invoke-RestMethod -Uri "https://asheroto.com/winget" -ErrorAction Stop
        if ($wingetScript) {
            $tempScript = Join-Path $tempDir "winget_install_$(Get-Random).ps1"
            $wingetScript | Out-File -FilePath $tempScript -Force
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript
            Remove-Item -Path $tempScript -Force -ErrorAction Ignore
            Write-Host -ForegroundColor Green "[+] WinGet installed successfully"
        }
        else {
            throw "WinGet installation script content was empty"
        }
    }
    catch {
        Write-Host -ForegroundColor Red "[!] Failed to install WinGet: $($_.Exception.Message)"
        exit 1
    }
}

Install-WinGetIfNeeded


# Install necessary WinGet Packages 
########################################################

$apps = "Microsoft.DotNet.DesktopRuntime.6",
        "Microsoft.DotNet.SDK.8"

foreach ($app in $apps) {
    winget install --id $app --source winget --accept-package-agreements --accept-source-agreements -e
}


# Configure TLS/SSL protocols and strong crypto
########################################################

function Set-RegistryProperty {
    param (
        [string]$Path,
        [string]$Name,
        [string]$Value,
        [string]$PropertyType
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force | Out-Null
}

$basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"

# Disable legacy protocols (SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1)
foreach ($protocol in @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1")) {
    foreach ($role in @("Client", "Server")) {
        Set-RegistryProperty "$basePath\$protocol\$role" "Enabled" 0 "DWord"
    }
}

# Enable TLS 1.2
foreach ($role in @("Client", "Server")) {
    Set-RegistryProperty "$basePath\TLS 1.2\$role" "Enabled" 1 "DWord"
    Set-RegistryProperty "$basePath\TLS 1.2\$role" "DisabledByDefault" 0 "DWord"
}

# Enable strong crypto for .NET Framework
foreach ($fwPath in @(
    "HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727",
    "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"
)) {
    Set-RegistryProperty $fwPath "SchUseStrongCrypto" 1 "DWord"
}

Write-Host -ForegroundColor Green "[+] TLS/SSL protocols and strong crypto configured"



# Download and install the StoreCommerce app 
########################################################

$storeCommerceFile = Join-Path $tempDir "StoreCommerce.Installer.exe"
Write-Host -ForegroundColor Yellow "[!] Downloading StoreCommerce.Installer.exe"
curl.exe -o $storeCommerceFile "https://ssintunedata.blob.core.windows.net/d365/StoreCommerce.Installer.exe"

Write-Host -ForegroundColor Yellow "[!] Installing StoreCommerce..."
& $storeCommerceFile install --useremoteappcontent --retailserverurl "https://sst-prodret.operations.dynamics.com/Commerce"
if ($LASTEXITCODE -ne 0) {
    Write-Host -ForegroundColor Red "[!] StoreCommerce installer exited with code $LASTEXITCODE"
} else {
    Write-Host -ForegroundColor Green "[+] StoreCommerce app installed successfully"
}



#Download and install the Epson OPOS ADK 
########################################################

$epsonAdkFile = Join-Path $tempDir "EPSON_OPOS_ADK_V3.00ER20.exe"
Write-Host -ForegroundColor Yellow "[!] Downloading Epson OPOS ADK"
curl.exe -o $epsonAdkFile "https://ssintunedata.blob.core.windows.net/d365/EPSON_OPOS_ADK_V3.00ER20.exe"

Write-Host -ForegroundColor Yellow "[!] Installing Epson OPOS ADK..."
& $epsonAdkFile /q DisplayInternalUI="no"
if ($LASTEXITCODE -ne 0) {
    Write-Host -ForegroundColor Red "[!] Epson OPOS ADK installer exited with code $LASTEXITCODE"
} else {
    Write-Host -ForegroundColor Green "[+] Epson OPOS ADK installed successfully"
}



#Download and install the Epson OPOS CCOs 
########################################################

$epsonCcosFile = Join-Path $tempDir "OPOS_CCOs_1.14.001.msi"
Write-Host -ForegroundColor Yellow "[!] Downloading Epson OPOS CCOs"
curl.exe -o $epsonCcosFile "https://ssintunedata.blob.core.windows.net/d365/OPOS_CCOs_1.14.001.msi"

Write-Host -ForegroundColor Yellow "[!] Installing Epson OPOS CCOs..."
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/I `"$epsonCcosFile`" /quiet" -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host -ForegroundColor Red "[!] Epson OPOS CCOs installer exited with code $($process.ExitCode)"
} else {
    Write-Host -ForegroundColor Green "[+] Epson OPOS CCOs installed successfully"
}



# Setup local POSUser account
########################################################

# Define the username and password
$username = "POSUser"
$password = ConvertTo-SecureString "Almond1" -AsPlainText -Force

# Check if the user already exists
if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
    Write-Warning "User $username already exists. Skipping user creation."
} else {
    # Create the user account
    New-LocalUser -Name $username -Password $password -PasswordNeverExpires
    Write-Host -ForegroundColor Green "[+] User $username created with password set to never expire."
}

# Add user to local group RetailChannelUsers
# $group = "RetailChannelUsers"
# Add-LocalGroupMember -Group $group -Member $username
# Write-Host "User $username added to group $group."

# Set autologin registry keys
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$regProps = @{
    "DefaultUserName" = $username
    "DefaultPassword" = "Almond1"
    "AutoAdminLogon" = "1"
}

# Set registry values
foreach ($prop in $regProps.GetEnumerator()) {
    Set-ItemProperty -Path $regPath -Name $prop.Key -Value $prop.Value
}

Write-Host -ForegroundColor Green "[+] Auto-login for .\POSUser configured."



# Disable OneDrive for all users
########################################################

# Define the path of the OneDrive group policy registry key
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"

# Create the OneDrive group policy registry key if it doesn't exist
if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

# Set the value of the "DisableFileSyncNGSC" registry entry to 1 to disable OneDrive
Set-ItemProperty -Path $registryPath -Name "DisableFileSyncNGSC" -Value 1 | Out-Null
Write-Host -ForegroundColor Green "[+] OneDrive disabled for all users"



# Set power settings
########################################################
powercfg /change monitor-timeout-ac 20; powercfg /change standby-timeout-ac 0
Write-Host -ForegroundColor Green "[+] Powersettings set to monitor timeout 20 minutes and standby timeout 0 minutes"



# Download install notes
########################################################

$installNotesFile = Join-Path $tempDir "POS_install_notes.txt"
curl.exe -o $installNotesFile "https://ssintunedata.blob.core.windows.net/d365/POS_install_notes.txt"
Write-Host -ForegroundColor Cyan "[!] Install notes saved to $installNotesFile"



# Reset execution policy
########################################################
if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'Restricted') {
    Set-ExecutionPolicy Restricted -Scope CurrentUser -Force
    Write-Host -ForegroundColor Green "[+] Execution policy set to Restricted for CurrentUser"
} else {
    Write-Host -ForegroundColor DarkGray "[+] Execution policy already set to Restricted for CurrentUser"
}



# Restart computer
########################################################

Write-Warning 'Device will restart in 30 seconds. Press Ctrl + C to cancel'
Start-Sleep -Seconds 30
Restart-Computer -Force
