#Requires -RunAsAdministrator

# To determine witch RSAT tools are available:
Get-WindowsCapability -Name RSAT* -Online | Select-Object -Property DisplayName, State