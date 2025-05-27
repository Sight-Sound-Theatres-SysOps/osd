# Set the Microsoft Teams directory path
$teamsDir = "C:\Program Files\WindowsApps\MSTeams_*"

# Check if the Microsoft Teams directory exists
if (Test-Path $teamsDir) {
    Write-Host -ForegroundColor Green "[+] New Microsoft Teams already installed"

    # Create a shortcut on the All Users Desktop
    $allUsersDesktopPath = "C:\Users\Public\Desktop"
    $shortcutPath = Join-Path -Path $allUsersDesktopPath -ChildPath "Microsoft Teams.lnk"
    $targetPath = (Get-Item -Path $teamsDir).FullName + "\Teams.exe"

    if (Test-Path $targetPath) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.IconLocation = $targetPath
        $shortcut.Save()
        Write-Host -ForegroundColor Green "[+] Microsoft Teams shortcut created on All Users Desktop."
    } else {
        Write-Host -ForegroundColor Yellow "[-] Teams executable not found. Shortcut was not created."
    }

    Exit
} else {
    Write-Host -ForegroundColor Yellow "[-] New Microsoft Teams is not installed."
}
