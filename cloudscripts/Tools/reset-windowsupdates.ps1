# Reset-WindowsUpdate.ps1
# Author: Matthew Miles
# Description: Resets Windows Update client settings to default.

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as an Administrator."
    exit
}

# Stop Windows Update service
Stop-Service -Name wuauserv

# Delete SoftwareDistribution folder
Remove-Item -Path C:\Windows\SoftwareDistribution -Recurse -Force

# Reset BITS service
Stop-Service -Name BITS
Start-Service -Name BITS

# Reset registry keys related to Windows Update
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name AccountDomainSid -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name PingID -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name SusClientId -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name SusClientIDValidation -ErrorAction SilentlyContinue

# Restart Windows Update service
Start-Service -Name wuauserv

Write-Host "Windows Update client settings have been reset."

# Reboot the system (optional)
# Restart-Computer -Force