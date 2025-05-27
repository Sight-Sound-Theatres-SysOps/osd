# Set the Microsoft Teams directory path
$teamsDir = "C:\Program Files\WindowsApps\MSTeams_*"

# Check if the Microsoft Teams directory exists
if (Test-Path $teamsDir) {
    # If it exists, exit the script
    Write-Host -ForegroundColor Green "[+] New Microsoft Teams already installed"
    Exit
}

# Set the download URLs
$teamsbootstrapperURL = "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"
$MSTeamsx64URL = "https://go.microsoft.com/fwlink/?linkid=2196106"

# Set the destination directory
$destinationDir = "c:\Windows\sightsound"

# Check if the destination directory exists, if not create it
if (!(Test-Path $destinationDir)) {
    New-Item -ItemType Directory -Force -Path $destinationDir
}

# Set the destination file paths
$teamsbootstrapperPath = Join-Path $destinationDir "teamsbootstrapper.exe"
$MSTeamsx64Path = Join-Path $destinationDir "MSTeams-x64.msix"

# Download the files
Invoke-WebRequest -Uri $teamsbootstrapperURL -OutFile $teamsbootstrapperPath
Invoke-WebRequest -Uri $MSTeamsx64URL -OutFile $MSTeamsx64Path

#Install 
& "$destinationDir\teamsbootstrapper.exe" -p -o "$destinationDir\MSTeams-x64.msix" 
