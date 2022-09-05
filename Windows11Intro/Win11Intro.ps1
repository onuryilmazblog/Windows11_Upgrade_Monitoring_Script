## < WINDOWS 11 UPGRADE MONITORING SCRIPT > ## 

<#
.OZET
Bu komut dosyası, SCCM Windows Servicing ile gönderimi sağlanan windows 11 update paketini monitör eder ve kullanıcı ekranına bildirimler gönderir.
# LİSANS #
Windows 11 Upgrade Monitoring Script - Windows 10'dan Windows 11'e geçiş yapılabilmesi için bir dizi izleme ve yönlendirme sağlar.
Bu program özgür bir yazılımdır: yeniden dağıtabilir ve/veya değiştirebilirsiniz. Bu program yararlı olması ümidiyle dağıtılmaktadır, ancak HİÇBİR GARANTİ YOKTUR.
.TANIM
SCCM Windows Servicing Update ile birlikte çalışmaktadır. Windows Servicing Update ile tamamen sessiz bir şekilde gönderim sağladığınız Windows 11 Update paketini 
EvaluationState değerlerini kontrol ederek izler ve tespit ettiği değerlere göre kullanıcıya özel hazırlanmış bildirimlerin gönderimini sağlar.
.VERSION
1.0.6
.YAZAR
Onur Yilmaz
.BAĞLANTI
https://onuryilmaz.blog
#>


##*=============================================
##* GET CONFIG FILE VARIABLE
##*=============================================
$scriptPaths = split-path -parent $MyInvocation.MyCommand.Definition
$scriptMainPath = Split-Path -Path $scriptPaths -Parent
## Get Config Veriable
$Config = "$scriptMainPath\Config.xml"
if (Test-Path $Config -ErrorAction SilentlyContinue) {
    $Xml = [xml](Get-Content -Path $Config -ErrorAction SilentlyContinue)
    [string]$scriptPath = $Xml.Configuration.Option | Select-Object -ExpandProperty scriptPath -ErrorAction SilentlyContinue
}


## Remove Variable
If (Test-Path -LiteralPath 'variable:dpiScale') { Remove-Variable -Name 'dpiScale' }
If (Test-Path -LiteralPath 'variable:UserDisplayScaleFactor') { Remove-Variable -Name 'UserDisplayScaleFactor' }
If (Test-Path -LiteralPath 'variable:RunAsActiveUser') { Remove-Variable -Name 'RunAsActiveUser' }
If (Test-Path -LiteralPath 'variable:User') { Remove-Variable -Name 'User' }
If (Test-Path -LiteralPath 'variable:XAML') { Remove-Variable -Name 'XAML' }
If (Test-Path -LiteralPath 'variable:XAMLReader') { Remove-Variable -Name 'XAMLReader' }
If (Test-Path -LiteralPath 'variable:Window') { Remove-Variable -Name 'Window' }
If (Test-Path -LiteralPath 'variable:SoundOnButton') { Remove-Variable -Name 'SoundOnButton' }
If (Test-Path -LiteralPath 'variable:SoundOffButton') { Remove-Variable -Name 'SoundOffButton' }
If (Test-Path -LiteralPath 'variable:ReplayButton') { Remove-Variable -Name 'ReplayButton' }
If (Test-Path -LiteralPath 'variable:SoundOffButton') { Remove-Variable -Name 'SoundOffButton' }
If (Test-Path -LiteralPath 'variable:CloseButton') { Remove-Variable -Name 'CloseButton' }
If (Test-Path -LiteralPath 'variable:VideoPlayer') { Remove-Variable -Name 'VideoPlayer' }
If (Test-Path -LiteralPath 'variable:Label') { Remove-Variable -Name 'Label' }

## Check Active User SID
[string]$SystemDrive = $env:SystemDrive
$UpgradeFolderPath = $scriptPath
[string[]]$ReferencedAssemblies = 'System.Drawing', 'System.Windows.Forms', 'System.DirectoryServices'
Add-Type -Path "$UpgradeFolderPath\PreNotification\AppDeployToolkit\AppDeployToolkitMain.cs" -ReferencedAssemblies $ReferencedAssemblies
$User=[PSADT.QueryUser]::GetUserSessionInfo("$env:ComputerName")
if ($User -ne $null) { $RunAsActiveUser = $User | Where-Object {$_.IsActiveUserSession -eq $True} -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty SID  -ErrorAction SilentlyContinue}

## Variables: System DPI Scale Factor
#  If a user is logged on, then get display scale factor for logged on user (even if running in session 0)
[boolean]$UserDisplayScaleFactor = $false
New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
If ($RunAsActiveUser) {
    [int32]$dpiPixels = Get-ItemProperty -Path "HKU:\$RunAsActiveUser\Control Panel\Desktop\WindowMetrics" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "AppliedDPI" -ErrorAction SilentlyContinue
    If (-not ([string]$dpiPixels)) {
        [int32]$dpiPixels = Get-ItemProperty -Path "HKU:\$RunAsActiveUser\Control Panel\Desktop" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "LogPixels" -ErrorAction SilentlyContinue
    }
	[boolean]$UserDisplayScaleFactor = $true
}
If (-not ([string]$dpiPixels)) {
    #  This registry setting only exists if system scale factor has been changed at least once
    [int32]$dpiPixels = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontDPI' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "LogPixels" -ErrorAction SilentlyContinue
	[boolean]$UserDisplayScaleFactor = $false
	}
	Switch ($dpiPixels) {
		96 { [int32]$dpiScale = 100 }
		120 { [int32]$dpiScale = 125 }
		144 { [int32]$dpiScale = 150 }
		192 { [int32]$dpiScale = 200 }
		Default { [int32]$dpiScale = 100 }
}


#WPF Library for Playing Movie and some components
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.ComponentModel
$timer = New-Object -TypeName 'System.Windows.Forms.Timer'
$timerend = New-Object -TypeName 'System.Windows.Forms.Timer'
#XAML File of WPF as windows for playing movie#
[xml]$XAML = @"
 
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows 11 Intro" Height="214" Width="380" ResizeMode="NoResize" WindowStyle="None" Background="Transparent" ShowInTaskbar="False">
    <Grid Margin="0,0,0,0">
        <MediaElement Height="244" Width="378" Name="VideoPlayer" LoadedBehavior="Manual" UnloadedBehavior="Stop" />
        <Button Content="Tanıtımı Geç" Name="CloseButton" HorizontalAlignment="Left" Margin="270,177,0,0" VerticalAlignment="Top" Width="100" Height="25"/>
        <Button Content="Replay" Name="ReplayButton" HorizontalAlignment="Left" Margin="40,177,0,0" VerticalAlignment="Top" Width="25" Height="25"/>
        <Button Content="Ses Aç" Name="SoundOnButton" HorizontalAlignment="Left" Margin="10,177,0,0" VerticalAlignment="Top" Width="25" Height="25"/>
        <Button Content="Sesi Kapat" Name="SoundOffButton" HorizontalAlignment="Left" Margin="10,177,0,0" VerticalAlignment="Top" Width="25" Height="25"/>
        <Label x:Name="Label" Content="" HorizontalAlignment="Left" Margin="58,2,0,0" VerticalAlignment="Top" Height="40" Width="420" FontSize="16"/>
    </Grid>
</Window>
"@

$FolderLocation = "$UpgradeFolderPath\Windows11Intro"

#Devide All Objects on XAML
#Devide All Objects on XAML
$XAMLReader=(New-Object System.Xml.XmlNodeReader $XAML)
$Window=[Windows.Markup.XamlReader]::Load( $XAMLReader )
$VideoPlayer = $Window.FindName("VideoPlayer")
$CloseButton = $Window.FindName("CloseButton")
$ReplayButton = $Window.FindName("ReplayButton")
$SoundOnButton = $Window.FindName("SoundOnButton")
$SoundOffButton = $Window.FindName("SoundOffButton")
$Label = $Window.FindName("Label")
$timerstopcontrol = $false
[int32]$global:ReplayButtonCount = 2
$Window.Topmost = $True

$screen = [Windows.Forms.Screen]::PrimaryScreen
$screenWorkingArea = $screen.WorkingArea
[int32]$screenWidth = $screenWorkingArea | Select-Object -ExpandProperty 'Width'
[int32]$screenHeight = $screenWorkingArea | Select-Object -ExpandProperty 'Height'
#  Set the start position of the Window based on the screen size
$Window.Left = [string]((($screenWidth / ($dpiscale / 100)) - 10 ) - ($Window.Width))
$Window.Top = [string]((($screenHeight / ($dpiscale / 100)) - 12 ) - ($Window.Height))


[scriptblock]$FormEvent_Load = {
	$Window.WindowState = 'Normal'
    $Window.WindowStartupLocation = "Manual"
	$Window.TopMost = $true
    $timer.Start()
    $VideoPlayer.Play()
}


[scriptblock]$Form_StateCorrection_Load = {
    $Window.WindowState = 'Normal'
    $Window.WindowStartupLocation = "Manual"
	$Window.TopMost = $true
    $timer.Start()
    $VideoPlayer.Play()
}


$Window.Add_Loaded($FormEvent_Load)

## Remove all event handlers from the controls
[scriptblock]$Form_Cleanup_FormClosed = {
Try {
    $Window.remove_Load($FormEvent_Load)
    $Window.remove_FormClosed($Form_Cleanup_FormClosed)
    $Window.remove_Load($Form_StateCorrection_Load)
    $timer.remove_Tick($timer_Tick)
}
Catch { }
}


# CloseButton
$CloseButton.Background = "Black"
#$CloseButton.Background = "Transparent"
#$CloseButton.BorderThickness = "0"
$CloseButton.Foreground = "White"
$CloseButton.FontWeight = "Bold"
$CloseButton.BorderBrush = "White"

# SoundOnImage
$SoundOnimage = New-Object System.Windows.Controls.Image
$SoundOnimage.Source = "$FolderLocation\SoundOn.png"
$SoundOnimage.Stretch = 'Fill'
$SoundOnButton.Content = $SoundOnimage

# SoundOffImage
$SoundOffimage = New-Object System.Windows.Controls.Image
$SoundOffimage.Source = "$FolderLocation\SoundOff.png"
$SoundOffimage.Stretch = 'Fill'
$SoundOffButton.Content = $SoundOffimage

# ReplayButton
$Replayimage = New-Object System.Windows.Controls.Image
$Replayimage.Source = "$FolderLocation\Replay.png"
$Replayimage.Stretch = 'Fill'
$ReplayButton.Content = $Replayimage
#$ReplayButton.Background = "Transparent"
#$ReplayButton.BorderThickness = "0" 
 
#Video Default Setting
$VideoPlayer.Volume = 0;
$VideoPlayer.Source = "$FolderLocation\Intro.mp4"
$CloseButton.Visibility = [System.Windows.Visibility]::Hidden
$SoundOnButton.Visibility = [System.Windows.Visibility]::Visible
$SoundOffButton.Visibility = [System.Windows.Visibility]::Visible
$ReplayButton.Visibility = [System.Windows.Visibility]::Hidden
$Label.Foreground = "White"
$Label.FontWeight = "Bold"

$Window.Add_MouseLeave({
    $SoundOnButton.Visibility = [System.Windows.Visibility]::Hidden
    if ($VideoPlayer.Volume -eq 0) {
        $SoundOffButton.Visibility = [System.Windows.Visibility]::Visible
    }
    $ReplayButton.Visibility = [System.Windows.Visibility]::Hidden
    $CloseButton.Visibility = [System.Windows.Visibility]::Hidden
})


$Window.Add_MouseEnter({
    if ($VideoPlayer.Volume -eq 100) {
        $SoundOnButton.Visibility = [System.Windows.Visibility]::Visible
        $SoundOffButton.Visibility = [System.Windows.Visibility]::Hidden
    }
    elseif ($VideoPlayer.Volume -eq 0) {
        $SoundOnButton.Visibility = [System.Windows.Visibility]::Hidden
        $SoundOffButton.Visibility = [System.Windows.Visibility]::Visible
    }
    $ReplayButton.Visibility = [System.Windows.Visibility]::Visible
    $CloseButton.Visibility = [System.Windows.Visibility]::Visible
    if ( [int32]$global:ReplayButtonCount -eq 0 ) {
       $ReplayButton.Visibility = [System.Windows.Visibility]::Hidden
    }
})


# ReplayButton click event 
$ReplayButton.Add_Click({
    $timer.Start()
    $VideoPlayer.Stop()
    $VideoPlayer.Play()
    
    $CloseButton.Visibility = [System.Windows.Visibility]::Hidden
    $SoundOnButton.Visibility = [System.Windows.Visibility]::Hidden
    $SoundOffButton.Visibility = [System.Windows.Visibility]::Hidden
    [int32]$global:ReplayButtonCount--
    if ( [int32]$global:ReplayButtonCount -eq 0 ) {
       $ReplayButton.Visibility = [System.Windows.Visibility]::Hidden
    }
    else {
        $ReplayButton.Visibility = [System.Windows.Visibility]::Hidden
    }
    if ($timerstopcontrol -eq $True) {
        $timer.Start()
        $timerstopcontrol = $false
    }
    $Label.Content = ""
    $timerend.Stop()
})


# SoundOnButton click event 
$SoundOnButton.Add_Click({
    $VideoPlayer.Volume = 0;
    $SoundOffButton.Visibility = [System.Windows.Visibility]::Visible
    $SoundOnButton.Visibility = [System.Windows.Visibility]::Hidden
})


# SoundOffButton click event 
$SoundOffButton.Add_Click({
    $VideoPlayer.Volume = 100;
    $SoundOffButton.Visibility = [System.Windows.Visibility]::Hidden
    $SoundOnButton.Visibility = [System.Windows.Visibility]::Visible
})


# CloseButton click event 
$CloseButton.Add_Click({
    $VideoPlayer.Pause()
    $VideoPlayer.Stop()
    $Window.Close()
})


$timer.Interval = (2000)
$timerend.Interval = (30000)

$timerend.Add_Tick({
    $timerend.Stop()
    $VideoPlayer.Pause()
    $VideoPlayer.Stop()
    $Window.Close()
})
        
$timer.Add_Tick({
    if (($VideoPlayer.Position.Seconds -gt 0) -and ($VideoPlayer.Position.Seconds -lt 19)) {
        $label.Margin ="58,2,0,0"
        $Label.Content = "Windows 11 dünyasını keşfedin"
    }
    elseif (($VideoPlayer.Position.Seconds -ge 19) -and ($VideoPlayer.Position.Seconds -lt 33)) {
        $label.Margin ="16,2,0,0"
        $Label.Content = "Windows 11 ile iş akışınızı yeniden odaklayın"
    }
    elseif (($VideoPlayer.Position.Seconds -ge 33) -and ($VideoPlayer.Position.Seconds -lt 43)) {
        $label.Margin ="44,1,0,0"
        $Label.Content = "Windows 11 dünyasına hazır mısınız ?"
    }
    elseif (($VideoPlayer.Position.Seconds -ge 43) -and ($VideoPlayer.Position.Seconds -lt 45)) {
        $label.Margin ="77,1,0,0"
        $Label.Content = "Windows 11'e hemen geçin."
    }
    elseif ($VideoPlayer.Position.Seconds -ge 45) {
        $label.Margin ="62,1,0,0"
        $Label.Content = ""
        if ( [int32]$global:ReplayButtonCount -eq 0 ) {
            $ReplayButton.Visibility = [System.Windows.Visibility]::Hidden
        }
        else {
            $ReplayButton.Visibility = [System.Windows.Visibility]::Visible
        }
        $CloseButton.Visibility = [System.Windows.Visibility]::Visible
        if ($VideoPlayer.Volume -eq 100) {
            $SoundOffButton.Visibility = [System.Windows.Visibility]::Hidden
            $SoundOnButton.Visibility = [System.Windows.Visibility]::Visible
        }
        elseif ($VideoPlayer.Volume -eq 0) {
            $SoundOnButton.Visibility = [System.Windows.Visibility]::Hidden
            $SoundOffButton.Visibility = [System.Windows.Visibility]::Visible
        }
        $timer.Stop()
        $timerstopcontrol = $True
        $timerend.Start()
    }
})


# Init the OnLoad event to correct the initial state of the form
$Window.Add_Loaded($Form_StateCorrection_Load)
# Clean up the control events
$Window.Add_Closed($Form_Cleanup_FormClosed)

Start-Sleep 10
#Show Up the Window 
$Window.ShowDialog() | out-null