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
$scriptMainPath = split-path -parent $MyInvocation.MyCommand.Definition
## Get Config Veriable
$Config = "$scriptMainPath\Config.xml"
if (Test-Path $Config -ErrorAction SilentlyContinue) {
    $Xml = [xml](Get-Content -Path $Config -ErrorAction SilentlyContinue)
    [string]$scriptPath = $Xml.Configuration.Option | Select-Object -ExpandProperty scriptPath -ErrorAction SilentlyContinue
    [string]$registeryPath = $Xml.Configuration.Option | Select-Object -ExpandProperty registeryPath -ErrorAction SilentlyContinue
    [string]$LogFolderPath = $Xml.Configuration.Option | Select-Object -ExpandProperty LogFolderPath -ErrorAction SilentlyContinue
    [string]$UpgradeFileSize = $Xml.Configuration.Option | Select-Object -ExpandProperty UpgradeFileSize -ErrorAction SilentlyContinue
    [string]$ForceUpdateDate = $Xml.Configuration.Option | Select-Object -ExpandProperty ForceUpdateDate -ErrorAction SilentlyContinue
    [string]$NeedDiskSize = $Xml.Configuration.Option | Select-Object -ExpandProperty NeedDiskSize -ErrorAction SilentlyContinue
}

##*=============================================
##* LOG BUILDER
##*=============================================
function Write-Log() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        
        # Log File Path
        [Parameter(Mandatory=$false)]
        [Alias('LogPath')]
        [string]$Path=$LogFolderPath,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info"
    )

    Begin {
        $VerbosePreference = 'Continue'
    }
    Process {
		if ((Test-Path $Path)) {
			$LogSize = (Get-Item -Path $Path).Length/1MB
			$MaxLogSize = 5
		}
                
        # Log File Check
        if ((Test-Path $Path) -AND $LogSize -gt $MaxLogSize) {
            Write-Error "Log dosyası $Path yolunda zaten var ve maximum dosya boyutunu aşıyor. Yeniden oluşturuluyor."
            Remove-Item $Path -Force
            $NewLogFile = New-Item $Path -Force -ItemType File
        }

        # Create Log Folder
        elseif (-NOT(Test-Path $Path)) {
            Write-Verbose "$Path oluşturuluyor."
            $NewLogFile = New-Item $Path -Force -ItemType File
            }

        else { 
        }

        # Log file date
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Mesaj types
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
                }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
                }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
                }
            }
        
        # Log çıktı
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}


##*=============================================
##* VARIABLE DECLARATION
##*=============================================
[string]$SystemDrive = $env:SystemDrive
[string]$ComputerName = $env:COMPUTERNAME
[string]$envWinDir = $env:WINDIR
[string]$CacheFolder = "$envWinDir\ccmcache"
[string]$envProgramData = [Environment]::GetFolderPath('CommonApplicationData')
[string]$envProgramFiles = [Environment]::GetFolderPath('ProgramFiles')
[string]$envProgramFilesX86 = ${env:ProgramFiles(x86)}
[string]$LanguageLCID = Get-UICulture -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LCID
#$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
## Logged on User Session Modül
[string[]]$ReferencedAssemblies = 'System.Drawing', 'System.Windows.Forms', 'System.DirectoryServices'
Add-Type -Path "$scriptPath\UpgradeStatusMonitoring\AppDeployToolkit\AppDeployToolkitMain.cs" -ReferencedAssemblies $ReferencedAssemblies
## Upgrade Registery Key Create
[string]$BuildVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'CurrentBuild' -ErrorAction SilentlyContinue
if ($LanguageLCID -eq 1055) { $FeatureUpdateName = "*Windows 11 (*) en-us x64" }
else { $FeatureUpdateName = "Upgrade to Windows 11 (*) en-us x64" }
[int32]$Nowait = 0

##*=============================================
##* FUNCTIONS
##*=============================================


## Exit Script
## Example: ExitScript 5
Function ExitScript ([int32]$ExitCode) {
    Write-Log -Level Warn -Message "ForceMonitoring: Exit $ExitCode kodu ile çıkış sağlandı."
    Write-Log -Message "*********************** Win11 Upgrade Monitoring Scripti Sonlandırıldı. ***********************"
    [System.Environment]::Exit([int32]$ExitCode)
}


## Add Upgrade Reg Key
## Example: Add-UpgradeReg "UpgradeStatus" "1"
Function Add-UpgradeReg ($AddRegName,$AddRegValue) {
    New-ItemProperty -Path $registeryPath -Name "$AddRegName" -Value "$AddRegValue" -Force -ErrorAction Continue | Out-Null
}


## Win11 Feature Update Check
## Example: FeatureUpdateCheck or (FeatureUpdateCheck).EvaluationState
Function FeatureUpdateCheck {
    $FeatureUpdateCheck = get-wmiobject -query "SELECT * FROM CCM_SoftwareUpdate" -namespace "ROOT\ccm\ClientSDK" -ErrorAction SilentlyContinue | Where-Object {$_.Name -like "$FeatureUpdateName"} -ErrorAction SilentlyContinue 
    return $FeatureUpdateCheck
}


## LoggedOnUser Info
## Session Info: NTAccount,SID,UserName,DomainName,SessionId,SessionName,ConnectState,IsCurrentSession,IsConsoleSession,IsActiveUserSession,IsUserSession,IsRdpSession,IsLocalAdmin,LogonTime,IdleTime
## Example: LoggedOnUser or (LoggedOnUser).UserName
Function LoggedOnUser {
    $ErrorActionPreference = "SilentlyContinue"   
    [PSADT.QueryUser]::GetUserSessionInfo("$ComputerName")
    $ErrorActionPreference = "Continue"
}


## Registery Check
## Example: RegisteryCheck "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData" "NotfiyUI"
Function RegisteryCheck ($RegPath,$RegisteryValue) {
    Get-ItemProperty -Path "$RegPath" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "$RegisteryValue" -ErrorAction SilentlyContinue
}


## Restart Registery Check
## Example: RestartRegisteryCheck
Function RestartRegisteryCheck {
    if (((RegisteryCheck "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" "33700b13-ec32-4ebd-ad1d-722901b18ed8") -ne $null) -or ((RegisteryCheck "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" "355c8e5f-0d2d-472b-b76a-0d08f429b55f") -ne $null) -or ((RegisteryCheck "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData" "NotifyUI") -ne $null) -or ((RegisteryCheck "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Updates Management\Handler\UpdatesRebootStatus\33700b13-ec32-4ebd-ad1d-722901b18ed8" "RebootType") -eq "SoftReboot"))
    {
        return $True
    }
    else {
        return $False
    }
}


## Logged On User Check
## Example: LoggenOnUserCheck
Function LoggenOnUserCheck {
    $LoggedOnUserCount = (LoggedOnUser).Count
    if ($LoggedOnUserCount -eq 0) {
        Write-Log -Message "ForceMonitoring: Oturum açmış kullanıcı hesabı bulunamadı. Kullanıcı oturum açması beklenmektedir."
        While ($LoggedOnUserCount -eq 0)
        {
            Start-Sleep 300
            $LoggedOnUserCount = (LoggedOnUser).Count
            $EvaluationState = (FeatureUpdateCheck).EvaluationState
            if (($EvaluationState -eq 8) -and (RestartRegisteryCheck -eq $True)) {
                $LoggedOnUserCount = 1
            }
            if ($EvaluationState -eq 7) {
                $PercentComplete = (FeatureUpdateCheck).PercentComplete
                Write-Log -Message "ForceMonitoring: Installing - %$PercentComplete"
            }
        }
        $LoggedOnUserCount = (LoggedOnUser).Count
        $EvaluationState = (FeatureUpdateCheck).EvaluationState
        if  (($LoggedOnUserCount -eq 0) -and ($EvaluationState -eq 8) -and (RestartRegisteryCheck -eq $True)) {
            Write-Log -Level Warn -Message "ForceMonitoring: Aktif kullanıcı oturumu bulunamadı."
            Write-Log -Level Warn -Message "ForceMonitoring: EvaluationState 8 olarak algılandı. Restart kayıt defteri verileri bulundu."
            Write-Log -Level Warn -Message "ForceMonitoring: Bilgisayarın yeniden başlatılması bekleniyor."
            Write-Log -Message "*********************** Win11 Upgrade Monitoring Scripti Sonlandırıldı. ***********************"
            Restart-Computer -Force
        }
    }
}


## All Update Check
## Example: UpdateCheck or (UpdateCheck).EvaluationState
Function UpdateCheck {
    $UpdateCheck = get-wmiobject -query "SELECT * FROM CCM_SoftwareUpdate" -namespace "ROOT\ccm\ClientSDK" -ErrorAction SilentlyContinue
    return $UpdateCheck
}


## Start-MultiNotification Script (FolderName)
## Example: Start-MultiNotification "PreNotification"
Function Start-MultiNotification ($NotificationFolderName) {
    LoggenOnUserCheck
    $UpgradeStatusPath = "$scriptPath\$NotificationFolderName"
    $User=[PSADT.QueryUser]::GetUserSessionInfo("$ComputerName")
    $UserSessionID = ("$($User.SessionId)").Split("{ }")
    foreach ($SessionID in $UserSessionID) {
        $wshell = new-object -com wscript.shell
        $CommandLine = "$scriptPath\ServiceUI.exe -session:$SessionID $envWinDir\system32\wscript.exe " + '"'+"$UpgradeStatusPath\Deploy-Application.vbs"+'"' + " " + '"Deploy-Application.ps1"'
        $wshell.run("cmd /c $CommandLine",0, $False)
    }
    Write-Log -Message "ForceMonitoring: $NotificationFolderName bildirimi başlatıldı."
}


## Software Scan Policy Trigger
## Example: SoftwareScanTrigger
Function SoftwareScanTrigger {
    Invoke-CimMethod -Namespace ROOT\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = "{00000000-0000-0000-0000-000000000113}"} -ErrorAction SilentlyContinue | Out-Null
}


## Hardware Inventory Trigger
## Example: HWScanTrigger
Function HWScanTrigger {
    Write-Log -Message "Hardware Inventory policy tetikleniyor."
    Invoke-CimMethod -Namespace ROOT\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = "{00000000-0000-0000-0000-000000000001}"} -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep 300
    # Check InventoryAgent log for ignored message
    $InventoryAgentLog = "$envWinDir\CCM\Logs\InventoryAgent.Log"
    $ErrorActionPreference = "SilentlyContinue"
    $LogEntries = Select-String –Path $InventoryAgentLog –SimpleMatch "{00000000-0000-0000-0000-000000000001}" -ErrorAction SilentlyContinue | Select -Last 1 -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Continue"
    If ($LogEntries -match "already in queue. Message ignored.")
    {
        Write-Log -Message "Hardware Inventory -already in queue. Message ignored- hatası tespit edildi. Düzeltme uygulanıyor."
        try {
            # Clear the message queue
            Stop-Service -Name CcmExec -Force -ErrorAction SilentlyContinue
            Remove-Item -Path C:\Windows\CCM\ServiceData\Messaging\EndpointQueues\InventoryAgent -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
            Start-Service -Name CcmExec -ErrorAction SilentlyContinue

            # Invoke a full (resync) HWI report
            Start-Sleep -Seconds 10
            $Instance = Get-CimInstance -NameSpace ROOT\ccm\InvAgt -Query "SELECT * FROM InventoryActionStatus WHERE InventoryActionID='{00000000-0000-0000-0000-000000000001}'" -ErrorAction SilentlyContinue
            $Instance | Remove-CimInstance -ErrorAction SilentlyContinue
            Invoke-CimMethod -Namespace ROOT\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = "{00000000-0000-0000-0000-000000000001}"} -ErrorAction SilentlyContinue | Out-Null
            Write-Log -Message "HW Inventory hatası düzeltildi. Başarılı!"
        }
        catch {
            Write-Log -Level Error -Message "HW Inventory hatası düzeltilemedi!"
        }
    }
}


##*=============================================
##* UPGRADE MONITORING BEGIN
##*=============================================

## Start Task
Write-Log -Message "*********************** Win11 Upgrade Monitoring Scripti Başlatıldı. ***********************"

Write-Log -Message "ForceMonitoring: 1 dakika beklemeye alındı!"
Start-Sleep 60


## Runnig Process Check
#$Upgrade_Task_Process = RunProcess "powershell.exe" "Upgrade_Task.ps1"
$DeployApplication_Process = RunProcess "powershell.exe" "Deploy-Application.ps1"
$AppDeployToolkitMain_Process = RunProcess "powershell.exe" "AppDeployToolkitMain.ps1"

if (($DeployApplication_Process -gt 0) -or ($AppDeployToolkitMain_Process -gt 0) -or ($ForceMonitoring_Process -gt 0)) {
    if ($DeployApplication_Process -gt 0) { Write-Log -Level Error -Message "ForceMonitoring: Deploy-Application scripti çalıştığı tespit edildi. ForceMonitoring scripti sonlandırıldı!" }
    if ($AppDeployToolkitMain_Process -gt 0) { Write-Log -Level Error -Message "ForceMonitoring: AppDeployToolkitMain scripti çalıştığı tespit edildi. ForceMonitoring scripti sonlandırıldı!" }
    ExitScript 0
}


## Windows 11 Version Check
if ($BuildVersion -ge "22000") 
{
    Write-Log -Level Warn -Message "ForceMonitoring: Windows 11 versiyonu $BuildVersion olarak tespit edildi. Güncel!"
    $UpgradeStatus_Reg = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'UpgradeStatus' -ErrorAction SilentlyContinue
    if ($UpgradeStatus_Reg -ne $null) {
        Add-UpgradeReg "UpgradeStatus" "20"
        Start-Sleep 600
        HWScanTrigger
        Start-MultiNotification "SuccessNotification"
    }
    else {
        Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File `"$scriptPath\SuccessNotification\Remove_Task.ps1`"" -WindowStyle 'Hidden' -ErrorAction 'SilentlyContinue'
        Add-UpgradeReg "UpgradeStatus" "20"
        Write-Log -Message "ForceMonitoring: Hardware Scan tetiklemesi yapılmadan önce 10 dakika beklemeye alındı."
        Start-Sleep 600
        HWScanTrigger
        ExitScript 0
    }
    ExitScript 0
}
else {
    Write-Log -Message "ForceMonitoring: Windows 10 versiyonu $BuildVersion olarak tespit edildi. Başarılı!"
}


## Group Policy Check
$GP_MachinePolicy = "$envWinDir\System32\GroupPolicy\Machine\Registry.pol"
$GP_UserPolicy = "$envWinDir\System32\GroupPolicy\User\Registry.pol"
try {

$GP_MachinePolicy_SizeCheck = Get-ChildItem -path "$GP_MachinePolicy" -ErrorAction SilentlyContinue | Where-Object { ($_.Length -eq 0) -or ($_.Length -lt 100) } -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
$GP_UserPolicy_SizeCheck = Get-ChildItem -path "$GP_UserPolicy" -ErrorAction SilentlyContinue | Where-Object { ($_.Length -eq 0) } -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
if (($GP_MachinePolicy_SizeCheck -ne $null)) { Remove-Item -Path "$GP_MachinePolicy_SizeCheck" -Force }
if ($GP_UserPolicy_SizeCheck -ne $null) { Remove-Item -Path "$GP_UserPolicy_SizeCheck" -Force }

$GP_MachinePolicy_Check = Get-Content -path "$GP_MachinePolicy" -ErrorAction SilentlyContinue | Where-Object { $_ -notlike "PReg*" } -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSPath -ErrorAction SilentlyContinue
$GP_UserPolicy_Check = Get-Content -path "$GP_UserPolicy" -ErrorAction SilentlyContinue | Where-Object { $_ -notlike "PReg*" } -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSPath -ErrorAction SilentlyContinue

if (($GP_MachinePolicy_Check -ne $null)) { Remove-Item -Path "$GP_MachinePolicy_Check" -Force }
if ($GP_UserPolicy_Check -ne $null) { Remove-Item -Path "$GP_UserPolicy_Check" -Force }
if (($GP_MachinePolicy_SizeCheck -ne $null) -or ($GP_UserPolicy_SizeCheck -ne $null) -or ($GP_MachinePolicy_Check -ne $null) -or ($GP_UserPolicy_Check -ne $null)) { 
    gpupdate /force | Out-Null
    Write-Log -Message "ForceMonitoring: Group Policy onarımı yapıldı. Başarılı!"
    Start-Sleep 300
    if (FeatureUpdateCheck -eq $null) { SoftwareScanTrigger }
        Start-Sleep 120
    }
    else {
        Write-Log -Message "ForceMonitoring: Group Policy sorunu tespit edilmedi. Başarılı!"
    }
}
catch {
    Write-Log -Level Error -Message "ForceMonitoring: Group Policy onarımı yapılamadı. Başarısız!"
    Add-UpgradeReg "UpgradeStatus" "4"
}


## EvaluationState Check
$EvaluationState = (FeatureUpdateCheck).EvaluationState
if (($EvaluationState -eq $null) -or ($EvaluationState -ne 7)) {
    Write-Log -Message "ForceMonitoring: EvaluationState değeri 7 olarak algılanmadığı için beklemeye alındı."
    While (($EvaluationState -ne 7) -and ($Nowait -eq 0))
    {
        Start-Sleep 300
        $EvaluationState = (FeatureUpdateCheck).EvaluationState
        if (($EvaluationState -eq 8) -and ((RestartRegisteryCheck) -eq $True)) { $Nowait = 1; Write-Log -Level Warn -Message "UpgradeStatusMonitoring: EvaluationState değeri 8 olarak algılandı." }
    }
}
$EvaluationState = (FeatureUpdateCheck).EvaluationState
if (($EvaluationState -eq 8) -and ((RestartRegisteryCheck) -eq $True)) {
    Start-MultiNotification "UpgradeNotification"
}
elseif ($EvaluationState -eq 7) {
    Start-MultiNotification "PreNotification"
}


##*=============================================
##* UPGRADE MONITORING FINISH
##*=============================================
Write-Log -Message "*********************** Win11 Upgrade Monitoring Scripti Sonlandırıldı. ***********************"