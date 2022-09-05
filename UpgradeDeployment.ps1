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

# Bu script Revision numarasına göre güncellenmesini ve dosya bütünlüğü kontrol etmektedir.
# Task Scheduler'da görevin varlığı kontrol edilerek yoksa oluşturulup tetiklenmektedir var ise sadece tetiklenecek şekilde yapılandırılmıştır. 


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
    [int32]$FileRevision = $Xml.Configuration.Option | Select-Object -ExpandProperty FileRevision -ErrorAction SilentlyContinue
}


##*=============================================
##* VARIABLE DECLARATION
##*=============================================
[int32]$File_Revision = $FileRevision
[string]$TaskName = "Win11_Upgrade"
[string]$SystemDrive = $env:SystemDrive
[string]$envWinDir = $env:WINDIR
$CurrentScriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$UpgradeFolderPath = $scriptPath
$UpgradeMainFolderPath = Split-Path -Path $UpgradeFolderPath -Parent
[string]$BuildVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'CurrentBuild' -ErrorAction SilentlyContinue

$YH_Reg_Key_Test = (Test-Path $registeryPath -ErrorAction SilentlyContinue)
if ($YH_Reg_Key_Test -eq $False) { New-Item -Path $registeryPath -Force -ErrorAction Continue | Out-Null }


##*=============================================
##* FUNCTIONS
##*=============================================


## Log Builder
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


## Exit Script
## Example: ExitScript 5
Function ExitScript ([int32]$ExitCode) {
    Write-Log -Level Warn -Message "UpgradeDeployment: Exit $ExitCode kodu ile çıkış sağlandı."
    Write-Log -Message "*********************** Win11 Upgrade Deployment Sonlandırıldı. ***********************"
    [System.Environment]::Exit([int32]$ExitCode)
}


## Process Check
## Example: RunProcess "powershell.exe" "Pre_Monitoring.ps1"
Function RunProcess ($ProcessName,$ProcessCommand) {
    (Get-WmiObject Win32_Process -Filter "name = ""$ProcessName""" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$ProcessCommand*"} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CommandLine -ErrorAction SilentlyContinue).count
}


## TriggerTask
## Example: TriggerTask
Function TriggerTask {
    Write-Log -Message "UpgradeDeployment: $TaskName Taskı çalıştırıldı."
    Start-ScheduledTask -TaskName "$TaskName" -ErrorAction SilentlyContinue
}

## Machine Policy Trigger
## Example: MachinePolicyTrigger
Function MachinePolicyTrigger {
    Write-Log -Message "Machine policy tetikleniyor."
    Invoke-CimMethod -Namespace ROOT\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = "{00000000-0000-0000-0000-000000000021}"} -ErrorAction SilentlyContinue | Out-Null
}


## Hardware Inventory Trigger
## Example: HWScanTrigger
Function HWScanTrigger {
    Write-Log -Message "Hardware Inventory policy tetikleniyor."
    Invoke-CimMethod -Namespace ROOT\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = "{00000000-0000-0000-0000-000000000001}"} -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep 60
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

## Start Upgrade Deployment
Write-Log -Message "*********************** Win11 Upgrade Deployment Başlatıldı. ***********************"


$UpgradeFile_RV = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'UpgradeFile_RV' -ErrorAction SilentlyContinue
if ($UpgradeFile_RV -ne $null) {
    Write-Log -Message "UpgradeDeployment: File Revision: $File_Revision -- Registery File Revision: $UpgradeFile_RV"
    if ($File_Revision -ne $UpgradeFile_RV) {
        Write-Log -Level Warn -Message "UpgradeDeployment: File Revision değeri Registery File Revision değeriyle eşleşmedi."
    }
    else {
        Write-Log -Message "UpgradeDeployment: File Revision değeri Registery File Revision değeriyle eşleşti."
    }
}
else {
    Write-Log -Message "UpgradeDeployment: File Revision: $File_Revision -- Registery File Revision değeri bulunamadı. Oluşturuluyor."
}


##*=============================================
##* WINDOWS 10 VERSION CHECK
##*=============================================
if ($BuildVersion -ge "22000") 
{
    Write-Log -Level Warn -Message "UpgradeDeployment: Windows 11 versiyonu $BuildVersion olarak tespit edildi. Güncel!"
    MachinePolicyTrigger
    HWScanTrigger
    ExitScript 0
}
elseif (($BuildVersion -lt "19041")) {
    Write-Log -Level Warn -Message "UpgradeDeployment: Eski Windows 10 ($BuildVersion) versiyonu tespit edildi. Sonlandırıldı!"
    HWScanTrigger
    ExitScript 0
}
else {
    Write-Log -Message "UpgradeDeployment: Windows 10 versiyonu $BuildVersion olarak tespit edildi. İşlemlere devam ediliyor."
}


##*=============================================
##* UPGRADE DEPLOYMENT BEGINS
##*=============================================
## Upgrade File Revision Test
$UpgradeFile_RV = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'UpgradeFile_RV' -ErrorAction SilentlyContinue
if (($UpgradeFile_RV -ne $null) -and ($UpgradeFile_RV -ne $File_Revision)) {
    if (Test-Path $UpgradeFolderPath) {
        ## PreNotification - UpgradeStatusMonitoring - Upgrade_Task_Process ps1 kill
        $Upgrade_Task_Process = RunProcess "powershell.exe" "Upgrade_Task.ps1"
        $ForceMonitoring_Process = RunProcess "powershell.exe" "ForceMonitoring.ps1"
        $PreNotification_Process = RunProcess "powershell.exe" "PreNotification"
        $UpgradeStatusMonitoring_Process = RunProcess "powershell.exe" "UpgradeStatusMonitoring"
        if (($ForceMonitoring_Process -gt 0) -or ($Upgrade_Task_Process -gt 0) -or ($PreNotification_Process -gt 0) -or ($UpgradeStatusMonitoring_Process -gt 0)) {
        ## Process Log
        if ($Upgrade_Task_Process -gt 0) { Write-Log -Level Warn -Message "UpgradeDeployment: Upgrade_Task.ps1 scripti çalışmaktadır." }
        if ($ForceMonitoring_Process -gt 0) { Write-Log -Level Warn -Message "UpgradeDeployment: ForceMonitoring.ps1 scripti çalışmaktadır." }
        if ($PreNotification_Process -gt 0) { Write-Log -Level Warn -Message "UpgradeDeployment: PreNotification bildirimi çalışmaktadır." }
        if ($UpgradeStatusMonitoring_Process -gt 0) { Write-Log -Level Warn -Message "UpgradeDeployment: UpgradeStatusMonitoring bildirimi çalışmaktadır." }
        $RunningAppID = Get-WmiObject Win32_Process -Filter "name = ""powershell.exe""" -ErrorAction SilentlyContinue | Where-Object { ($_.CommandLine -like "*Upgrade_Task.ps1*") -or ($_.CommandLine -like "*ForceMonitoring.ps1*") -or ($_.CommandLine -like "*PreNotification*") -or ($_.CommandLine -like "*UpgradeStatusMonitoring*")} -ErrorAction SilentlyContinue | Select -ExpandProperty ProcessId -ErrorAction SilentlyContinue
            If ($RunningAppID -ne $null) {
               Stop-Process -Id $RunningAppID -Force -ErrorAction SilentlyContinue
               Write-Log -Message "UpgradeDeployment: Çalışan işlemler sonlandırıldı."
            }
        }
        else {
            Write-Log -Message "UpgradeDeployment: Çalışan bir işlem bulunamadı."
        }
        ## Remove Folder
        Remove-Item -Path "$UpgradeFolderPath" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log -Message "UpgradeDeployment: $UpgradeFolderPath klasörü siliniyor."
        if (Test-Path $UpgradeFolderPath) { Write-Log -Level Warn -Message "UpgradeDeployment: $UpgradeFolderPath klasörü tam silinemedi. İşlemlere devam ediliyor." }
        else { Write-Log -Message "UpgradeDeployment: $UpgradeFolderPath klasörü başarıyla silindi." }
    }
}


## If there is no upgrade folder, create it
if (!(Test-Path $UpgradeFolderPath)) {
    New-Item -Path "$UpgradeFolderPath" -ItemType Directory -Force -ErrorAction Continue | Out-Null
    Write-Log -Message "UpgradeDeployment: $UpgradeFolderPath klasörü bulunamadı. Oluşturuldu."
    $wshell = new-object -com wscript.shell
    $CommandLine = "icacls $UpgradeMainFolderPath /grant Users:(OI)(CI)(RX) System:(OI)(CI)(F) Administrators:(OI)(CI)(F) /inheritance:r"
    $wshell.run("cmd /c $CommandLine",0, $False)
}


## Upgrade file integrity check
$UpgradeFileTest1 = "$UpgradeFolderPath\Upgrade_Task.ps1"
$UpgradeFileTest2 = "$UpgradeFolderPath\ServiceUI.exe"
$UpgradeFileTest3 = "$UpgradeFolderPath\UpgradeNotification\Deploy-Application.ps1"
$UpgradeFileTest4 = "$UpgradeFolderPath\Upgrade_Task.vbs"
if ((!(Test-Path $UpgradeFileTest1)) -or (!(Test-Path $UpgradeFileTest2)) -or (!(Test-Path $UpgradeFileTest3)) -or (!(Test-Path $UpgradeFileTest4))) {
    Copy-Item -Path "$CurrentScriptPath\*" -Destination "$UpgradeFolderPath" -Recurse -Force
    Write-Log -Message "UpgradeDeployment: Güncel dosyalar $UpgradeFolderPath adresine kopyalandı."
    New-ItemProperty -Path $registeryPath -Name "UpgradeFile_RV" -Value "$File_Revision" -Force -ErrorAction Continue | Out-Null
    Write-Log -Message "UpgradeDeployment: Güncel revision numarası registery'a yazıldı."
}


## Task scheduler control
$GetUpgradeTask = (Get-ScheduledTask -TaskPath "\" -TaskName "$TaskName" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TaskName -ErrorAction SilentlyContinue).Count
if ($GetUpgradeTask -eq 0) {
    ## Create Task Scheduler
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $User= "NT AUTHORITY\SYSTEM"
    $Action= New-ScheduledTaskAction -Execute "$envWinDir\system32\wscript.exe" -Argument "$UpgradeFolderPath\Upgrade_Task.vbs"
    Register-ScheduledTask -TaskName "$TaskName" -User $User -Action $Action -Trigger $Trigger -Settings $Set –Force
    Start-Sleep 10
    Write-Log -Message "UpgradeDeployment: $TaskName adında task bulunamadı. Oluşturuldu."
    TriggerTask
}
else {
    Write-Log -Message "UpgradeDeployment: $TaskName adında task bulundu."
    ## Trigger Task
    $Upgrade_Task_Process = RunProcess "powershell.exe" "Upgrade_Task.ps1"
    if ($Upgrade_Task_Process -eq 0) {
        TriggerTask
    }
}


## Finish Upgrade Deployment
Write-Log -Message "*********************** Win11 Upgrade Deployment Sonlandırıldı. ***********************"

##*=============================================
##* UPGRADE DEPLOYMENT FINISH
##*=============================================