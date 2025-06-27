[CmdletBinding()]
param()
$ScriptName = 'oobe_menu_functions.ps1'
$ScriptVersion = '25.6.27.1'

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
    [CmdletBinding()]
    param ()

    $scriptDirectory = "C:\OSDCloud\Scripts"
    $scriptPath = Join-Path $scriptDirectory "InstallM365Apps.ps1"
    $officeConfigXml = "https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/supportFiles/MicrosoftOffice/configuration.xml"

    # Helper: Test for any M365 Office app by product name
    function Test-M365Installed {
        $officeNames = @(
            "Microsoft 365 Apps for enterprise",
            "Microsoft 365 Apps for business",
            "Microsoft Office 365 ProPlus",
            "Microsoft Office Professional Plus 2016",
            "Microsoft Office Professional Plus 2019",
            "Microsoft Office LTSC",
            "Microsoft Office 365",
            "Office16",
            "Office19"
        )

        $found = $false
        $UninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($keyPath in $UninstallKeys) {
            $apps = Get-ItemProperty $keyPath -ErrorAction SilentlyContinue
            foreach ($app in $apps) {
                foreach ($name in $officeNames) {
                    if ($app.DisplayName -like "*$name*") {
                        return $true
                    }
                }
            }
        }
        return $false
    }

    # Ensure script directory exists
    if (-not (Test-Path $scriptDirectory)) {
        Write-Host -ForegroundColor Yellow "[-] Creating $scriptDirectory..."
        New-Item -Path $scriptDirectory -ItemType Directory | Out-Null
    }

    if (Test-M365Installed) {
        Write-Host -ForegroundColor Green "[+] Microsoft 365 Apps already installed."
        return $true
    }

    # Download the installer script if not present
    if (-not (Test-Path $scriptPath)) {
        Write-Host -ForegroundColor Yellow "[-] Downloading M365 installer script..."
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/InstallM365Apps.ps1" -OutFile $scriptPath
    }

    Write-Host -ForegroundColor Yellow "[-] Installing M365 Applications (see $scriptPath)..."
    try {
        & $scriptPath -XMLURL $officeConfigXml -ErrorAction Stop
        Write-Host -ForegroundColor Green "[+] M365 installation script executed."
    } catch {
        Write-Host -ForegroundColor Red "[!] Error running M365 install: $_"
        return $false
    }
    return $true
}
