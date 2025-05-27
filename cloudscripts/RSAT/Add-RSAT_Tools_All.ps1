#Requires -RunAsAdministrator

# To install all RSAT Tools:
Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online