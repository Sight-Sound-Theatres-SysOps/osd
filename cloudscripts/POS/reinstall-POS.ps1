############################################
#                                          # 
#  Reinstall StoreCommerce POS             #
#                                          #
############################################


# Uninstall existing StoreCommerce app
function Uninstall-StoreCommerce {
    [CmdletBinding()]
    param ()

    Write-Host -ForegroundColor Yellow "[!] Attempting to uninstall existing StoreCommerce app..."

    # Method 1: Use the StoreCommerce installer's built-in uninstall command
    $installerPath = "C:\temp\StoreCommerce.Installer.exe"
    if (Test-Path $installerPath) {
        Write-Host -ForegroundColor Yellow "[-] Running StoreCommerce.Installer.exe uninstall..."
        $process = Start-Process -FilePath $installerPath -ArgumentList "uninstall" -Wait -PassThru
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
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
        Write-Host -ForegroundColor Green "[+] StoreCommerce AppxPackage removed"
        return
    }

    Write-Host -ForegroundColor Cyan "[i] No existing StoreCommerce installation found"
}

Uninstall-StoreCommerce

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


# Reset execution policy to Restricted if it isn't already
if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'Restricted') {
    Write-Host -ForegroundColor Yellow "[!] Resetting ExecutionPolicy to Restricted for CurrentUser"
    Set-ExecutionPolicy Restricted -Scope CurrentUser -Force
}
