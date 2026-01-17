[CmdletBinding()]
param()
$ScriptName = 'oobe_menu_functions.ps1'
$ScriptVersion = '26.1.17.1'

#region Initialize
if ($env:SystemDrive -eq 'X:') {
    $WindowsPhase = 'WinPE'
}
else {
    $ImageState = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction Ignore).ImageState
    if ($env:UserName -eq 'defaultuser0') {$WindowsPhase = 'OOBE'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE') {$WindowsPhase = 'Specialize'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_AUDIT') {$WindowsPhase = 'AuditMode'}
    else {$WindowsPhase = 'Windows'}
}

Write-Host -ForegroundColor DarkGray "[✓] $ScriptName $ScriptVersion ($WindowsPhase Phase)"

##===============================##
##           FUNCTIONS           ## 
##===============================##

function step-oobeMenu_InstallM365Apps {
    $marker = 'C:\OSDCloud\Scripts\m365AppsInstalled.txt'
    $scriptDirectory = "C:\OSDCloud\Scripts"
    $scriptPath = "$scriptDirectory\InstallM365Apps.ps1"
    $officeConfigXml = "https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/supportFiles/MicrosoftOffice/configuration.xml"

    if (Test-Path $marker) {
        Write-Host -ForegroundColor DarkGray "[✓] Microsoft 365 Apps already installed (marker file present)."
        return $true
    }

    # Ensure script directory exists
    if (-not (Test-Path $scriptDirectory)) {
        Write-Host -ForegroundColor Cyan "[→] Creating $scriptDirectory..."
        New-Item -Path $scriptDirectory -ItemType Directory | Out-Null
    }

    # Download the installer script if not present
    if (-not (Test-Path $scriptPath)) {
        Write-Host -ForegroundColor Cyan "[→] Downloading M365 installer script..."
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/InstallM365Apps.ps1" -OutFile $scriptPath
    }

    Write-Host -ForegroundColor Cyan "[→] Installing M365 Applications (see $scriptPath)..."
    try {
        & $scriptPath -XMLURL $officeConfigXml -ErrorAction Stop
        if ($?) {
            Write-Host -ForegroundColor DarkGray "[✓] M365 installation script executed."
            # Marker for future runs
            New-Item -ItemType File -Path $marker -Force | Out-Null
            return $true
        } else {
            Write-Host -ForegroundColor Red "[!] Office installer returned an error."
            return $false
        }
    } catch {
        Write-Host -ForegroundColor Red "[!] Error running M365 install: $_"
        return $false
    }
}

function step-oobeMenu_RegisterAutopilot {
    [CmdletBinding()]
    param (
        [string]$GroupTag,
        [string]$Group,
        [string]$ComputerName,
        [string]$EnrollmentPassword,
        [bool]$UseCommunityScript
    )

    Write-Host -ForegroundColor Cyan "[→] Registering with Windows Autopilot"

    # Decrypt credentials
    $jsonContent = Test-AutopilotPassword -Password $EnrollmentPassword
    if (-not $jsonContent) {
        Write-Host -ForegroundColor Red "[!] Failed to decrypt Autopilot credentials. Skipping registration."
        return $false
    }

    $TenantID  = $jsonContent.TenantID
    $appID     = $jsonContent.appid
    $appsecret = $jsonContent.appsecret

    # Install the appropriate script based on the flag
    if ($UseCommunityScript) {
        Write-Host -ForegroundColor Cyan "[→] Installing Community Autopilot script..."
        Install-Script Get-WindowsAutopilotInfoCommunity -Force
        $scriptName = "Get-WindowsAutopilotInfoCommunity.ps1"
    } else {
        Write-Host -ForegroundColor Cyan "[→] Installing standard Autopilot script..."
        Install-Script Get-WindowsAutopilotInfo -Force
        $scriptName = "Get-WindowsAutopilotInfo.ps1"
    }
    
    Install-Script Get-AutopilotDiagnosticsCommunity -Force 

    # Run the appropriate script
    try {
        Write-Host -ForegroundColor Cyan "[→] Running $scriptName..."
        Write-Host -ForegroundColor Yellow "[!] Tag: $GroupTag - Computer Name: $ComputerName - Group: $Group"

        if ($UseCommunityScript) {
            & Get-WindowsAutopilotInfoCommunity.ps1 -Assign `
                -GroupTag $GroupTag `
                -AssignedComputerName $ComputerName `
                -AddToGroup $Group `
                -online `
                -TenantID $TenantID `
                -appID $appID `
                -appsecret $appsecret
        } else {
            & Get-WindowsAutopilotInfo.ps1 -Assign `
                -GroupTag $GroupTag `
                -AssignedComputerName $ComputerName `
                -AddToGroup $Group `
                -online `
                -TenantID $TenantID `
                -appID $appID `
                -appsecret $appsecret
        }
        
        Write-Host -ForegroundColor DarkGray "[✓] Autopilot registration completed using $(if ($UseCommunityScript) { 'Community' } else { 'Standard' }) script."
        return $true
    } catch {
        Write-Host -ForegroundColor Red "[!] Error during Autopilot registration: $_"
        return $false
    }
}

function Test-AutopilotPassword {
    param (
        [string]$Password
    )
    $blobUrl = "https://ssintunedata.blob.core.windows.net/autopilot/autopilot.json.enc"
    $tempFile = "$env:TEMP\autopilot.json.enc"
    try { Invoke-WebRequest -Uri $blobUrl -OutFile $tempFile -ErrorAction Stop }
    catch { return $false }

    # Try decrypting
    try {
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

        $cryptoStream.Close(); $memoryStream.Close(); $aes.Dispose()
        Remove-Item $tempFile -Force

        $jsonContent = $decryptedText | ConvertFrom-Json
        # Optionally return the credentials object here
        return $jsonContent
    } catch {
        Remove-Item $tempFile -Force
        return $false
    }
}
