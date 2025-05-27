
$moduleList = 
    #"ActiveDirectory",
    "AzureAD",
    #"AzureADPreview",
    #"Dism",
    #"DnsClient",
    #"DnsServer",
    #"DSCParser",
    "ExchangeOnlineManagement",
    #"M365Documentation",
    "Microsoft.Graph",
    "Microsoft.Graph.Beta.Users",
    #"Microsoft.Online.SharePoint.PowerShell",
    #"Microsoft.PowerApps.Administration.PowerShell",
    #"Microsoft.PowerShell.Archive",
    #"Microsoft.PowerShell.Crescendo",
    #"Microsoft.PowerShell.Diagnostics",
    #"Microsoft.PowerShell.Host",
    #"Microsoft.PowerShell.LocalAccounts",
    #"Microsoft.PowerShell.Management",
    #"Microsoft.PowerShell.Operation.Validation",
    #"Microsoft.PowerShell.SecretManagement",
    #"Microsoft.PowerShell.SecretStore",
    #"Microsoft.PowerShell.Security",
    #"Microsoft.PowerShell.Utility",
    #"Microsoft365DSC",
    "MicrosoftTeams",
    "MSOnline",
    #"NetAdapter",
    #"NetConnection",
    #"NetEventPacketCapture",
    #"NetTCPIP",
    #"NetworkConnectivityStatus",
    #"oh-my-posh",
    #"PackageManagement",
    "PowerShellGet",
    "PSReadLine",
    #"WindowsAutoPilotIntune",
    "OSD"

    foreach ($moduleName in $moduleList) {
        if (-not (Get-Module -Name $moduleName -ListAvailable)) {
            # Module is not installed, so install it
            Write-Host -ForegroundColor Green "[+] Installing module $moduleName ..."
            Install-Module -Name $moduleName -Scope Allusers -AllowPrereleas -Force
        }
        else {
            # Module is already installed, so skip it
            Write-Host -ForegroundColor Cyan "[!} Module $moduleName is already installed."
        }
    }