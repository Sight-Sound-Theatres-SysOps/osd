<#
.SYNOPSIS
Update installed modules to the latest production or pre-release version.

.DESCRIPTION
This function updates all installed modules to the latest production or pre-release version (based on the AllowPrerelease switch).

.PARAMETER AllowPrerelease
If specified, updates to the latest pre-release versions; otherwise, updates to the latest production versions.

.PARAMETER ShowErrors
If specified, shows specific PowerShell error messages when an error occurs during the module update process.

.EXAMPLE
Update-ModuleVersions -AllowPrerelease -ShowErrors
# Updates all installed modules to the latest pre-release versions and shows specific error messages when an error occurs.

.EXAMPLE
Update-ModuleVersions
# Updates all installed modules to the latest production versions without showing specific error messages.

.AUTHER
Matthew Miles
#>

function Update-ModuleVersions {
    [CmdletBinding()]
    param (
        [switch]$AllowPrerelease,
        [switch]$ShowErrors
    )

    # Check admin privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
        Throw "This function requires administrator privileges."
    }

    # Get all installed modules
    Write-Host "Retrieving all installed modules ..." -ForegroundColor Green
    $CurrentModules = Get-InstalledModule | Select-Object Name, Version | Sort-Object Name

    if (-not $CurrentModules) {
        Write-Host "No modules found." -ForegroundColor Gray
        return
    }
    else {
        $ModulesCount = $CurrentModules.Count
        Write-Host "$ModulesCount modules found." -ForegroundColor Gray
    }

    # Show status of AllowPrerelease Switch
    if ($AllowPrerelease) {
        Write-Host "Updating installed modules to the latest PreRelease version ..." -ForegroundColor Green
    }
    else {
        Write-Host "Updating installed modules to the latest Production version ..." -ForegroundColor Green
    }

    # Loop through the installed modules and update them if a newer version is available
    $i = 0
    foreach ($Module in $CurrentModules) {
        $i++
        $Counter = "[{0,-$($ModulesCount.ToString().Length)}/{1,-$($ModulesCount.ToString().Length)}]" -f $i, $ModulesCount
        Write-Host ("{0} Checking for updated version of module {1} ..." -f $Counter, $Module.Name) -ForegroundColor Green
        try {
            Update-Module -Name $Module.Name -AllowPrerelease:$AllowPrerelease -AcceptLicense -Scope:AllUsers -Force -ErrorAction Stop
        }
        catch {
            $errorMessage = "Error updating module {0}!" -f $Module.Name
            if ($ShowErrors) {
                $errorMessage += " Error message: {0}" -f $_.Exception.Message
            }
            Write-Host $errorMessage -ForegroundColor Red
        }

        # Retrieve newest version number and remove old(er) version(s) if any
        $AllVersions = Get-InstalledModule -Name $Module.Name -AllVersions | Sort-Object PublishedDate -Descending
        $MostRecentVersion = $AllVersions[0].Version
        if ($AllVersions.Count -gt 1) {
            Foreach ($Version in $AllVersions) {
                if ($Version.Version -ne $MostRecentVersion) {
                    try {
                        Write-Host ("{0} Uninstalling previous version {1} of module {2} ..." -f (' ' * $Counter.Length), $Version.Version, $Module.Name) -ForegroundColor Gray
                        Uninstall-Module -Name $Module.Name -RequiredVersion $Version.Version -Force -ErrorAction Stop
                    }
                    catch {
                        $errorMessage = "Error uninstalling previous version {0} of module {1}!" -f $Version.Version, $Module.Name
                        if ($ShowErrors) {
                            $errorMessage += " Error message: {0}" -f $_.Exception.Message
                        }
                        Write-Warning $errorMessage
                    }
                }
            }
        }
    }

    # Get the new module versions for comparing them to the previous one if updated
    $NewModules = Get-InstalledModule | Select-Object Name, Version | Sort-Object Name
    if ($NewModules) {
        Write-Host "`nList of updated modules:" -ForegroundColor Green
        $NoUpdatesFound = $true
        foreach ($Module in $NewModules) {
            $CurrentVersion = $CurrentModules | Where-Object Name -EQ $Module.Name
            if ($CurrentVersion.Version -notlike $Module.Version) {
                $NoUpdatesFound = $false
                Write-Host ("- Updated module {0} from version {1} to {2}" -f $Module.Name, $CurrentVersion.Version, $Module.Version) -ForegroundColor Green
            }
        }

        if ($NoUpdatesFound) {
            Write-Host "No modules were updated." -ForegroundColor Gray
        }
    }
}
Update-ModuleVersions