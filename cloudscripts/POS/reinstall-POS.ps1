############################################
#                                          # 
#  Remove app from programs list manually  #
#                                          #
############################################


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




