[CmdletBinding()]
param()
$ScriptName = 'oobe_menu_functions.ps1'
$ScriptVersion = '25.6.27.2'

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

Write-Host -ForegroundColor Green "[+] $ScriptName $ScriptVersion ($WindowsPhase Phase)"


function step-oobeMenu_InstallM365Apps {
    $marker = 'C:\OSDCloud\Scripts\m365AppsInstalled.txt'
    $scriptDirectory = "C:\OSDCloud\Scripts"
    $scriptPath = "$scriptDirectory\InstallM365Apps.ps1"
    $officeConfigXml = "https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/supportFiles/MicrosoftOffice/configuration.xml"

    if (Test-Path $marker) {
        Write-Host -ForegroundColor Green "[+] Microsoft 365 Apps already installed (marker file present)."
        return $true
    }

    # Ensure script directory exists
    if (-not (Test-Path $scriptDirectory)) {
        Write-Host -ForegroundColor Yellow "[-] Creating $scriptDirectory..."
        New-Item -Path $scriptDirectory -ItemType Directory | Out-Null
    }

    # Download the installer script if not present
    if (-not (Test-Path $scriptPath)) {
        Write-Host -ForegroundColor Yellow "[-] Downloading M365 installer script..."
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/InstallM365Apps.ps1" -OutFile $scriptPath
    }

    Write-Host -ForegroundColor Yellow "[-] Installing M365 Applications (see $scriptPath)..."
    try {
        & $scriptPath -XMLURL $officeConfigXml -ErrorAction Stop
        if ($?) {
            Write-Host -ForegroundColor Green "[+] M365 installation script executed."
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


function step-oobeMenu_InstallUmbrella {
    [CmdletBinding()]
    param ()  

    Write-Host -ForegroundColor Yellow "[-] Installing Cisco Umbrella"
}


function step-oobeMenu_InstallDellCmd {
    [CmdletBinding()]
    param ()  
    
    Write-Host -ForegroundColor Yellow "[-] Installing Dell Commandupdate"
}


function step-oobeMenu_ClearTPM {
    [CmdletBinding()]
    param ()   

    Write-Host -ForegroundColor Yellow "[-] Clearing TPM"
}

function step-oobeMenu_RegisterAutopilot {
    [CmdletBinding()]
    param ()   

    Write-Host -ForegroundColor Yellow "[-] Registering with Windows Autopilot"
}