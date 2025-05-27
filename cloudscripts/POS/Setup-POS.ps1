
# Clear the screen and display banner
Clear-Host
Write-Host "###############################################" -ForegroundColor Cyan
Write-Host "#   Microsoft Dynamics Store Commerce Setup   #" -ForegroundColor Cyan
Write-Host "###############################################" -ForegroundColor Cyan
Write-Host ""
Write-Host ""

# Check Curl version and install if necessary
function Install-Curl {
    [CmdletBinding()]
    param ()
    if (-not (Get-Command 'curl.exe' -ErrorAction SilentlyContinue)) {
        Write-Host -ForegroundColor Yellow "[-] Install Curl for Windows"
        $Uri = 'https://curl.se/windows/latest.cgi?p=win64-mingw.zip'
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile "$env:TEMP\curl.zip"
    
        $null = New-Item -Path "$env:TEMP\Curl" -ItemType Directory -Force
        Expand-Archive -Path "$env:TEMP\curl.zip" -DestinationPath "$env:TEMP\curl"
    
        Get-ChildItem "$env:TEMP\curl" -Include 'curl.exe' -Recurse | foreach {Copy-Item $_ -Destination "$env:SystemRoot\System32\curl.exe"}
    }
    else {
        $GetItemCurl = Get-Item -Path "$env:SystemRoot\System32\curl.exe" -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor Green "[+] Curl $($GetItemCurl.VersionInfo.FileVersion)"
    }
}

Install-Curl


# Install necessary WinGet Packages 
########################################################

$apps = "Microsoft.DotNet.DesktopRuntime.6",
        "Microsoft.DotNet.SDK.8"

foreach ($app in $apps) {
    winget install --id $app --accept-package-agreements --accept-source-agreements -e
}


# Set necessary reg keys
########################################################

# Function to create registry key if it doesn't exist
function Create-RegistryKeyIfNotExists {
    param (
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

# Function to create registry property if it doesn't exist
function Create-RegistryPropertyIfNotExists {
    param (
        [string]$Path,
        [string]$Name,
        [string]$Value,
        [string]$PropertyType
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    if (-not (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force | Out-Null
    }
}

# Create SSL 2.0 Client and Server registry keys if they don't exist
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client" "Enabled" 0 "DWord"
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" "Enabled" 0 "DWord"

# Create SSL 3.0 Client and Server registry keys if they don't exist
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client" "Enabled" 0 "DWord"
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" "Enabled" 0 "DWord"

# Create TLS 1.0 Client and Server registry keys if they don't exist
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" "Enabled" 0 "DWord"
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" "Enabled" 0 "DWord"

# Create TLS 1.1 Client and Server registry keys if they don't exist
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client" "Enabled" 0 "DWord"
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" "Enabled" 0 "DWord"

# Create TLS 1.2 Client and Server registry keys if they don't exist
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" "Enabled" 1 "DWord"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" "DisabledByDefault" 0 "DWord"
Create-RegistryKeyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" "Enabled" 1 "DWord"
Create-RegistryPropertyIfNotExists "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" "DisabledByDefault" 0 "DWord"

# Create SchUseStrongCrypto registry keys if they don't exist 
Create-RegistryPropertyIfNotExists "HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727" "SchUseStrongCrypto" 1 "DWord"
Create-RegistryPropertyIfNotExists "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" "SchUseStrongCrypto" 1 "DWord"
Create-RegistryPropertyIfNotExists "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727" "SchUseStrongCrypto" 1 "DWord"
Create-RegistryPropertyIfNotExists "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319" "SchUseStrongCrypto" 1 "DWord"


# Restart the explorer process to reload the registry
########################################################

# Get the process ID of the Process Explorer
Write-Host -ForegroundColor Yellow "[!] Restarting explorer process to reload the registry"
$processId = (Get-Process -Name explorer).Id
# Stop the process using the process ID
Stop-Process -Id $processId -Force



# Download and install the StoreCommerce app 
########################################################

$url = "https://ssintunedata.blob.core.windows.net/d365/StoreCommerce.Installer.exe"
$outputDir = "C:\temp"
$outputFile = Join-Path $outputDir "StoreCommerce.Installer.exe"

# Check if the output directory exists and create it if necessary
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Download the file using curl
Write-host -ForegroundColor yellow "[!] Downloading StoreCommerce.Installer.exe"
curl.exe -o $outputFile $url

# Run the installer with the provided arguments
cd $outputDir
.\StoreCommerce.Installer.exe install --useremoteappcontent --retailserverurl "https://sst-prodret.operations.dynamics.com/Commerce"

Write-Host -ForegroundColor Green "[+] StoreCommerce app installed successfully"



#Download and install the Epson OPOS ADK 
########################################################

$url = "https://ssintunedata.blob.core.windows.net/d365/EPSON_OPOS_ADK_V3.00ER20.exe"
$outputDir = "C:\temp"
$outputFile = Join-Path $outputDir "EPSON_OPOS_ADK_V3.00ER20.exe"

# Check if the output directory exists and create it if necessary
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Download the file using Curl
Write-host -ForegroundColor yellow "[!] Downloading Epson OPOS ADK"
curl.exe -o $outputFile $url

# Run the installer with the provided arguments
cd $outputDir
.\EPSON_OPOS_ADK_V3.00ER20.exe /q DisplayInternalUI=”no”

Write-Host -ForegroundColor Green "[+] Epson OPOS ADK installed successfully"



#Download and install the Epson OPOS CCOs 
########################################################

$url = "https://ssintunedata.blob.core.windows.net/d365/OPOS_CCOs_1.14.001.msi"
$outputDir = "C:\temp"
$outputFile = Join-Path $outputDir "OPOS_CCOs_1.14.001.msi"

# Check if the output directory exists and create it if necessary
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Download the file using Curl
Write-host -ForegroundColor yellow "[!] Downloading Epson OPOS CCOs"
curl.exe -o $outputFile $url

# Run the installer with the provided arguments
cd $outputDir
msiexec /I "OPOS_CCOs_1.14.001.msi" /quiet

Write-Host -ForegroundColor Green "[+] Epson OPOS CCOs installed successfully"



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



# Create install notes .txt file in c:\temp
########################################################

# Set the URL and destination path
$URL = "https://ssintunedata.blob.core.windows.net/d365/POS_install_notes.txt"
$Destination = "C:\temp\POS_install_notes.txt"

# Check if C:\temp directory exists, if not create it
if (!(Test-Path -Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp"
}

# Download the file
Invoke-WebRequest -Uri $URL -OutFile $Destination
Write-Host -ForegroundColor Cyan "[!] Install notes .txt file saved in c:\temp"



# Restart computer
########################################################

Write-Warning 'Device will restart in 30 seconds.  Press Ctrl + C to cancel'
        Start-Sleep -Seconds 30
        Restart-Computer -Force
