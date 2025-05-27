# Function to download file from URL
function Download-File {
    param (
        [string]$url,
        [string]$outputPath
    )

    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($url, $outputPath)
}

# Specify the folder to store .ico files
$iconFolder = "C:\Windows\sightsound"

# Create the folder if it doesn't exist
if (-not (Test-Path $iconFolder)) {
    New-Item -ItemType Directory -Path $iconFolder | Out-Null
}

# Define the list of URLs for .ico files
$iconUrls = @(
    "https://ssintunedata.blob.core.windows.net/box-cc/agentStartup.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/Calendar.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/OneDrive.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/Outlook.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/SharePoint.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/ShowTix_DEV.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/ShowTix_QA.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/ShowTix.ico",
    "https://ssintunedata.blob.core.windows.net/box-cc/agentSetup_Talkdesk.bat"
)

# Download each .ico file to the specified folder
foreach ($iconUrl in $iconUrls) {
    $fileName = Split-Path $iconUrl -Leaf
    $outputPath = Join-Path $iconFolder $fileName
    Download-File -url $iconUrl -outputPath $outputPath
}

# Create shortcuts
$shell = New-Object -ComObject WScript.Shell
$sAllUsersProfile = $shell.SpecialFolders("AllUsersDesktop")

# Create shortcuts for each link
$shortcuts = @(
    @{
        TargetPath = "https://sightsoundtheatres.sharepoint.com/teams/ContactCenter/"
        Description = "Contact Center SharePoint"
        IconFile = "$iconFolder\SharePoint.ico"
    },
    @{
        TargetPath = "https://outlook.office365.com/owa/?realm=sight-sound.com"
        Description = "Office 365 - Outlook Mail"
        IconFile = "$iconFolder\Outlook.ico"
    },
    @{
        TargetPath = "https://outlook.office.com/owa/?realm=sight-sound.com&exsvurl=1&ll-cc=1033&modurl=0&path=/calendar/view/Month"
        Description = "Office 365 - Outlook Calendar"
        IconFile = "$iconFolder\Calendar.ico"
    },
    @{
        TargetPath = "https://sightsoundtheatres-my.sharepoint.com/"
        Description = "Office 365 - OneDrive"
        IconFile = "$iconFolder\OneDrive.ico"
    },
    @{
        TargetPath = "C:\Windows\Sightsound\agentSetup_Talkdesk.bat"
        Description = "Agent startup tabs"
        IconFile = "$iconFolder\agentStartup.ico"
    },
    @{
        TargetPath = "https://showtix.sight-sound.com/"
        Description = "ShowTix 2.0 - Production"
        IconFile = "$iconFolder\ShowTix.ico"
    },
    @{
        TargetPath = "https://qa-showtix.sight-sound.com/"
        Description = "ShowTix 2.0 - QA"
        IconFile = "$iconFolder\ShowTix_QA.ico"
    },
    @{
        TargetPath = "https://dev-showtix.sight-sound.com/"
        Description = "ShowTix 2.0 - DEV"
        IconFile = "$iconFolder\ShowTix_DEV.ico"
    }
)

foreach ($shortcut in $shortcuts) {
    $link = $shell.CreateShortcut("$sAllUsersProfile\$($shortcut.Description).lnk")
    $link.TargetPath = $shortcut.TargetPath
    $link.Description = $shortcut.Description
    $link.IconLocation = $shortcut.IconFile
    $link.WindowStyle = 1
    $link.WorkingDirectory = "C:\Windows\sightsound\"
    $link.Save()
}
