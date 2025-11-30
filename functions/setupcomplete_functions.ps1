
Function Set-PowerSettingTurnMonitorOffAfter
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[int] $Minutes,
	        [Parameter(Mandatory = $true)]
	        [ValidateSet(
			"AC",
			"Battery"
		)]
		[string]$PowerSource
	)

    #Get Seconds
    [int]$Seconds = $Minutes * 60
    if ($Seconds -gt 18000){
        $Seconds = 18000
        Write-Output "Max Time is 5 hours, settings to 300 minutes"
    }


	# Get active plan
	# Get-CimInstance won't work due to Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan doesn't have the "Activate" trigger as Get-WmiObject does
	$CurrentPlan = Get-WmiObject -Namespace root\cimv2\power -ClassName Win32_PowerPlan | Where-Object -FilterScript {$_.IsActive}

	# Get "Lid closed" setting
	$SleepAfterSetting = Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_Powersetting | Where-Object -FilterScript {$_.ElementName -eq "Turn off display after"}

	# Get GUIDs
	$CurrentPlanGUID = [Regex]::Matches($CurrentPlan.InstanceId, "{.*}" ).Value
	$SleepAfterGUID = [Regex]::Matches($SleepAfterSetting.InstanceID, "{.*}" ).Value

	# Get and set "Plugged in lid" setting (DC)
    if ($PowerSource -eq "Battery"){
	    Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerSettingDataIndex | Where-Object -FilterScript {
		    ($_.InstanceID -eq "Microsoft:PowerSettingDataIndex\$CurrentPlanGUID\DC\$SleepAfterGUID")
	    } | Set-CimInstance -Property @{SettingIndexValue = $Seconds}
    }
    # Get and set "Plugged in lid" setting (AC)
    if ($PowerSource -eq "AC"){
	    Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerSettingDataIndex | Where-Object -FilterScript {
		    ($_.InstanceID -eq "Microsoft:PowerSettingDataIndex\$CurrentPlanGUID\AC\$SleepAfterGUID")
	    } | Set-CimInstance -Property @{SettingIndexValue = $Seconds}
    }

	# Refresh
	# $CurrentPlan | Invoke-CimMethod -MethodName Activate results in "This method is not implemented in any class"
	$CurrentPlan.Activate
}

function Set-PowerSettingSleepAfter {
    [CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[int] $Minutes,
        [Parameter(Mandatory = $true)]
        [ValidateSet(
			"AC",
			"Battery"
		)]
		[string]$PowerSource
	)

    #Get Seconds
    [int]$Seconds = $Minutes * 60
    if ($Seconds -gt 18000){
        $Seconds = 18000
        Write-Output "Max Time is 5 hours, settings to 300 minutes"
    }


	# Get active plan
	# Get-CimInstance won't work due to Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan doesn't have the "Activate" trigger as Get-WmiObject does
	$CurrentPlan = Get-WmiObject -Namespace root\cimv2\power -ClassName Win32_PowerPlan | Where-Object -FilterScript {$_.IsActive}

	# Get "Lid closed" setting
	$SleepAfterSetting = Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_Powersetting | Where-Object -FilterScript {$_.ElementName -eq "Sleep after"}

	# Get GUIDs
	$CurrentPlanGUID = [Regex]::Matches($CurrentPlan.InstanceId, "{.*}" ).Value
	$SleepAfterGUID = [Regex]::Matches($SleepAfterSetting.InstanceID, "{.*}" ).Value

	# Get and set "Plugged in lid" setting (DC)
    if ($PowerSource -eq "Battery"){
	    Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerSettingDataIndex | Where-Object -FilterScript {
		    ($_.InstanceID -eq "Microsoft:PowerSettingDataIndex\$CurrentPlanGUID\DC\$SleepAfterGUID")
	    } | Set-CimInstance -Property @{SettingIndexValue = $Seconds}
    }
    # Get and set "Plugged in lid" setting (AC)
    if ($PowerSource -eq "AC"){
	    Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerSettingDataIndex | Where-Object -FilterScript {
		    ($_.InstanceID -eq "Microsoft:PowerSettingDataIndex\$CurrentPlanGUID\AC\$SleepAfterGUID")
	    } | Set-CimInstance -Property @{SettingIndexValue = $Seconds}
    }

	# Refresh
	# $CurrentPlan | Invoke-CimMethod -MethodName Activate results in "This method is not implemented in any class"
	$CurrentPlan.Activate
}

Function Start-WindowsUpdate {
    <#
    .SYNOPSIS
    Control Windows Update via PowerShell
    
    .DESCRIPTION
    Installing Updates using this Method does NOT notify the user, and does NOT let the user know that updates need to be applied at the next reboot.
    It's 100% hidden.
    HResult Lookup: https://docs.microsoft.com/en-us/windows/win32/wua_sdk/wua-success-and-error-codes-
    #>

    $Results = @(
        @{ ResultCode = '0'; Meaning = "Not Started"}
        @{ ResultCode = '1'; Meaning = "In Progress"}
        @{ ResultCode = '2'; Meaning = "Succeeded"}
        @{ ResultCode = '3'; Meaning = "Succeeded With Errors"}
        @{ ResultCode = '4'; Meaning = "Failed"}
        @{ ResultCode = '5'; Meaning = "Aborted"}
        @{ ResultCode = '6'; Meaning = "No Updates Found"}
    )

    $WUDownloader = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateDownloader()
    $WUInstaller = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateInstaller()
    $WUUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
    
    ((New-Object -ComObject Microsoft.Update.Session).CreateupdateSearcher().Search("IsInstalled=0 and Type='Software'")).Updates | % {
        if(!$_.EulaAccepted) { $_.EulaAccepted = $true }
        if ($_.Title -notmatch "Preview") { [void]$WUUpdates.Add($_) }
    }

    if ($WUUpdates.Count -ge 1) {
        $WUInstaller.ForceQuiet = $true
        $WUInstaller.Updates = $WUUpdates
        $WUDownloader.Updates = $WUUpdates
        $UpdateCount = $WUDownloader.Updates.count
        
        if ($UpdateCount -ge 1) {
            Write-Output "Downloading $UpdateCount Updates"
            foreach ($update in $WUInstaller.Updates) { Write-Output "$($update.Title)" }
            $Download = $WUDownloader.Download()
        }
        
        $InstallUpdateCount = $WUInstaller.Updates.count
        if ($InstallUpdateCount -ge 1) {
            Write-Output "Installing $InstallUpdateCount Updates | Time: $($(Get-Date).ToString("hh:mm:ss"))"
            $Install = $WUInstaller.Install()
            $ResultMeaning = ($Results | Where-Object {$_.ResultCode -eq $Install.ResultCode}).Meaning
            Write-Output $ResultMeaning
        }
    }
    else { 
        Write-Output "No Updates Found"
    }
}

Function Start-WindowsUpdateDriver {
    <#
    .SYNOPSIS
    Control Windows Update Driver Updates via PowerShell
    
    .DESCRIPTION
    Installing Updates using this Method does NOT notify the user, and does NOT let the user know that updates need to be applied at the next reboot.
    It's 100% hidden.
    #>

    $Results = @(
        @{ ResultCode = '0'; Meaning = "Not Started"}
        @{ ResultCode = '1'; Meaning = "In Progress"}
        @{ ResultCode = '2'; Meaning = "Succeeded"}
        @{ ResultCode = '3'; Meaning = "Succeeded With Errors"}
        @{ ResultCode = '4'; Meaning = "Failed"}
        @{ ResultCode = '5'; Meaning = "Aborted"}
        @{ ResultCode = '6'; Meaning = "No Updates Found"}
    )

    $WUDownloader = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateDownloader()
    $WUInstaller = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateInstaller()
    $WUUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
    
    ((New-Object -ComObject Microsoft.Update.Session).CreateupdateSearcher().Search("IsInstalled=0 and Type='Driver'")).Updates | % {
        if(!$_.EulaAccepted) { $_.EulaAccepted = $true }
        [void]$WUUpdates.Add($_)
    }

    if ($WUUpdates.Count -ge 1) {
        $WUInstaller.ForceQuiet = $true
        $WUInstaller.Updates = $WUUpdates
        $WUDownloader.Updates = $WUUpdates
        $UpdateCount = $WUDownloader.Updates.count
        
        if ($UpdateCount -ge 1) {
            Write-Output "Downloading $UpdateCount Driver Updates"
            foreach ($update in $WUInstaller.Updates) { Write-Output "$($update.Title)" }
            $Download = $WUDownloader.Download()
        }
        
        $InstallUpdateCount = $WUInstaller.Updates.count
        if ($InstallUpdateCount -ge 1) {
            Write-Output "Installing $InstallUpdateCount Driver Updates | Time: $($(Get-Date).ToString("hh:mm:ss"))"
            $Install = $WUInstaller.Install()
            $ResultMeaning = ($Results | Where-Object {$_.ResultCode -eq $Install.ResultCode}).Meaning
            Write-Output $ResultMeaning
        }
    }
    else { 
        Write-Output "No Driver Updates Found"
    }
}

function Update-DefenderStack {
    [CmdletBinding()]
    param ()
#    if (Test-WebConnection -Uri "google.com") {
    if (Test-WindowsUpdateEnvironment) {
        # Source Addresses - Defender for Windows 10, 8.1 ################################
        $sourceAVx64 = "http://go.microsoft.com/fwlink/?LinkID=121721&arch=x64"
        $sourcePlatformx64 = "https://go.microsoft.com/fwlink/?LinkID=870379&clcid=0x409&arch=x64"
        Write-Output "UPDATE Defender Package Script version $ScriptVer..."
        $Intermediate = "$env:TEMP\DefenderScratchSpace"
    
        if (!(Test-Path -Path "$Intermediate")) {
            $Null = New-Item -Path "$env:TEMP" -Name "DefenderScratchSpace" -ItemType Directory
        }
    
        if (!(Test-Path -Path "$Intermediate\x64")) {
            $Null = New-Item -Path "$Intermediate" -Name "x64" -ItemType Directory
        }

        Remove-Item -Path "$Intermediate\x64\*" -Force -EA SilentlyContinue
        $wc = New-Object System.Net.WebClient
    
        # x64 AV #########################################################################
    
        $Dest = "$Intermediate\x64\" + 'mpam-fe.exe'
        Write-Output "Starting MPAM-FE Download"
        $wc.DownloadFile($sourceAVx64, $Dest)
        if (Test-Path -Path $Dest) {
            $x = Get-Item -Path $Dest
            [version]$Version1a = $x.VersionInfo.ProductVersion #Downloaded
            [version]$Version1b = (Get-MpComputerStatus).AntivirusSignatureVersion #Currently Installed
            if ($Version1a -gt $Version1b) {
                Write-Output "Starting MPAM-FE Install of $Version1b to $Version1a"
                $MPAMInstall = Start-Process -FilePath $Dest -Wait -PassThru
            }
            else {
                Write-Output "No Update Needed, Installed:$Version1b vs Downloaded: $Version1a"
            }
            Write-Output "Finished MPAM-FE Install"
        }
        else {
            Write-Output "Failed MPAM-FE Download"
        }
    
        # x64 Update Platform ########################################################################
        Write-Output "Starting Update Platform Download"
        $Dest = "$Intermediate\x64\" + 'UpdatePlatform.exe'
        $wc.DownloadFile($sourcePlatformx64, $Dest)
    
        if (Test-Path -Path $Dest) {
            $x = Get-Item -Path $Dest
            [version]$Version2a = $x.VersionInfo.ProductVersion #Downloaded
            [version]$Version2b = (Get-MpComputerStatus).AMServiceVersion #Installed
    
            if ($Version2a -gt $Version2b) {
                Write-Output "Starting Update Platform Install of $Version2b to $Version2a"
                $UPInstall = Start-Process -FilePath $Dest -Wait -PassThru
            }
            else {
                Write-Output "No Update Needed, Installed:$Version2b vs Downloaded: $Version2a"
            }
            Write-Output "Finished Update Platform Install"
        }
        else {
            Write-Output "Failed Update Platform Download"
        }
        New-Alias -Name 'UpdateDefenderStack' -Value 'osdcloud-UpdateDefenderStack' -Description 'OSDCloud' -Force
    }
    else {
        Write-Output "No Internet Connection, Skipping Defender Updates"
    }
}

function Get-WindowsOEMProductKey {
    $ProductKey = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
    return $ProductKey
}

function Set-WindowsOEMActivation {
    $ProductKey = Get-WindowsOEMProductKey
    Write-Output "Starting Process to Set Windows Licence to OEM Value in BIOS"
    if ($ProductKey) {
        try {
            Write-Output " Setting Key: $ProductKey" 
            $service = get-wmiObject -query "select * from SoftwareLicensingService"
            if ($service){
                $service.InstallProductKey($ProductKey) | Out-Null
                $service.RefreshLicenseStatus() | Out-Null
                $service.RefreshLicenseStatus() | Out-Null
                Write-Output  " Successfully Applied Key"
            }
            else {
                Write-Output " Failed to connect to Service to Apply Key"
            }
        }
        catch {
            Write-Output " Failed try statement to Apply Key"
        }
    }
    else{
	    Write-Output ' Key not found!'
    }
}