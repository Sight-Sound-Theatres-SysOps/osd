<#
    Enables DCU Auto Update, Install, and Reboot
    #>
    $DCUServiceName = 'Dell Client Management Service'

    # Check if the DCU CLI executable exists
    if (Test-Path -Path 'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe') {
        $ProcessPath = 'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
        Write-Host -ForegroundColor Green "[+] Dell Command Update installed"
    } elseif (Test-Path -Path 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe') {
        $ProcessPath = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
        Write-Host -ForegroundColor Green "[+] Dell Command Update installed"
    } else {
        Write-Host -ForegroundColor Cyan "[-] System not = Dell - DCU not supported"
        return  # Stop script execution if DCU is not supported
    }

    # Check if the Dell Client Management Service is running
    $DCUService = Get-Service -DisplayName $DCUServiceName -ErrorAction SilentlyContinue

    if ($DCUService -ne $null -and $DCUService.Status -eq 'Running') {
        Write-Host -ForegroundColor Yellow "[-] Stopping Dell Client Management Service..."
        Stop-Service -DisplayName $DCUServiceName
        Start-Sleep -Seconds 5  # Give some time for the service to stop
    }    
    
    $ProcessArgs = "/configure -scheduleAuto -scheduleAction=DownloadInstallAndNotify -scheduledReboot=60"
    $DCU = Start-Process -FilePath $ProcessPath -ArgumentList $ProcessArgs -Wait -PassThru -NoNewWindow
    $DCUReturn = $DCUReturnTablet | Where-Object {$_.ReturnCode -eq $DCU.ExitCode}

    Write-Host "DCU Finished with Code: $($DCU.ExitCode): $($DCUReturn.Description)"
    Write-Host -ForegroundColor Yellow "[-] Starting Dell Client Management Service..."
    Start-Service -DisplayName $DCUServiceName


