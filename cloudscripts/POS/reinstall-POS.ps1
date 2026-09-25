############################################
#                                          # 
#  Reinstall StoreCommerce POS             #
#                                          #
############################################

# Must be run as the posuser account (the one actually logged in at the register)
if ($env:USERNAME -ne 'posuser') {
    Write-Warning "This script must be run from the 'posuser' account. Currently logged in as '$env:USERNAME'. Restart PowerShell as posuser and try again."
    exit 1
}

# Prompt once for admin credentials, reused for every elevation-required step below
$adminCred = Get-Credential -Message "Enter local admin credentials to install POS components"

# Uninstall existing StoreCommerce app
function Uninstall-StoreCommerce {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCredential]$Credential
    )

    Write-Host -ForegroundColor Yellow "[!] Attempting to uninstall existing StoreCommerce app..."

    # Method 1: Use the StoreCommerce installer's built-in uninstall command
    $installerPath = "C:\temp\StoreCommerce.Installer.exe"
    if (Test-Path $installerPath) {
        Write-Host -ForegroundColor Yellow "[-] Running StoreCommerce.Installer.exe uninstall..."
        $process = Start-Process -FilePath $installerPath -ArgumentList "uninstall" -Credential $Credential -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Host -ForegroundColor Green "[+] StoreCommerce uninstalled successfully via installer"
            return
        }
        else {
            Write-Host -ForegroundColor Yellow "[!] Installer uninstall exited with code $($process.ExitCode), trying alternative method..."
        }
    }

    # Method 2: Remove via AppxPackage (Store Commerce is an MSIX app)
    $appxPackage = Get-AppxPackage -AllUsers -Name "*StoreCommerce*" -ErrorAction SilentlyContinue
    if ($appxPackage) {
        foreach ($pkg in $appxPackage) {
            Write-Host -ForegroundColor Yellow "[-] Removing AppxPackage: $($pkg.PackageFullName)"
            # Remove-AppxPackage -AllUsers needs an elevated session, so run it in a child process under the admin credential
            $removeCmd = "Remove-AppxPackage -Package '$($pkg.PackageFullName)' -AllUsers -ErrorAction SilentlyContinue"
            Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-Command', $removeCmd -Credential $Credential -Wait
        }
        Write-Host -ForegroundColor Green "[+] StoreCommerce AppxPackage removed"
        return
    }

    Write-Host -ForegroundColor Cyan "[i] No existing StoreCommerce installation found"
}

Uninstall-StoreCommerce -Credential $adminCred

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

# Check for required .NET Desktop Runtime version and install if missing
function Test-DotNetDesktopRuntime {
    [CmdletBinding()]
    param (
        [string]$RequiredVersion = "10.0.12"
    )

    $dotnetCmd = Get-Command 'dotnet.exe' -ErrorAction SilentlyContinue
    if (-not $dotnetCmd) {
        return $false
    }

    $runtimes = & dotnet.exe --list-runtimes 2>$null
    $match = $runtimes | Where-Object { $_ -match "^Microsoft\.WindowsDesktop\.App $([regex]::Escape($RequiredVersion))\b" }
    return [bool]$match
}

function Install-DotNetDesktopRuntime {
    [CmdletBinding()]
    param (
        [string]$Version = "10.0.12",
        [Parameter(Mandatory)]
        [PSCredential]$Credential
    )

    $url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/$Version/windowsdesktop-runtime-$Version-win-x64.exe"
    $outputDir = "C:\temp"
    $outputFile = Join-Path $outputDir "windowsdesktop-runtime-$Version-win-x64.exe"

    if (!(Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    Write-Host -ForegroundColor Yellow "[!] Downloading .NET Desktop Runtime $Version..."
    curl.exe -o $outputFile $url

    Write-Host -ForegroundColor Yellow "[-] Installing .NET Desktop Runtime $Version..."
    $process = Start-Process -FilePath $outputFile -ArgumentList "/install", "/quiet", "/norestart" -Credential $Credential -Wait -PassThru
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Host -ForegroundColor Green "[+] .NET Desktop Runtime $Version installed successfully"
    }
    else {
        Write-Host -ForegroundColor Red "[x] .NET Desktop Runtime install exited with code $($process.ExitCode)"
    }

    Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
}

$requiredDotNetVersion = "10.0.12"
if (Test-DotNetDesktopRuntime -RequiredVersion $requiredDotNetVersion) {
    Write-Host -ForegroundColor Green "[+] .NET Desktop Runtime $requiredDotNetVersion is already installed"
}
else {
    Write-Host -ForegroundColor Yellow "[!] .NET Desktop Runtime $requiredDotNetVersion not found"
    Install-DotNetDesktopRuntime -Version $requiredDotNetVersion -Credential $adminCred
}

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
$installArgs = 'install', '--useremoteappcontent', '--retailserverurl', 'https://sst-prodret.operations.dynamics.com/Commerce'
$process = Start-Process -FilePath $outputFile -ArgumentList $installArgs -Credential $adminCred -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host -ForegroundColor Red "[x] StoreCommerce install exited with code $($process.ExitCode)"
}


# Reset execution policy to Restricted if it isn't already
if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'Restricted') {
    Write-Host -ForegroundColor Yellow "[!] Resetting ExecutionPolicy to Restricted for CurrentUser"
    Set-ExecutionPolicy Restricted -Scope CurrentUser -Force
}
