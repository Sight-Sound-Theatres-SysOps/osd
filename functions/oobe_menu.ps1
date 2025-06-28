[CmdletBinding()]
param()
$ScriptName = 'oobe_menu.ps1'
$ScriptVersion = '25.6.27.3'

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

function step-oobemenu {

    Write-Host -ForegroundColor Green "[+] Loading OOBE configuration menu..."

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore

    function Get-TpmVersion {
        try {
            $tpm = Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction Stop
            if ($tpm) { return $tpm.SpecVersion }
            return $null
        } catch { return $null }
    }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Sight &amp; Sound - OOBE Configuration" Height="500" Width="830" WindowStartupLocation="CenterScreen" Background="#FF1E1E1E">
    <Grid Margin="14">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="2.3*" />
            <ColumnDefinition Width="5*" />
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*" />
            <RowDefinition Height="110" />
        </Grid.RowDefinitions>
        <!-- Left Panel: Computer Details, Checkboxes, Winget, TPM, and Clear TPM -->
        <Grid Grid.Column="0" Grid.RowSpan="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" /> <!-- Computer details -->
                <RowDefinition Height="*" />    <!-- Checkboxes -->
                <RowDefinition Height="Auto" /> <!-- Winget -->
                <RowDefinition Height="Auto" /> <!-- TPM label -->
                <RowDefinition Height="Auto" /> <!-- Clear TPM checkbox -->
            </Grid.RowDefinitions>
            <!-- Computer Details Box -->
            <Border Grid.Row="0" Margin="0,0,10,20" Padding="16" CornerRadius="10"
                    Background="#FF23272E" HorizontalAlignment="Center" Width="330">
                <StackPanel>
                    <TextBlock Text="Computer Details" FontSize="15" FontWeight="Bold"
                               Foreground="White" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                    <TextBlock Name="txtManModel" FontSize="13" Foreground="#FFDADADA"
                               HorizontalAlignment="Center" Margin="0,0,0,10"/>
                    <Grid Margin="0,0,0,2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="80"/>
                            <ColumnDefinition Width="250"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock Text="Serial:"   Grid.Column="0" Grid.Row="0" Foreground="#FFAAAAAA" FontSize="13" Margin="0,0,6,2" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        <TextBlock Name="txtSerial" Grid.Column="1" Grid.Row="0" Foreground="White" FontSize="13" Margin="0,0,0,2" VerticalAlignment="Center"/>
                        <TextBlock Text="BIOS:"     Grid.Column="0" Grid.Row="1" Foreground="#FFAAAAAA" FontSize="13" Margin="0,0,6,2" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        <TextBlock Name="txtBios"   Grid.Column="1" Grid.Row="1" Foreground="White" FontSize="13" Margin="0,0,0,2" TextWrapping="Wrap" VerticalAlignment="Center"/>
                        <TextBlock Text="CPU:"      Grid.Column="0" Grid.Row="2" Foreground="#FFAAAAAA" FontSize="13" Margin="0,0,6,2" HorizontalAlignment="Right" VerticalAlignment="Center" Name="lblCpuLabel"/>
                        <TextBlock Name="txtCpu"    Grid.Column="1" Grid.Row="2" Foreground="White" FontSize="13" Margin="0,0,0,2" VerticalAlignment="Center"/>
                    </Grid>
                </StackPanel>
            </Border>
            <!-- Checkboxes Section -->
            <StackPanel Grid.Row="1" VerticalAlignment="Top" HorizontalAlignment="Stretch" Margin="0,0,10,0">
                <CheckBox Name="chkOffice" Content="Install Office Applications" Margin="0,0,0,14" Foreground="White" />
                <CheckBox Name="chkUmbrella" Content="Install Cisco Umbrella Client" Margin="0,0,0,14" Foreground="White" />
                <CheckBox Name="chkDellCmd" Content="Install Dell Command Update" Margin="0,0,0,14" Foreground="White" />
            </StackPanel>
            <TextBlock Name="txtWinget" Grid.Row="2" FontSize="14" Foreground="#FFC0C0C0" Margin="4,7,0,0" HorizontalAlignment="Left"/>
            <TextBlock Name="lblTPM" Grid.Row="3" VerticalAlignment="Bottom" HorizontalAlignment="Left" Margin="4,0,0,0" FontSize="14" FontWeight="Bold"/>
            <CheckBox Name="chkClearTPM" Grid.Row="4" Content="Clear TPM" Margin="4,0,0,0" Foreground="White" VerticalAlignment="Bottom"/>
        </Grid>
        <!-- Right Panel: Autopilot Section -->
        <Border Grid.Column="1" Grid.Row="0" Background="#FF23272E" CornerRadius="8" Padding="16" Margin="10,0,0,0" Width="480" MinHeight="360">
            <StackPanel>
                <TextBlock Text="Autopilot" FontSize="22" FontWeight="Bold" Margin="0,0,0,20" Foreground="White"/>
                <CheckBox Name="chkEnroll" Content="Enroll in Autopilot" Margin="0,0,0,16" Foreground="White"/>
                <TextBlock Text="Group Tag:" Foreground="White"/>
                <ComboBox Name="cmbGroupTag" VerticalContentAlignment="Center" Margin="0,0,0,12" Height="30">
                    <ComboBoxItem Content="Entreprise" />
                    <ComboBoxItem Content="Development" />
                    <ComboBoxItem Content="MTR-" />
                </ComboBox>
                <TextBlock Text="Group:" Foreground="White"/>
                <ComboBox Name="cmbGroup" VerticalContentAlignment="Center" Margin="0,0,0,12" Height="30">
                    <ComboBoxItem Content="Autopilot_Devices-GeneralUsers" />
                    <ComboBoxItem Content="Autopilot_Devices-Box_CC" />
                    <ComboBoxItem Content="AutoPilot_Devices-Retail" />
                    <ComboBoxItem Content="Autopilot_Devices-CenterStageKiosk" />
                    <ComboBoxItem Content="Autopilot_Devices-SharedDevice" />
                    <ComboBoxItem Content="AutoPilot_Devices-TeamsRooms" />
                </ComboBox>
                <TextBlock Text="Computer Name:" Foreground="White"/>
                <TextBox Name="txtComputerName" VerticalContentAlignment="Center" Margin="0,0,0,12" Height="30" />
                <TextBlock Text="Enrollment Password:" Foreground="White"/>
                <PasswordBox Name="pwdEnrollment" VerticalContentAlignment="Center" Margin="0,0,0,0" Height="30" />
            </StackPanel>
        </Border>
        <!-- Bottom right: Buttons and Time -->
        <StackPanel Grid.Column="1" Grid.Row="1" Orientation="Vertical" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,8,8">
            <!-- Buttons Row -->
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,0,7">
                <Button Name="btnCancel" Content="Cancel" Width="88" Height="34" Margin="0,0,10,0" Background="#FF363636" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
                <Button Name="btnContinue" Content="Continue" Width="110" Height="34" Background="#FF3A78F2" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
            </StackPanel>
            <!-- Time and Timezone Row -->
            <Border Background="#FF23272E" CornerRadius="7" Padding="8,5" Margin="0,0,0,0" HorizontalAlignment="Right" VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal">
                    <Label Name="lblTime" FontSize="16" Foreground="White" FontWeight="Bold" Cursor="Hand" Padding="0" Margin="0" VerticalAlignment="Center"/>
                    <TextBlock Text="  " />
                    <Label Name="lblTimeZone" FontSize="16" Foreground="White" Cursor="Hand" Padding="0" Margin="0" VerticalAlignment="Center"/>
                </StackPanel>
            </Border>
        </StackPanel>
    </Grid>
</Window>
"@

    # --- XAML LOADING: use XmlReader + StringReader, NOT [xml] ---
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    function Find-Name {
        param([string]$name)
        return $window.FindName($name)
    }

    # Controls
    $chkOffice      = Find-Name 'chkOffice'
    $chkUmbrella    = Find-Name 'chkUmbrella'
    $chkDellCmd     = Find-Name 'chkDellCmd'
    $lblTPM         = Find-Name 'lblTPM'
    $chkClearTPM    = Find-Name 'chkClearTPM'
    $chkEnroll      = Find-Name 'chkEnroll'
    $cmbGroupTag    = Find-Name 'cmbGroupTag'
    $cmbGroup       = Find-Name 'cmbGroup'
    $txtComputerName= Find-Name 'txtComputerName'
    $pwdEnrollment  = Find-Name 'pwdEnrollment'
    $lblTime        = Find-Name 'lblTime'
    $lblTimeZone    = Find-Name 'lblTimeZone'
    $btnCancel      = Find-Name 'btnCancel'
    $btnContinue    = Find-Name 'btnContinue'
    $txtManufacturer = Find-Name 'txtManufacturer'
    $txtModel        = Find-Name 'txtModel'
    $txtSerial       = Find-Name 'txtSerial'
    $txtBios         = Find-Name 'txtBios'
    $lblCpuLabel     = Find-Name 'lblCpuLabel'
    $txtCpu          = Find-Name 'txtCpu'
    $txtWinget       = Find-Name 'txtWinget'
    $txtManModel     = Find-Name 'txtManModel'

    # Get Computer Details
    try {
        $compSys = Get-WmiObject -Class Win32_ComputerSystem
        $bios    = Get-WmiObject -Class Win32_BIOS
        $proc    = Get-WmiObject -Class Win32_Processor | Select-Object -First 1

        if ($txtManufacturer) { $txtManufacturer.Text  = $compSys.Manufacturer }
        if ($txtModel)        { $txtModel.Text         = $compSys.Model }
        if ($txtSerial)       { $txtSerial.Text        = $bios.SerialNumber }
        if ($txtBios)         { $txtBios.Text          = $bios.SMBIOSBIOSVersion }
        if ($txtManModel)     { $txtManModel.Text      = "$($compSys.Manufacturer) - $($compSys.Model)" }

        if ($chkDellCmd) {
            if ($compSys.Manufacturer -ne "Dell Inc.") {
                $chkDellCmd.IsEnabled = $false
                $chkDellCmd.ToolTip = "This option is only available on Dell systems."
                $chkDellCmd.Foreground = [System.Windows.Media.Brushes]::DarkSlateGray
            } else {
                $chkDellCmd.IsEnabled = $true
                $chkDellCmd.ToolTip = $null
                $chkDellCmd.Foreground = [System.Windows.Media.Brushes]::White
            }
        }

        if ($proc.Architecture -eq 9) {
            if ($txtCpu) { $txtCpu.Text = "x64" }
            if ($lblCpuLabel) { $lblCpuLabel.Visibility = "Visible" }
            if ($txtCpu) { $txtCpu.Visibility = "Visible" }
        } elseif ($proc.Architecture -eq 12) {
            if ($txtCpu) { $txtCpu.Text = "ARM" }
            if ($lblCpuLabel) { $lblCpuLabel.Visibility = "Visible" }
            if ($txtCpu) { $txtCpu.Visibility = "Visible" }
        } else {
            if ($lblCpuLabel) { $lblCpuLabel.Visibility = "Collapsed" }
            if ($txtCpu) { $txtCpu.Visibility = "Collapsed" }
        }
    } catch {
        if ($txtManufacturer) { $txtManufacturer.Text = "N/A" }
        if ($txtModel)        { $txtModel.Text        = "N/A" }
        if ($txtSerial)       { $txtSerial.Text       = "N/A" }
        if ($txtBios)         { $txtBios.Text         = "N/A" }
        if ($txtManModel)     { $txtManModel.Text     = "N/A" }
        if ($lblCpuLabel)     { $lblCpuLabel.Visibility = "Collapsed" }
        if ($txtCpu)          { $txtCpu.Visibility = "Collapsed" }
        if ($chkDellCmd) {
            $chkDellCmd.IsEnabled = $false
            $chkDellCmd.ToolTip = "This option is only available on Dell systems."
            $chkDellCmd.Foreground = [System.Windows.Media.Brushes]::DarkSlateGray
        }
    }

    # Winget version check
    try {
        $wingetVersion = & winget --version 2>$null
        if ($wingetVersion) {
            if ($txtWinget) {
                $txtWinget.Text = "Winget installed ($wingetVersion)"
                $txtWinget.Foreground = [System.Windows.Media.Brushes]::LimeGreen
            }
        } else {
            if ($txtWinget) {
                $txtWinget.Text = "Winget not installed"
                $txtWinget.Foreground = [System.Windows.Media.Brushes]::Red
            }
        }
    } catch {
        if ($txtWinget) {
            $txtWinget.Text = "Winget not installed"
            $txtWinget.Foreground = [System.Windows.Media.Brushes]::Red
        }
    }

    # Set Time Zone display
    $timeZone = [System.TimeZoneInfo]::Local
    if ($lblTimeZone) { $lblTimeZone.Content = $timeZone.StandardName }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMinutes(1)
    $updateDateTime = {
        $now = Get-Date
        if ($lblTime) { $lblTime.Content = $now.ToString("dddd, MMMM d  h:mm tt") }
    }
    $timer.Add_Tick($updateDateTime)
    & $updateDateTime
    $timer.Start()

    if ($lblTime) { $lblTime.ToolTip = "Click to open Windows Date & Time settings" }
    if ($lblTimeZone) { $lblTimeZone.ToolTip = "Click to open Windows Date & Time settings" }
    $openSettings = {
        Start-Process "ms-settings:dateandtime"
    }
    if ($lblTime) { $null = $lblTime.Add_MouseLeftButtonUp($openSettings) }
    if ($lblTimeZone) { $null = $lblTimeZone.Add_MouseLeftButtonUp($openSettings) }

    $tpmVer = Get-TpmVersion
    if ($lblTPM) {
        $lblTPM.Inlines.Clear()
        if ($tpmVer -and $tpmVer -match "^2") {
            $lblTPM.Inlines.Add("TPM v2")
            $lblTPM.Foreground = [System.Windows.Media.Brushes]::LimeGreen
        } else {
            $lblTPM.Inlines.Add("TPM v2 ")
            $italic = New-Object System.Windows.Documents.Run(" (Autopilot not supported)")
            $italic.FontStyle = [System.Windows.FontStyles]::Italic
            $lblTPM.Inlines.Add($italic)
            $lblTPM.Foreground = [System.Windows.Media.Brushes]::Red
        }
    }

    $global:oobeMenuResult = $null

    if ($btnCancel) {
        $btnCancel.Add_Click({
            $global:oobeMenuResult = $null
            $window.Close()
        })
    }
    if ($btnContinue) {
        $btnContinue.Add_Click({
            $global:oobeMenuResult = [PSCustomObject]@{
                InstallOffice = $chkOffice.IsChecked
                InstallUmbrella = $chkUmbrella.IsChecked
                InstallDellCmd = $chkDellCmd.IsChecked
                ClearTPM = $chkClearTPM.IsChecked
                EnrollAutopilot = $chkEnroll.IsChecked
                GroupTag = $cmbGroupTag.Text
                Group = $cmbGroup.Text
                ComputerName = $txtComputerName.Text
                EnrollmentPassword = $pwdEnrollment.Password
            }
            $window.Close()
        })
    }

    $window.ShowDialog() | Out-Null
    $timer.Stop()
    return $global:oobeMenuResult
}
