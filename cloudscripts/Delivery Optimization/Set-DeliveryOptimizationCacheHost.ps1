<#
.SYNOPSIS
    Configures Windows Delivery Optimization to use DHCP Option 235 for Microsoft Connected Cache discovery.

.DESCRIPTION
    This script sets the DOCacheHostSource registry value to enable automatic discovery of 
    Microsoft Connected Cache (MCC) servers via DHCP Option 235. This allows Windows Update 
    and other Delivery Optimization clients to automatically locate and utilize MCC servers 
    on the network for content caching.

    Registry Path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization
    Registry Key:  DOCacheHostSource
    Value:         1 (DHCP Option 235)

    Setting this value to 1 instructs the Delivery Optimization client to:
    - Query DHCP for Option 235 during network initialization
    - Use the returned IP address(es) as Microsoft Connected Cache servers
    - Fall back to standard Delivery Optimization behavior if Option 235 is not available

.PARAMETER None
    This script does not accept any parameters.

.EXAMPLE
    .\Set-DeliveryOptimizationCacheHost.ps1
    
    Runs the script to configure DHCP-based MCC discovery.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File ".\Set-DeliveryOptimizationCacheHost.ps1"
    
    Runs the script with execution policy bypass (useful for deployment scenarios).

.NOTES
    File Name      : Set-DeliveryOptimizationCacheHost.ps1
    Author         : Matthew Miles
    Prerequisite   : PowerShell 5.1 or higher, Administrator rights
    Exit Codes     : 0 = Success, 1 = Failure
    
    Requirements:
    - Must run with Administrator privileges
    - DHCP Option 235 must be configured on your DHCP server
    - Microsoft Connected Cache server must be deployed and reachable
    
    For more information on Microsoft Connected Cache:
    https://learn.microsoft.com/en-us/windows/deployment/do/waas-microsoft-connected-cache

.LINK
    https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deliveryoptimization

#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param()

# Script Configuration
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
$regName = "DOCacheHostSource"
$regValue = 1  # 1 = DHCP Option 235, 2 = Custom server, 0 = Disabled
$regType = "DWord"

try {
    Write-Verbose "Starting Delivery Optimization configuration..."
    
    # Create the registry path if it doesn't exist
    if (-not (Test-Path $regPath)) {
        Write-Output "Creating registry path: $regPath"
        New-Item -Path $regPath -Force | Out-Null
    }
    else {
        Write-Verbose "Registry path already exists: $regPath"
    }

    # Set the registry value
    Write-Output "Setting $regName to $regValue (DHCP Option 235)"
    New-ItemProperty -Path $regPath -Name $regName -Value $regValue -PropertyType $regType -Force | Out-Null

    # Verify the value was set correctly
    $verifyValue = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop
    
    if ($verifyValue.$regName -eq $regValue) {
        Write-Output "Successfully configured $regName = $regValue"
        Write-Output "Delivery Optimization will now use DHCP Option 235 for MCC discovery"
        exit 0  # Success
    }
    else {
        Write-Warning "Registry value mismatch. Expected: $regValue, Found: $($verifyValue.$regName)"
        exit 1  # Failure
    }
}
catch {
    Write-Error "Failed to configure Delivery Optimization: $_"
    Write-Output "Error Details: $($_.Exception.Message)"
    exit 1  # Failure
}