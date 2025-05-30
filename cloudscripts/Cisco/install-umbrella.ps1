
# Banner
Write-Host "###########################################" -ForegroundColor Cyan
Write-Host "#                                         #" -ForegroundColor Cyan
Write-Host "#       Install Cisco Umbrella Client     #" -ForegroundColor Cyan
Write-Host "#                                         #" -ForegroundColor Cyan
Write-Host "###########################################" -ForegroundColor Cyan
Write-Host ""

# Define file paths
$tempFolder = "C:\temp"
$vpnMsiUrl = "https://ssintunedata.blob.core.windows.net/cisco/cisco-secure-client-win-5.1.9.113-core-vpn-predeploy-k9.msi"
$vpnMsiPath = "$tempFolder\cisco-secure-client-core-vpn.msi"
$umbrellaMsiUrl = "https://ssintunedata.blob.core.windows.net/cisco/cisco-secure-client-win-5.1.9.113-umbrella-predeploy-k9.msi"
$umbrellaMsiPath = "$tempFolder\cisco-secure-client-umbrella.msi"

# Create temp folder if it doesn't exist
if (-not (Test-Path -Path $tempFolder)) {
    Write-Host "[-] Creating temp folder..." -ForegroundColor Yellow
    New-Item -Path $tempFolder -ItemType Directory
} else {
    Write-Host "[+] Temp folder already exists." -ForegroundColor Green
}

# Define the OrgInfo.json content
$jsonContent = @{
    organizationId = "2277035"
    fingerprint = "db4a2dca2f04f157600531005e14a056"
    userId = "8949621"
} | ConvertTo-Json -Depth 3

# Define the OrgInfo.json file path
$orgInfoPath = "$env:ProgramData\Cisco\Cisco Secure Client\Umbrella\OrgInfo.json"

# Check if the OrgInfo.json file exists, create it if it does not
if (-Not (Test-Path -Path $orgInfoPath)) {
    write-host "[-] Creating OrgInfo.json file" -ForegroundColor Yellow
    New-Item -ItemType File -Path $orgInfoPath -Force
    Set-Content -Path $orgInfoPath -Value $jsonContent
} else {
    Write-Host "[+] OrgInfo.json file already exists at $orgInfoPath" -ForegroundColor Green
}

# Download files using curl.exe
Write-Host "[!] Downloading VPN MSI..." -ForegroundColor Yellow
curl.exe -o $vpnMsiPath $vpnMsiUrl

Write-Host "[!} Downloading Umbrella MSI..." -ForegroundColor Yellow
curl.exe -o $umbrellaMsiPath $umbrellaMsiUrl

# Install VPN MSI
Write-Host "[+] Installing Cisco VPN..." -ForegroundColor Yellow
Start-Process msiexec.exe -ArgumentList "/i `"$vpnMsiPath`" /norestart /passive PRE_DEPLOY_DISABLE_VPN=1 /qn" -Wait

# Install Umbrella MSI
Write-Host "[+] Installing Cisco Umbrella..." -ForegroundColor Yellow
Start-Process msiexec.exe -ArgumentList "/i `"$umbrellaMsiPath`" /norestart /passive LOCKDOWN=1 ARPSYSTEMCOMPONENT=1 /qn" -Wait

Write-Host "[+] Installation completed." -ForegroundColor Green
write-host "[!] Cleaning up temp folder..." -ForegroundColor Yellow
Remove-Item -Path $vpnMsiPath, $umbrellaMsiPath -Force | Out-Null
