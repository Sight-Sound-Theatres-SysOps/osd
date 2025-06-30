[CmdletBinding()]
param()
$ScriptName = 'oobeFunctions.sight-sound.dev'
$ScriptVersion = '25.6.30.1'

#region Initialize
if ($env:SystemDrive -eq 'X:') {
    $WindowsPhase = 'WinPE'
}
else {
    $ImageState = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction Ignore).ImageState
    if ($env:UserName -eq 'defaultuser0') {$WindowsPhase = 'OOBE'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE') {$WindowsPhase = 'Specialize'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_AUDIT') {$WindowsPhase = 'AuditMode'}
    else {$WindowsPhase = 'Windows'}
}

Write-Host -ForegroundColor Green "[+] $ScriptName $ScriptVersion ($WindowsPhase Phase)"
#endregion

$Global:oobeCloud = @{
    oobeRemoveAppxPackageName = @(
        # '9NHT9RB2F4HD', # Microsoft Copilot
        'Clipchamp.Clipchamp',
        'Microsoft.BingNews',
        'Microsoft.BingWeather',
        'Microsoft.GamingApp',
        'Microsoft.GetHelp',
        'Microsoft.Getstarted',
        'Microsoft.Messaging',
        'Microsoft.Microsoft3DViewer',
        'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.MixedReality.Portal',
        # 'Microsoft.MSPaint',
        'Microsoft.News',
        'Microsoft.OneConnect',
        'Microsoft.People',
        'Microsoft.PowerAutomateDesktop',
        'Microsoft.Print3D',
        'Microsoft.SkypeApp',
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.WindowsMaps',
        'Microsoft.Xbox.TCUI',
        'Microsoft.XboxApp',
        'Microsoft.XboxGameOverlay',
        'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxIdentityProvider',
        'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.YourPhone',
        'Microsoft.ZuneMusic',
        'Microsoft.ZuneVideo',
        'MicrosoftCorporationII.MicrosoftFamily',
        'MicrosoftCorporationII.QuickAssist',
        'MicrosoftTeams',
        'microsoft.windowscommunicationsapps'
    )
}

#=================================================
#   oobeFunctions
#=================================================

function Step-installCertificates {

    # Define an array of certificates to install
    $certs = @(
        @{
            Name        = "Cisco Umbrella"
            Url         = "https://ssintunedata.blob.core.windows.net/cert/Cisco_Umbrella_Root_CA.cer"
            FileName    = "Cisco_Umbrella_Root_CA.cer"
            IssuerMatch = "*Cisco Umbrella*"
        },
        @{
            Name        = "ST-CA"
            Url         = "https://ssintunedata.blob.core.windows.net/cert/24-st-ca.cer"
            FileName    = "24-ST-CA.cer"
            IssuerMatch = "*ST-CA*"
        },
        @{
            Name        = "SST-ROOT-CA"
            Url         = "https://ssintunedata.blob.core.windows.net/cert/SST-ROOT-CA.crt"
            FileName    = "SST-ROOT-CA.crt"
            IssuerMatch = "*SST-ROOT-CA*"
        }
        # To add another certificate, add another hashtable here.
    )

    # Set the directory where certificates will be temporarily stored
    $certDirectory = "C:\OSDCloud\Temp"

    # Ensure the directory exists
    if (-not (Test-Path -Path $certDirectory)) {
        Write-Host -ForegroundColor Yellow "[-] Directory $certDirectory does not exist. Creating it..."
        New-Item -Path $certDirectory -ItemType Directory | Out-Null
    }

    # Loop through each certificate definition
    foreach ($cert in $certs) {

        # Check if the certificate is already installed by matching the issuer name
        $certExists = Get-ChildItem -Path 'Cert:\LocalMachine\Root\' |
                      Where-Object { $_.Issuer -like $cert.IssuerMatch }

        if ($certExists) {
            Write-Host -ForegroundColor Green "[+] $($cert.Name) root certificate is already installed"
        }
        else {
            Write-Host -ForegroundColor Yellow "[-] Installing $($cert.Name) root certificate"

            # Define the full file path for the downloaded certificate
            $certFile = Join-Path -Path $certDirectory -ChildPath $cert.FileName

            # Download the certificate
            Invoke-WebRequest -Uri $cert.Url -OutFile $certFile

            # Load the certificate from the file
            $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $Certificate.Import($certFile)

            # Open the local machine Root store in ReadWrite mode, add the certificate, then close the store
            $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
            $Store.Open("ReadWrite")
            $Store.Add($Certificate)
            $Store.Close()

            # Clean up the downloaded file
            Remove-Item $certFile -Force
        }
    }
}
    function Step-oobeInstallModuleGetWindowsAutopilotInfoCommunity {
        [CmdletBinding()]
        param ()
            # Install the get-windowsautopilotinfocommunity script
            Install-Script Get-WindowsAutopilotInfo -Force
            Install-Script Get-AutopilotDiagnosticsCommunity -Force    
    
            # Define the options for the GroupTag parameter
            $GroupTagOptions = @("Development", "Enterprise","MTR-")
    
            # Display the menu for the GroupTag parameter
            Write-Host "Select a GroupTag:" -ForegroundColor Yellow        
            for ($i = 0; $i -lt $GroupTagOptions.Count; $i++) {
                Write-Host "[$($i + 1)]" -ForegroundColor White -NoNewline
                Write-Host " $($GroupTagOptions[$i])" -ForegroundColor DarkCyan
            }
            $GroupTagChoice = Read-Host "Enter your choice"
            $GroupTag = $GroupTagOptions[$GroupTagChoice - 1]
    
            # If GroupTag is MTR-, prompt for room name
            if ($GroupTag -eq "MTR-") {
                Write-Host "Enter the room name (e.g., BR The Garden): " -ForegroundColor Yellow -NoNewline
                $RoomName = Read-Host
    
                # Remove spaces from the room name
                $RoomName = $RoomName -replace '\s+', ''
    
                # Append the formatted room name to the GroupTag
                $GroupTag = $GroupTag + $RoomName
            }
    
            # Prompt the user to enter a value for the AssignedComputerName parameter
            do {
                Write-Host "Enter the AssignedComputerName ex XXWIN-EID-XXXX (15 characters or less): " -ForegroundColor Yellow -NoNewline
                $AssignedComputerName = (Read-Host).ToUpper()
                if ($AssignedComputerName.Length -gt 15) {
                    Write-Host "WARNING: AssignedComputerName must be 15 characters or less" -ForegroundColor Yellow
                }
            } while ($AssignedComputerName.Length -gt 15)
    
            # Define the options for the AddToGroup parameter using the group names directly
            $AddToGroupOptions = @(
                "Autopilot_Devices-GeneralUsers",
                "Autopilot_Devices-Box_CC",
                "AutoPilot_Devices-Retail",
                "Autopilot_Devices-CenterStageKiosk",
                "Autopilot_Devices-SharedDevice",
                "AutoPilot_Devices-TeamsRooms"
            )
    
            # Display the menu for the AddToGroup parameter
            Write-Host "Select an AddToGroup option:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $AddToGroupOptions.Count; $i++) {
                Write-Host "[$($i + 1)]" -ForegroundColor White -NoNewline
                Write-Host " $($AddToGroupOptions[$i])" -ForegroundColor DarkCyan
            }
    
            $AddToGroupChoice = Read-Host "Enter your choice"
            $AddToGroup = $AddToGroupOptions[$AddToGroupChoice - 1]
    
            # Output the selected AddToGroup value for verification
            Write-Host "Tag: $GroupTag - Computer Name: $AssignedComputerName - Group: $AddToGroup" -ForegroundColor Green
    
            # Call the get-windowsautopilotinfo.ps1 script with the specified parameters
            get-windowsautopilotinfo.ps1 -Assign -GroupTag $GroupTag -AssignedComputerName $AssignedComputerName -AddToGroup $AddToGroup -online
    }

function Step-oobeRegisterAutopilot {
    [CmdletBinding()]
    param (
        [System.String]
        $Command
    )    
        # Display a pop-up asking for user confirmation
        $caption = "Register Device with Autopilot?"
        $message = "Would you like to register this device with Autopilot?"
        $options = [System.Windows.Forms.MessageBoxButtons]::YesNo
        $result = [System.Windows.Forms.MessageBox]::Show($message, $caption, $options, [System.Windows.Forms.MessageBoxIcon]::Question)
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Host -ForegroundColor Yellow "[-] Registering Device in Autopilot using get-WindowsAutoPilotInfo"
            #Step-oobeInstallModuleGetWindowsAutopilotInfoCommunity
            Step-oobeAutoPilotAppRegisteration
        }
        else {
            Write-Host -ForegroundColor Cyan "[!] Device registration with Autopilot skipped."
            return
        }
    }
    function Step-oobeAutoPilotAppRegisteration {
        [CmdletBinding()]
        param ()
    
        # Install the get-windowsautopilotinfocommunity script
        Install-Script Get-WindowsAutopilotInfo -Force
        Install-Script Get-AutopilotDiagnosticsCommunity -Force    
    
        # Loop until options are confirmed
        $optionsConfirmed = $false
        while (-not $optionsConfirmed) {
            # Define the options for the GroupTag parameter
            $GroupTagOptions = @("Development", "Enterprise", "MTR-")
    
            # Display the menu for the GroupTag parameter
            Write-Host "Select a GroupTag:" -ForegroundColor Yellow        
            for ($i = 0; $i -lt $GroupTagOptions.Count; $i++) {
                Write-Host "[$($i + 1)]" -ForegroundColor White -NoNewline
                Write-Host " $($GroupTagOptions[$i])" -ForegroundColor DarkCyan
            }
            $GroupTagChoice = Read-Host "Enter your choice"
            $GroupTag = $GroupTagOptions[$GroupTagChoice - 1]
    
            # If GroupTag is MTR-, prompt for room name
            if ($GroupTag -eq "MTR-") {
                Write-Host "Enter the room name (e.g., BR The Garden): " -ForegroundColor Yellow -NoNewline
                $RoomName = Read-Host
                $RoomName = $RoomName -replace '\s+', ''
                $GroupTag = $GroupTag + $RoomName
            }
    
            # Prompt the user to enter a value for the AssignedComputerName parameter
            do {
                Write-Host "Enter the AssignedComputerName ex XXWIN-EID-XXXX (15 characters or less): " -ForegroundColor Yellow -NoNewline
                $AssignedComputerName = (Read-Host).ToUpper()
                if ($AssignedComputerName.Length -gt 15) {
                    Write-Host "WARNING: AssignedComputerName must be 15 characters or less" -ForegroundColor Yellow
                }
            } while ($AssignedComputerName.Length -gt 15)
    
            # Define the options for the AddToGroup parameter using the group names directly
            $AddToGroupOptions = @(
                "Autopilot_Devices-GeneralUsers",
                "Autopilot_Devices-Box_CC",
                "AutoPilot_Devices-Retail",
                "Autopilot_Devices-CenterStageKiosk",
                "Autopilot_Devices-SharedDevice",
                "AutoPilot_Devices-TeamsRooms"
            )
    
            # Display the menu for the AddToGroup parameter
            Write-Host "Select an AddToGroup option:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $AddToGroupOptions.Count; $i++) {
                Write-Host "[$($i + 1)]" -ForegroundColor White -NoNewline
                Write-Host " $($AddToGroupOptions[$i])" -ForegroundColor DarkCyan
            }
    
            $AddToGroupChoice = Read-Host "Enter your choice"
            $AddToGroup = $AddToGroupOptions[$AddToGroupChoice - 1]
    
            # Output the selected values for verification
            Write-Host "Selected options:" -ForegroundColor Green
            Write-Host "Tag: $GroupTag - Computer Name: $AssignedComputerName - Group: $AddToGroup" -ForegroundColor Green
    
            # Ask for confirmation
            $confirmation = Read-Host "Are these options correct? (Y/N)"
            $optionsConfirmed = $confirmation -eq 'Y' -or $confirmation -eq 'y'
    
            if (-not $optionsConfirmed) {
                Write-Host "Please re-enter the options." -ForegroundColor Yellow
            }
        }
    
        # Define the URL and temporary file path
        $blobUrl = "https://ssintunedata.blob.core.windows.net/autopilot/autopilot.json.enc"
        $tempFile = "$env:TEMP\autopilot.json.enc"
    
        # Download the encrypted file from Blob Storage
        try {
            Invoke-WebRequest -Uri $blobUrl -OutFile $tempFile -ErrorAction Stop
        } catch {
            Write-Error "Failed to download file from $blobUrl : $_"
            return
        }
    
        # Passphrase retry loop
        $maxAttempts = 3
        $attempt = 1
        $decryptedSuccessfully = $false
    
        while (-not $decryptedSuccessfully -and $attempt -le $maxAttempts) {
            # Prompt for passphrase
            $passphrase = Read-Host "Enter the passphrase to enroll the device (Attempt $attempt of $maxAttempts)" -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passphrase)
            $plainPassphrase = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    
            # Decrypt the file
            try {
                $encryptedBytesWithSaltAndIV = [System.IO.File]::ReadAllBytes($tempFile)
                $salt = $encryptedBytesWithSaltAndIV[0..15]
                $iv = $encryptedBytesWithSaltAndIV[16..31]
                $encryptedBytes = $encryptedBytesWithSaltAndIV[32..($encryptedBytesWithSaltAndIV.Length - 1)]
    
                $aes = [System.Security.Cryptography.Aes]::Create()
                $aes.KeySize = 256
                $aes.BlockSize = 128
                $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    
                $passphraseBytes = [System.Text.Encoding]::UTF8.GetBytes($plainPassphrase)
                $keyDerivation = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passphraseBytes, $salt, 100000)
                $aes.Key = $keyDerivation.GetBytes(32)
                $aes.IV = $iv
    
                $decryptor = $aes.CreateDecryptor()
                $memoryStream = New-Object System.IO.MemoryStream
                $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($memoryStream, $decryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
    
                $cryptoStream.Write($encryptedBytes, 0, $encryptedBytes.Length)
                $cryptoStream.FlushFinalBlock()
    
                $decryptedBytes = $memoryStream.ToArray()
                $decryptedText = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    
                $cryptoStream.Close()
                $memoryStream.Close()
                $aes.Dispose()
    
                # Parse the decrypted JSON
                $jsonContent = $decryptedText | ConvertFrom-Json
                $TenantID = $jsonContent.TenantID
                $appID = $jsonContent.appid
                $appsecret = $jsonContent.appsecret
                Write-Host "[+] Successfully extracted tenant information" -ForegroundColor Green
                $decryptedSuccessfully = $true
            } catch {
                Write-Host "Decryption or parsing failed (possibly incorrect passphrase). Please try again." -ForegroundColor Yellow
                $attempt++
            } finally {
                # Clean up passphrase from memory
                if ($bstr) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
                if (Get-Variable -Name plainPassphrase -ErrorAction SilentlyContinue) {
                    Remove-Variable -Name plainPassphrase -Force
                }
            }
        }
    
        # Clean up the temporary file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    
        # Check if decryption succeeded
        if (-not $decryptedSuccessfully) {
            Write-Error "Failed to decrypt after $maxAttempts attempts. Exiting."
            return
        }
    
        # Call the get-windowsautopilotinfo.ps1 script with the additional parameters
        get-windowsautopilotinfo.ps1 -Assign -GroupTag $GroupTag -AssignedComputerName $AssignedComputerName -AddToGroup $AddToGroup -online -TenantID $TenantID -appID $appID -appsecret $appsecret
    }

function Step-oobeRemoveAppxPackage {
    
        Write-Host -ForegroundColor Yellow "[-] Removing Appx Packages"
        foreach ($Item in $Global:oobeCloud.oobeRemoveAppxPackageName) {
            if (Get-Command Get-AppxProvisionedPackage) {
                Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -Match $Item} | ForEach-Object {
                    Write-Host -ForegroundColor DarkGray $_.DisplayName
                    if ((Get-Command Remove-AppxProvisionedPackage).Parameters.ContainsKey('AllUsers')) {
                        Try
                        {
                            $null = Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $_.PackageName
                        }
                        Catch
                        {
                            Write-Warning "AllUsers Appx Provisioned Package $($_.PackageName) did not remove successfully"
                        }
                    }
                    else {
                        Try
                        {
                            $null = Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName
                        }
                        Catch
                        {
                            Write-Warning "Appx Provisioned Package $($_.PackageName) did not remove successfully"
                        }
                    }
                }
            }
        }
    }
function Step-oobeRemoveAppxPackageAllUsers {

    Write-Host -ForegroundColor Yellow "[-] Removing Appx Packages"
    foreach ($Item in $Global:oobeCloud.oobeRemoveAppxPackageName) {
        if (Get-Command Get-AppxProvisionedPackage) {
            Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -Match $Item} | ForEach-Object {
                Write-Host -ForegroundColor DarkGray $_.DisplayName
                Try
                {
                    $null = Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $_.PackageName
                }
                Catch
                {
                    Write-Warning "AllUsers Appx Provisioned Package $($_.PackageName) did not remove successfully"
                }
            }
        }
    }
}
function Step-oobeSetUserRegSettings {
    [CmdletBinding()]
    param ()
    
    # Load Default User Profile hive (ntuser.dat)
    Write-host -ForegroundColor Yellow "[-] Setting default users registry settings ..."
    $DefaultUserProfilePath = "$env:SystemDrive\Users\Default\NTUSER.DAT"
    REG LOAD "HKU\Default" $DefaultUserProfilePath | Out-Null

    # Changes to Default User Registry

    Write-host -ForegroundColor DarkGray "[-] Show known file extensions" 
    REG ADD "HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f | Out-Null

    Write-host -ForegroundColor DarkGray "[-] Change default Explorer view to This PC"
    REG ADD "HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "LaunchTo" /t REG_DWORD /d 1 /f | Out-Null

    Write-host -ForegroundColor DarkGray "[-] Show User Folder shortcut on desktop"
    REG ADD "HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" /v "{59031a47-3f72-44a7-89c5-5595fe6b30ee}" /t REG_DWORD /d 0 /f | Out-Null
    REG ADD "HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" /v "{59031a47-3f72-44a7-89c5-5595fe6b30ee}" /t REG_DWORD /d 0 /f | Out-Null

    Write-host -ForegroundColor DarkGray "[-] Show This PC shortcut on desktop"
    REG ADD "HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f | Out-Null
    REG ADD "HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f | Out-Null

    Write-host -ForegroundColor DarkGray "[-] Show item checkboxes"
    REG ADD "HKU\Default\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "AutoCheckSelect" /t REG_DWORD /d 1 /f | Out-Null

    #Write-host -ForegroundColor DarkGray "[-] Disable Chat on Taskbar"
    #REG ADD "HKU\Default\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarMn" /t REG_DWORD /d 0 /f | Out-Null  
    
    #Write-host -ForegroundColor DarkGray "[-] Disable widgets on Taskbar"
    #REG ADD "HKU\Default\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarDa" /t REG_DWORD /d 0 /f | Out-Null   
    
    Write-host -ForegroundColor DarkGray "[-] Disable Windows Spotlight on lockscreen"
    REG ADD "HKU\Default\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsSpotlightFeatures" /t REG_DWORD /d 1 /f | Out-Null

    Write-host -ForegroundColor DarkGray "[-] Stop Start menu from opening on first logon"
    REG ADD "HKU\Default\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "StartShownOnUpgrade" /t REG_DWORD /d 1 /f | Out-Null

    Write-Host -ForegroundColor DarkGreen "[+] Unloading the default user registry hive"
    REG UNLOAD "HKU\Default" | Out-Null
    }

function Step-oobeSetDeviceRegSettings {
    [CmdletBinding()]
    param ()
    
    Write-host -ForegroundColor Yellow "[-] Setting default machine registry settings ..."

    Write-host -ForegroundColor DarkGray "[-] Disable IPv6 on all adapters"

        Set-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6 -Enabled $false -ErrorAction SilentlyContinue

    Write-host -ForegroundColor DarkGray "[-] Disable firstlogon animation"

        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableFirstLogonAnimation" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "EnableFirstLogonAnimation" -Value 0 -Type DWord -ErrorAction SilentlyContinue

    Write-host -ForegroundColor DarkGray "[-] Autoset time zone"

        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name Value -Value "Allow" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name start -Value "3" -ErrorAction SilentlyContinue

    Write-Host -ForegroundColor DarkGray "[-] Setting start menu items"
        
        if (-Not (Test-Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start")) {
            New-Item -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Force -ErrorAction SilentlyContinue | Out-Null
        }            
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderDocuments" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderDocuments_ProviderSet" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderDownloads" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderDownloads_ProviderSet" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderPictures" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderPictures_ProviderSet" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderFileExplorer" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderFileExplorer_ProviderSet" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderSettings" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\Start" -Name "AllowPinnedFolderSettings_ProviderSet" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    Write-Host -ForegroundColor DarkGray "[-] Disabling News and Interests"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests" -Name "value" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            
    Write-Host -ForegroundColor DarkGray "[-] Disabling Windows Feeds"
        if (-Not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Type DWord -ErrorAction SilentlyContinue

    Write-Host -ForegroundColor DarkGray "[-] Setting NumLock to on by default at lockscreen"
        REG ADD "HKU\.DEFAULT\Control Panel\Keyboard" /v "InitialKeyboardIndicators" /t REG_SZ /d "2" /f | Out-Null
    }

function Step-oobeCreateLocalUser {
    [CmdletBinding()]
    param ()
    
    $Username = "ssLocalAdmin"

    # Check if the user already exists
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Host -ForegroundColor Yellow "[-] Creating local user - $Username"
    
        # Generate a random password of 16 characters
        function Generate-RandomPassword {
            $validCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?/"
            $passwordLength = 32
            $random = New-Object System.Random
            $password = 1..$passwordLength | ForEach-Object { $validCharacters[$random.Next(0, $validCharacters.Length)] }
            return $password -join ''
        }
    
        $Password = Generate-RandomPassword
        $NeverExpire = $true
        $UserParams = @{
            "Name"                  = $Username
            "Password"              = (ConvertTo-SecureString -AsPlainText $Password -Force)
            "UserMayNotChangePassword" = $true
            "PasswordNeverExpires"  = $NeverExpire
        }
    
        # Create the user
        New-LocalUser @UserParams | Out-Null
    
        Write-Host -ForegroundColor DarkGray "[+] User '$Username' has been created with password: $Password"
    
        # Add the user to the Administrators group
        Add-LocalGroupMember -Group "Administrators" -Member $Username
    } else {
        Write-Host -ForegroundColor Green "[+] User '$Username' already exists."
    }
    
    }

    function Step-desktopWallpaper {
        [CmdletBinding()]
        param ()
        
        $scriptDirectory = "C:\OSDCloud\Scripts"
        $scriptPath = "C:\OSDCloud\Scripts\set-desktopWallpaper.ps1"
    
        # Check if the directory exists, if not, create it
        if (-Not (Test-Path -Path $scriptDirectory)) {
            Write-Host -ForegroundColor Yellow "[-] Directory $scriptDirectory does not exist. Creating it..."
            New-Item -Path $scriptDirectory -ItemType Directory | Out-Null
        }
    
        if (Test-Path $scriptPath) {
            Write-Host -ForegroundColor Green "[+] Replacing default wallpaper and lockscreen images"
        } else {
            Write-Host -ForegroundColor Yellow "[-] Replacing default wallpaper and lockscreen images"
            # Download the script
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/set-lockScreen_Wallpaper.ps1 -OutFile $scriptPath
            # Execute the script
            & $scriptPath -ErrorAction SilentlyContinue
        }
    }
    

    function Step-InstallM365Apps {
        [CmdletBinding()]
        param (
            [System.String]
            $Command
        )
        
        $scriptDirectory = "C:\OSDCloud\Scripts"
        $scriptPath = "C:\OSDCloud\Scripts\InstallM365Apps.ps1"
        $skippedPath = "c:\osdcloud\scripts\m365appinstallskipped.txt"
    
        # Check if the directory exists, if not, create it
        if (-Not (Test-Path -Path $scriptDirectory)) {
            Write-Host -ForegroundColor Yellow "[-] Directory $scriptDirectory does not exist. Creating it..."
            New-Item -Path $scriptDirectory -ItemType Directory | Out-Null
        }
    
        if (Test-Path $scriptPath) {
            Write-Host -ForegroundColor Green "[+] M365 Applications Installed"
            return
        }
    
        if (Test-Path $skippedPath) {
            Write-Host -ForegroundColor Cyan "[!] Installation of M365 office applications skipped."
            return
        }
    
        # Display a pop-up asking for user confirmation
        $caption = "Install M365 Apps?"
        $message = "Would you like to install the M365 Office Applications?"
        $options = [System.Windows.Forms.MessageBoxButtons]::YesNo
        $result = [System.Windows.Forms.MessageBox]::Show($message, $caption, $options, [System.Windows.Forms.MessageBoxIcon]::Question)
    
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Host -ForegroundColor Yellow "[-] Installing M365 Applications"
            # Download the script
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/functions/InstallM365Apps.ps1 -OutFile $scriptPath
            # Execute the script
            & $scriptPath -XMLURL "https://raw.githubusercontent.com/Sight-Sound-Theatres-SysOps/osd/main/supportFiles/MicrosoftOffice/configuration.xml" -ErrorAction SilentlyContinue
        }
        else {
            Write-Host -ForegroundColor Cyan "[!] Installation of M365 office applications skipped."
            New-Item -ItemType File -Path $skippedPath | Out-Null
            return
        }
    }
    
function Step-oobeRestartComputer {
    [CmdletBinding()]
    param ()        
        # Removing downloaded content
        Write-Host -ForegroundColor Yellow "[!] Cleaning up... Removing temperary directories"
        if (Test-Path "C:\osdcloud" -PathType Container) { Remove-Item "C:\osdcloud" -Force -Recurse }
        if (Test-Path "C:\Drivers" -PathType Container) { Remove-Item "C:\Drivers" -Force -Recurse }
        if (Test-Path "C:\Dell" -PathType Container) { Remove-Item "C:\Dell" -Force -Recurse }
        #if (Test-Path "C:\Temp" -PathType Container) { Remove-Item "C:\Temp" -Force -Recurse }
        Write-Host -ForegroundColor Green '[+] Build Complete!'
        Write-Warning 'Device will restart in 30 seconds.  Press Ctrl + C to cancel'
        Stop-Transcript
        Start-Sleep -Seconds 30
        Restart-Computer
    }
function Step-oobeDellDCU {
    [CmdletBinding()]
    param ()

    # Check if the system is a Dell
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computerSystem.Manufacturer -notmatch "Dell") {
        Write-Host -ForegroundColor Cyan "[!] This is not a Dell system, your running a" $computerSystem.Manufacturer $computerSystem.Model 
        return
    } 

    Write-Host -ForegroundColor Yellow "[-] Dell system detected"

        $Manufacturer = (Get-CimInstance -Class:Win32_ComputerSystem).Manufacturer
        $Model = (Get-CimInstance -Class:Win32_ComputerSystem).Model
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
        
        write-output "Manufacturer:    $Manufacturer"
        write-output "Model:           $Model"
        write-output "SystemSKUNumber: $SystemSKUNumber"

    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/gwblok/garytown/refs/heads/master/hardware/Dell/CommandUpdate/EMPS/Dell-EMPSps1')

    # Dell system confirmed; check if Dell Command Update is already installed.
    if ((Test-Path 'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe') -or (Test-Path 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe')) {
        Write-Host -ForegroundColor Green "[+] Dell Command Update is already installed."
        Invoke-DCU -applyUpdates -reboot Disable
    } else {            
        # Ensure winget is available.
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Error "winget is not available on this system."
            return
        }

        Write-Host -ForegroundColor Yellow "[-] Installing Dell Command Update"

        # Install Dell Command Update via winget.
        winget install Dell.CommandUpdate --accept-source-agreements --accept-package-agreements

        Write-Host -ForegroundColor Green "[+] Dell Command Update installed successfully."
        Write-Host -ForegroundColor Yellow "[-] Applying updates with Dell Command Update."
        Invoke-DCU -applyUpdates -reboot Disable
        Write-Host -ForegroundColor Green "[+] Dell Command Update updates applied successfully."
    }
}    
    
function Step-oobeSetDateTime {
    [CmdletBinding()]
    param ()    
        Write-Host -ForegroundColor Yellow 'Verify the Date and Time is set properly including the Time Zone'
        Write-Host -ForegroundColor Yellow 'If this is not configured properly, Certificates and Autopilot may fail'
        Start-Process 'ms-settings:dateandtime' | Out-Null
        $ProcessId = (Get-Process -Name 'SystemSettings').Id
        if ($ProcessId) {
            Wait-Process $ProcessId
        }
    }
    function step-InstallWinget {
        [CmdletBinding()]
        param (
            [string]$Locate = "en-US"  # Default locale to en-US if not specified
        )
    
        # Step 1: Set system locale to the specified value
        Write-Host -ForegroundColor Yellow "[-] Setting system locale to $Locate"
        try {
            Set-WinSystemLocale -SystemLocale $Locate -ErrorAction Stop
            Set-Culture -CultureInfo $Locate -ErrorAction Stop
            Write-Host -ForegroundColor Green "[+] System locale set to $Locate"
        }
        catch {
            Write-Host -ForegroundColor Red "[!] Failed to set system locale: $_"
            # Silently continue to the next step
        }
    
        # Step 2: Install/upgrade WinGet using the Microsoft.Winget.Client module
        Write-Host -ForegroundColor Yellow "[-] Installing / upgrading winget"
        try {
            Import-Module -Name Microsoft.Winget.Client -ErrorAction Stop
            Repair-WingetPackageManager -Force -Latest -ErrorAction Stop
            Write-Host -ForegroundColor Green "[+] WinGet installed/upgraded successfully"
        }
        catch {
            Write-Host -ForegroundColor Red "[!] Failed to install/upgrade WinGet: $_"
            # Silently continue to the next step
        }
    
        # Step 3: Upgrade all packages with winget
        Write-Host -ForegroundColor Yellow "[-] Upgrading winget packages"
        try {
            #winget upgrade --all --accept-source-agreements --accept-package-agreements 
            if ($LASTEXITCODE -eq 0) {
                Write-Host -ForegroundColor Green "[+] winget packages upgraded"
            }
            else {
                Write-Host -ForegroundColor Yellow "[!] winget upgrade exited with code $LASTEXITCODE"
            }
        }
        catch {
            Write-Host -ForegroundColor Red "[!] Failed to upgrade winget packages: $_"
            # Silently continue to the next step
        }
    }
function step-setTimeZoneFromIP {
    [CmdletBinding()]
    param ()

    Write-Host -ForegroundColor Yellow "[-] Attempting to set time zone based on IP address"

    # Try to synchronize system time before making the API call
    try {
        Write-Host -ForegroundColor Yellow "[-] Synchronizing system time with time server"
        w32tm /resync | Out-Null
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Warning "Failed to synchronize system time. Proceeding anyway."
    }

    # Method 1: Use a more reliable API (ipapi.co) to fetch the time zone
    $URIRequest = "https://ipapi.co/json/"
    $TimeZoneAPI = $null
    try {
        Write-Host -ForegroundColor Yellow "[-] Fetching time zone from ipapi.co"
        $Response = Invoke-WebRequest -Uri $URIRequest -UseBasicParsing -ErrorAction Stop
        $TimeZoneAPI = ($Response.Content | ConvertFrom-Json).timezone
    }
    catch {
        Write-Warning "Failed to fetch time zone from $URIRequest. Error: $($_.Exception.Message)"
    }

    # Method 2: Fallback to Windows Location Services if API fails
    if (-not $TimeZoneAPI) {
        Write-Host -ForegroundColor Yellow "[-] API failed, attempting to use Windows Location Services for time zone detection"
        try {
            # Ensure location services are enabled
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Allow" -ErrorAction Stop
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name "Start" -Value 3 -ErrorAction Stop
            Start-Service -Name "tzautoupdate" -ErrorAction Stop

            # Wait for the service to update the time zone
            Start-Sleep -Seconds 5

            # Get the current time zone
            $CurrentTimeZone = (Get-TimeZone).Id
            Write-Host -ForegroundColor Green "[+] Time zone detected via Windows Location Services: $CurrentTimeZone"
            return  # Exit the function since we've set the time zone
        }
        catch {
            Write-Warning "Failed to use Windows Location Services for time zone detection. Error: $($_.Exception.Message)"
            Write-Host -ForegroundColor Yellow "[-] Using default time zone as fallback"
            Set-TimeZone -Id "Eastern Standard Time"
            Write-Host -ForegroundColor Green "[+] Time zone set to Eastern Standard Time as fallback"
            return
        }
    }

    # Define the mapping for API time zones to Windows time zones
    $WindowsTimeZones = @{
        # Eastern Time Zone
        "America/New_York" = "Eastern Standard Time"
        "America/Detroit" = "Eastern Standard Time"
        "America/Kentucky/Louisville" = "Eastern Standard Time"
        "America/Indiana/Indianapolis" = "Eastern Standard Time"
        "America/Indiana/Vincennes" = "Eastern Standard Time"
        "America/Indiana/Winamac" = "Eastern Standard Time"
        "America/Indiana/Marengo" = "Eastern Standard Time"
        "America/Indiana/Petersburg" = "Eastern Standard Time"
        "America/Indiana/Vevay" = "Eastern Standard Time"
    
        # Central Time Zone
        "America/Chicago" = "Central Standard Time"
        "America/North_Dakota/Center" = "Central Standard Time"
        "America/North_Dakota/Beulah" = "Central Standard Time"
        "America/North_Dakota/New_Salem" = "Central Standard Time"
        "America/Menominee" = "Central Standard Time"
        "America/Indiana/Tell_City" = "Central Standard Time"
        "America/Indiana/Knox" = "Central Standard Time"
    
        # Mountain Time Zone
        "America/Denver" = "Mountain Standard Time"
        "America/Boise" = "Mountain Standard Time"
        "America/Shiprock" = "Mountain Standard Time"
        "America/Phoenix" = "US Mountain Standard Time"  # Does not observe DST
    
        # Pacific Time Zone
        "America/Los_Angeles" = "Pacific Standard Time"
        "America/Vancouver" = "Pacific Standard Time"
    
        # Alaska Time Zone
        "America/Anchorage" = "Alaskan Standard Time"
        "America/Metlakatla" = "Alaskan Standard Time"  # Approximation
    
        # Hawaii-Aleutian Time Zone
        "Pacific/Honolulu" = "Hawaiian Standard Time"  # Does not observe DST
        "America/Adak" = "Hawaiian Standard Time"  # Approximation, Adak observes DST
    
        # US Territories
        "America/Puerto_Rico" = "SA Western Standard Time"  # UTC-4, no DST
        "Pacific/Guam" = "West Pacific Standard Time"  # UTC+10
        "Pacific/Pago_Pago" = "UTC-11:00"  # American Samoa
    }

    # Check if the timezone exists in the mapping
    if ($WindowsTimeZones.ContainsKey($TimeZoneAPI)) {
        $WindowsTimeZone = $WindowsTimeZones[$TimeZoneAPI]
        try {
            Set-TimeZone -Id $WindowsTimeZone -ErrorAction Stop
            Write-Host -ForegroundColor Green "[+] Time zone has been updated to - $WindowsTimeZone"
        }
        catch {
            Write-Warning "Failed to set time zone to $WindowsTimeZone. Error: $($_.Exception.Message)"
            Write-Host -ForegroundColor Yellow "[-] Using default time zone as fallback"
            Set-TimeZone -Id "Eastern Standard Time"
            Write-Host -ForegroundColor Green "[+] Time zone set to Eastern Standard Time as fallback"
        }
    }
    else {
        Write-Warning "Time zone '$TimeZoneAPI' not found in the mapping. Using default time zone."
        Set-TimeZone -Id "Eastern Standard Time"
        Write-Host -ForegroundColor Green "[+] Time zone set to Eastern Standard Time as fallback"
    }
}
function step-SetExecutionPolicy {
    [CmdletBinding()]
    param ()
        if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'RemoteSigned') {
            Write-Host -ForegroundColor Yellow "[-] Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
            Set-ExecutionPolicy RemoteSigned -Force -Scope CurrentUser
        }
        else {
            Write-Host -ForegroundColor Green "[+] Get-ExecutionPolicy RemoteSigned [CurrentUser]"
        }
}
function step-SetPowerShellProfile {
    [CmdletBinding()]
    param ()

    $oobePowerShellProfile = @'
# Ensure TLS 1.2 is supported
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Append Scripts folder to PATH if not already present
$scriptsPath = "$Env:ProgramFiles\WindowsPowerShell\Scripts"
if ($Env:Path -notlike "*$scriptsPath*") {
    [System.Environment]::SetEnvironmentVariable('Path', $Env:Path + ";$scriptsPath", 'Process')
}
'@

    try {
        if (-not (Test-Path $Profile.CurrentUserAllHosts)) {
            Write-Verbose "Creating PowerShell profile at $($Profile.CurrentUserAllHosts)"
            $null = New-Item $Profile.CurrentUserAllHosts -ItemType File -Force -ErrorAction Stop
            $oobePowerShellProfile | Set-Content -Path $Profile.CurrentUserAllHosts -Force -Encoding UTF8 -ErrorAction Stop
            Write-Host -ForegroundColor Green "[+] Created PowerShell Profile [CurrentUserAllHosts]"
        } else {
            Write-Verbose "Profile already exists at $($Profile.CurrentUserAllHosts)"
        }
    } catch {
        Write-Error "Failed to create PowerShell profile: $_"
    }
}
function step-InstallPackageManagement {
    [CmdletBinding()]
    param ()
        $InstalledModule = Get-PackageProvider -Name PowerShellGet | Where-Object {$_.Version -ge '2.2.5'} | Sort-Object Version -Descending | Select-Object -First 1
        if (-not ($InstalledModule)) {
            Write-Host -ForegroundColor Yellow "[-] Install-PackageProvider PowerShellGet -MinimumVersion 2.2.5"
            Install-PackageProvider -Name PowerShellGet -MinimumVersion 2.2.5 -Force -Scope AllUsers | Out-Null
            Import-Module PowerShellGet -Force -Scope Global -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
    
        $InstalledModule = Get-Module -Name PackageManagement -ListAvailable | Where-Object {$_.Version -ge '1.4.8.1'} | Sort-Object Version -Descending | Select-Object -First 1
        if (-not ($InstalledModule)) {
            Write-Host -ForegroundColor Yellow "[-] Install-Module PackageManagement -MinimumVersion 1.4.8.1"
            Install-Module -Name PackageManagement -MinimumVersion 1.4.8.1 -Force -Confirm:$false -Source PSGallery -Scope AllUsers
            Import-Module PackageManagement -Force -Scope Global -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
    
        Import-Module PackageManagement -Force -Scope Global -ErrorAction SilentlyContinue
        $InstalledModule = Get-Module -Name PackageManagement -ListAvailable | Where-Object {$_.Version -ge '1.4.8.1'} | Sort-Object Version -Descending | Select-Object -First 1
        if ($InstalledModule) {
            Write-Host -ForegroundColor Green "[+] PackageManagement $([string]$InstalledModule.Version)"
        }
        Import-Module PowerShellGet -Force -Scope Global -ErrorAction SilentlyContinue
        $InstalledModule = Get-PackageProvider -Name PowerShellGet | Where-Object {$_.Version -ge '2.2.5'} | Sort-Object Version -Descending | Select-Object -First 1
        if ($InstalledModule) {
            Write-Host -ForegroundColor Green "[+] PowerShellGet $([string]$InstalledModule.Version)"
        }
}
function step-TrustPSGallery {
    [CmdletBinding()]
    param ()
    $PowerShellGallery = Get-PSRepository -Name PSGallery -ErrorAction Ignore
    if ($PowerShellGallery.InstallationPolicy -ne 'Trusted') {
        Write-Host -ForegroundColor Yellow "[-] Set-PSRepository PSGallery Trusted"
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    if ($PowerShellGallery.InstallationPolicy -eq 'Trusted') {
        Write-Host -ForegroundColor Green "[+] PSRepository PSGallery Trusted"
    }
}
function step-InstallPowerShellModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [System.Management.Automation.SwitchParameter]
        $Force
    )
    # Do not install the Module by default
    $InstallModule = $false

    # Get the version from the local machine
    $InstalledModule = Get-Module -Name $Name -ListAvailable -ErrorAction Ignore | Sort-Object Version -Descending | Select-Object -First 1
    
    # Get the version from PowerShell Gallery
    $GalleryPSModule = Find-Module -Name $Name -ErrorAction Ignore -WarningAction Ignore

    if ($InstalledModule) {
        if (($GalleryPSModule.Version -as [version]) -gt ($InstalledModule.Version -as [version])) {
            # The version in the gallery is newer than the installed version, so we need to install it
            $InstallModule = $true
        }
    }
    else {
        # Get-Module did not find the module, so we need to install it
        $InstallModule = $true
    }

    if ($InstallModule) {
        if ($WindowsPhase -eq 'WinPE') {
            Write-Host -ForegroundColor Yellow "[-] $Name $($GalleryPSModule.Version) [AllUsers]"
            Install-Module $Name -Scope AllUsers -Force -SkipPublisherCheck -AllowClobber
        }
        elseif ($WindowsPhase -eq 'OOBE') {
            Write-Host -ForegroundColor Yellow "[-] $Name $($GalleryPSModule.Version) [AllUsers]"
            Install-Module $Name -Scope AllUsers -Force -SkipPublisherCheck -AllowClobber
        }
        else {
            # Install the PowerShell Module in the OS
            Write-Host -ForegroundColor Yellow "[-] $Name $($GalleryPSModule.Version) [CurrentUser]"
            Install-Module $Name -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        }
    }
    else {
        # The module is already installed and up to date
        Import-Module -Name $Name -Force
        Write-Host -ForegroundColor Green "[+] $Name $($InstalledModule.Version)"
    }
}

function step-PendingReboot {
    # Checks common locations for pending reboot
    function Test-PendingReboot {
        Write-Host -ForegroundColor Yellow "[-] Checking for Windows Update pending reboot..."
        $rebootPending = $false
        # Check for CBS Reboot Pending
        $cbs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        if (Test-Path $cbs) { $rebootPending = $true }

        # Check for Windows Update Reboot Required
        $wu = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        if (Test-Path $wu) { $rebootPending = $true }

        return $rebootPending
    }

    if (Test-PendingReboot) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            "There is a pending reboot. Please reboot the system and try again.",
            "Pending Reboot Detected",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null

        # Show a Restart prompt
        $choice = [System.Windows.MessageBox]::Show(
            "Would you like to reboot now?",
            "Reboot Required",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
            Restart-Computer -Force
            return $true
        } else {
            exit  # Stop script 
        }
    }
    return $false
}
