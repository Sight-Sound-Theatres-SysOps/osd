
$ScriptName = '[+] Sight & Sound Windows 11 Pro 24H2 Deployment'
$ScriptVersion = '25.5.26.1'
Write-Host -ForegroundColor Green "$ScriptName $ScriptVersion"

#Variables to define the Windows OS / Edition etc to be applied during OSDCloud
$Product = (Get-MyComputerProduct)
$OSVersion = 'Windows 11' #Used to Determine Driver Pack
$OSReleaseID = '24H2' #Used to Determine Driver Pack
$OSName = 'Windows 11 24H2 x64'
$OSEdition = 'Pro'
$OSActivation = 'Retail'
$OSLanguage = 'en-us'

#Set OSDCloud Vars
$Global:MyOSDCloud = [ordered]@{
    Restart = [bool]$true
    RecoveryPartition = [bool]$true
    OEMActivation = [bool]$True
    WindowsUpdate = [bool]$true
    WindowsUpdateDrivers = [bool]$true
    WindowsDefenderUpdate = [bool]$true
    SetTimeZone = [bool]$false
    ClearDiskConfirm = [bool]$false
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB = [bool]$false
}

#Used to Determine Driver Pack
$DriverPack = Get-OSDCloudDriverPack -Product $Product -OSVersion $OSVersion -OSReleaseID $OSReleaseID

if ($DriverPack){
    $Global:MyOSDCloud.DriverPackName = $DriverPack.Name
}

#write variables to console
Write-Output $Global:MyOSDCloud

#Launch OSDCloud
Write-Host -ForegroundColor Green  "[+] Starting OSDCloud" 

# Ask the user if they want to install the latest version of Windows 11
write-host -ForegroundColor DarkGray "About to run Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage"
$response = Read-Host "Would you Install the latest version of Windows 11 v24H2 on this computer? (Y/N)" 
switch ($response.ToLower()) {
    {'y', 'yes' -contains $_} {
        write-host -ForegroundColor DarkGray "Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage"
        Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage        
        write-host -ForegroundColor Green "[+] OSDCloud Process Complete"
    }
    {'n', 'no' -contains $_} {
        Write-host -ForegroundColor Yellow "[!] Installation cancelled."
    }
    default {
        Write-Host -ForegroundColor Yellow "[!] Invalid input. Please enter Y or N."
    }
}
