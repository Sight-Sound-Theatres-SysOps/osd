<#
.SYNOPSIS
    Deploy custom background images to Microsoft Teams Rooms on Windows.
    
.DESCRIPTION
    Downloads three background images from Azure Blob Storage and creates the
    SkypeSettings.xml configuration file. Device must be restarted to apply.

.NOTES
    Requires Teams Rooms Pro license for enhanced backgrounds.
    Update the URLs below with your Azure Blob Storage paths + SAS tokens.
#>

#Requires -RunAsAdministrator

#region ============== CONFIGURATION - UPDATE THESE URLs ==============

$Config = @{
    MainDisplayUrl      = "https://ssintunedata.blob.core.windows.net/teams-rooms/MainFoRDisplay.png"
    ExtendedDisplayUrl  = "https://ssintunedata.blob.core.windows.net/teams-rooms/ExtendedFoRDisplay.png"
    ConsoleUrl          = "https://ssintunedata.blob.core.windows.net/teams-rooms/Console.png"    
   
    # Restart Options
    AutoRestart         = $true   # Set to $true to automatically restart after deployment
    RestartDelaySeconds = 15      # Countdown before restart (gives time to cancel)
}

#endregion ==============================================================

$MTRPath = "C:\Users\Skype\AppData\Local\Packages\Microsoft.SkypeRoomSystem_8wekyb3d8bbwe\LocalState"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    $colors = @{ Info = "Cyan"; Success = "Green"; Warning = "Yellow"; Error = "Red" }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $colors[$Type]
}

function Download-Image {
    param([string]$Url, [string]$Destination, [string]$Name)
    
    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -match "YOURSTORAGEACCOUNT") {
        Write-Status "Skipping $Name - URL not configured" -Type Warning
        return $null
    }
    
    try {
        Write-Status "Downloading $Name..."
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $Destination)
        $webClient.Dispose()
        
        $size = [math]::Round((Get-Item $Destination).Length / 1KB, 1)
        Write-Status "$Name downloaded successfully (${size} KB)" -Type Success
        return $true
    }
    catch {
        Write-Status "Failed to download $Name : $_" -Type Error
        return $null
    }
}

# Main execution
Write-Status "=" * 50
Write-Status "Teams Room Custom Background Deployment"
Write-Status "=" * 50

# Ask about dual screen configuration
$dualScreenResponse = Read-Host "Does this room have dual front-of-room displays? (Y/N)"
$DualScreenMode = $dualScreenResponse -match '^[Yy]'

if ($DualScreenMode) {
    Write-Status "Configuring for dual front-of-room displays" -Type Info
} else {
    Write-Status "Configuring for single front-of-room display" -Type Info
}

# Validate path exists
if (-not (Test-Path $MTRPath)) {
    Write-Status "Creating MTR LocalState directory..." -Type Warning
    New-Item -Path $MTRPath -ItemType Directory -Force | Out-Null
}

# Download all three images
$mainFile = "MainFoRDisplay.png"
$extFile = "ExtendedForDisplay.png"
$consoleFile = "Console.png"

$mainResult = Download-Image -Url $Config.MainDisplayUrl -Destination "$MTRPath\$mainFile" -Name "Main Display"
$extResult = Download-Image -Url $Config.ExtendedDisplayUrl -Destination "$MTRPath\$extFile" -Name "Extended Display"
$consoleResult = Download-Image -Url $Config.ConsoleUrl -Destination "$MTRPath\$consoleFile" -Name "Console"

if (-not $mainResult) {
    Write-Status "Main display image is required. Please update the configuration." -Type Error
    exit 1
}

# Build XML content
$xmlContent = @"
<SkypeSettings>
  <Theming>
    <ThemeName>Custom</ThemeName>
    <CustomBackgroundMainFoRDisplay>$mainFile</CustomBackgroundMainFoRDisplay>
"@

if ($DualScreenMode -and $extResult) {
    $xmlContent += "    <CustomBackgroundExtendedFoRDisplay>$extFile</CustomBackgroundExtendedFoRDisplay>`n"
}

if ($consoleResult) {
    $xmlContent += "    <CustomBackgroundConsole>$consoleFile</CustomBackgroundConsole>`n"
}

$xmlContent += @"
  </Theming>
</SkypeSettings>
"@

# Write XML file
$xmlPath = "$MTRPath\SkypeSettings.xml"
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($xmlPath, $xmlContent, $utf8NoBom)
    Write-Status "SkypeSettings.xml created successfully" -Type Success
}
catch {
    Write-Status "Failed to create SkypeSettings.xml: $_" -Type Error
    exit 1
}

# Display summary
Write-Status "-" * 50
Write-Status "Deployment Complete!" -Type Success
Write-Status "Files deployed to: $MTRPath"
Write-Status ""
Write-Status "XML Configuration:"
$xmlContent -split "`n" | ForEach-Object { Write-Status "  $_" }
Write-Status "-" * 50
Write-Status "RESTART REQUIRED to apply changes" -Type Warning

# Handle restart
if ($Config.AutoRestart) {
    Write-Status ""
    Write-Status "Device will restart in $($Config.RestartDelaySeconds) seconds..." -Type Warning
    Write-Status "Press Ctrl+C to cancel"
    Start-Sleep -Seconds $Config.RestartDelaySeconds
    Restart-Computer -Force
}
else {
    Write-Status ""
    Write-Status "Run 'Restart-Computer -Force' to apply changes"
}
