#Requires -RunAsAdministrator

# Install AD RSAT Tools:

$RSAT = Get-WindowsCapability -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -Online | Select-Object -Property State

if ($RSAT.State -eq "Installed") {
    Write-Host -ForegroundColor Green "[+] RSAT tool is already installed."
} else {
    Write-Host -ForegroundColor Yellow "[-] RSAT tool is not installed. Installing now..."
    Add-WindowsCapability -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -Online
}
