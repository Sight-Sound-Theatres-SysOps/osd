# Define folders
$WallpaperFolder = "C:\Windows\Web\Wallpaper\Windows"
$LockScreenFolder = "C:\Windows\Web\Screen"
$Wallpaper4KFolder = "C:\Windows\Web\4K\Wallpaper\Windows"

# Define files
$FilesToDelete = @(
    "$WallpaperFolder\img0.jpg",
    "$LockScreenFolder\img100.jpg",
    "$LockScreenFolder\img105.jpg",
    "$Wallpaper4KFolder\img0_1920x1200.jpg"
)

# Define the principals
$LocalAdministratorsPrincipal = "BUILTIN\Administrators"
$TrustedInstallerPrincipal = "NT SERVICE\TrustedInstaller"

# Function to take ownership of a folder
function Take-Ownership {
    param (
        [parameter(Mandatory = $true)]
        [string]$FolderPath
    )

    try {
        # Take ownership of the folder
        takeown /F $FolderPath /A /R /D Y | Out-Null

        # Set the owner to TrustedInstaller
        icacls $FolderPath /setowner "$($TrustedInstallerPrincipal)" /T /C /Q | Out-Null
    }
    catch {
        # Suppress error output
    }
}

# Function to set full control permissions for administrators group
function Set-FullControlPermissions {
    param (
        [parameter(Mandatory = $true)]
        [string]$FilePath,
        [parameter(Mandatory = $true)]
        [string]$Principal
    )

    try {
        # Get the current ACL
        $acl = Get-Acl $FilePath

        # Define the access rule
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($Principal, "FullControl", "Allow")

        # Add the access rule to the ACL
        $acl.SetAccessRule($rule)

        # Set the modified ACL back to the file
        Set-Acl $FilePath $acl | Out-Null
    }
    catch {
        # Suppress error output
    }
}

# Function to delete files
function Delete-Files {
    param (
        [parameter(Mandatory = $true)]
        [string[]]$FilePaths
    )

    foreach ($FilePath in $FilePaths) {
        try {
            # Delete the file
            Remove-Item $FilePath -Force -ErrorAction Stop | Out-Null
        }
        catch {
            # Suppress error output
        }
    }
}

# Take ownership of each folder
# Take-Ownership -FolderPath $WallpaperFolder | Out-Null
# Take-Ownership -FolderPath $LockScreenFolder | Out-Null
# Take-Ownership -FolderPath $Wallpaper4KFolder | Out-Null

# Set full control permissions for administrators group on each file
$AdministratorsGroup = "BUILTIN\Administrators"
Set-FullControlPermissions -FilePath $FilesToDelete[0] -Principal $AdministratorsGroup | Out-Null
Set-FullControlPermissions -FilePath $FilesToDelete[1] -Principal $AdministratorsGroup | Out-Null
Set-FullControlPermissions -FilePath $FilesToDelete[2] -Principal $AdministratorsGroup | Out-Null
Set-FullControlPermissions -FilePath $FilesToDelete[3] -Principal $AdministratorsGroup | Out-Null

# Delete the files
Delete-Files -FilePaths $FilesToDelete | Out-Null

# Download and replace wallpaper and lock screen files
$WallPaperURL = "https://ssintunedata.blob.core.windows.net/customization/img0_3840x2160.jpg"
$LockScreenURL = "https://ssintunedata.blob.core.windows.net/customization/img100.jpg"

Invoke-WebRequest -UseBasicParsing -Uri $WallPaperURL -OutFile "$WallpaperFolder\img0.jpg" | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri $LockScreenURL -OutFile "$LockScreenFolder\img100.jpg" | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri $LockScreenURL -OutFile "$LockScreenFolder\img105.jpg" | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri $WallPaperURL -OutFile "$Wallpaper4KFolder\img0_1920x1200.jpg" | Out-Null
