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
##* TASK SEQUENCE ENABLE-DISABLE CHECK
##*=============================================
[boolean]$Task1  =  $False  # Task Name: App Check
[boolean]$Task2  =  $True   # Task Name: System Type Check
[boolean]$Task3  =  $False  # Task Name: En-Us Language Check
[boolean]$Task4  =  $True   # Task Name: Group Policy Files Fix
[boolean]$Task5  =  $True   # Task Name: Free Space Disk Check, Cleaner and Notification
[boolean]$Task6  =  $True   # Task Name: Hardware Inventory Fix
[boolean]$Task7  =  $False  # Task Name: Null
[boolean]$Task8  =  $True   # Task Name: Feature Update Check
[boolean]$Task9  =  $True   # Task Name: Feature Update File Check
[boolean]$Task10 =  $True   # Task Name: Feature Update Monitoring
[boolean]$Task11 =  $True   # Task Name: Feature Update File Monitoring
[boolean]$Task12 =  $True   # Task Name: Start Multi Notification


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
## Logged on User Session Modül
[string[]]$ReferencedAssemblies = 'System.Drawing', 'System.Windows.Forms', 'System.DirectoryServices'
Add-Type -Path "$scriptPath\UpgradeStatusMonitoring\AppDeployToolkit\AppDeployToolkitMain.cs" -ReferencedAssemblies $ReferencedAssemblies
[string]$LanguageLCID = Get-UICulture -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LCID
[string]$LanguageName = Get-UICulture -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
[string]$BuildVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'CurrentBuild' -ErrorAction SilentlyContinue
[boolean]$Is64Bit = [boolean]((Get-WmiObject -Class 'Win32_Processor' -ErrorAction 'SilentlyContinue' | Where-Object { $_.DeviceID -eq 'CPU0' } | Select-Object -ExpandProperty 'AddressWidth') -eq 64)
If ($Is64Bit) { [string]$envOSArchitecture = '64-bit' } Else { [string]$envOSArchitecture = '32-bit' }
## Upgrade Registery Key Create
$UpgradeRegKeyTest = (Test-Path $registeryPath -ErrorAction SilentlyContinue)
if ($UpgradeRegKeyTest -eq $False) { New-Item -Path $registeryPath -Force -ErrorAction Continue | Out-Null }
$UpgradeStatus_Reg = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'UpgradeStatus' -ErrorAction SilentlyContinue
if ($UpgradeStatus_Reg -eq $null) { New-ItemProperty -Path $registeryPath -Name "UpgradeStatus" -Value "0" -Force -ErrorAction Continue | Out-Null }
$ACProcessCheck = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'ACProcessCheck' -ErrorAction SilentlyContinue
if ($ACProcessCheck -ne $null) { Remove-ItemProperty -Path $registeryPath -Name 'ACProcessCheck' -ErrorAction SilentlyContinue -Force }
if ($LanguageLCID -eq 1055) { $FeatureUpdateName = "*Windows 11 (*) en-us x64" }
else { $FeatureUpdateName = "Upgrade to Windows 11 (*) en-us x64" }


##*=============================================
##* FUNCTIONS
##*=============================================


## Process Check
## Example: RunProcess "powershell.exe" "Pre_Monitoring.ps1"
Function RunProcess ($ProcessName,$ProcessCommand) {
    (Get-WmiObject Win32_Process -Filter "name = ""$ProcessName""" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$ProcessCommand*"} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CommandLine -ErrorAction SilentlyContinue).count
}


## Exit Script
## Example: ExitScript 5
Function ExitScript ([int32]$ExitCode) {
    $ForceRequiredReg = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'ForceRequired' -ErrorAction SilentlyContinue
    if (($ForceRequiredReg -ne $null) -and ($ForceRequiredReg -eq 1)) { 
        $ForceMonitoring_Process = RunProcess "powershell.exe" "ForceMonitoring.ps1"
        if (($ForceMonitoring_Process -eq 0) -and ($ForceFeatureProcess -ne $True)) {
            Add-UpgradeReg "PreNotification_Snooze" "0"
            Add-UpgradeReg "PreNotification_Silently" "1"
            Write-Log -Level Warn -Message "Upgrade_Task: ForceRequired algılandı. Force Monitoring scripti başlatıldı."
            Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File `"$scriptPath\ForceMonitoring.ps1`"" -WindowStyle 'Hidden' -ErrorAction 'SilentlyContinue'
        }
        Write-Log -Level Warn -Message "Upgrade_Task: Exit 0 kodu ile çıkış sağlandı."
        Write-Log -Message "*********************** Win11 Upgrade Task Sequence Sonlandırıldı. ***********************"
        [System.Environment]::Exit(0)
    }
    else { 
        Write-Log -Level Warn -Message "Upgrade_Task: Exit $ExitCode kodu ile çıkış sağlandı."
        Write-Log -Message "*********************** Win11 Upgrade Task Sequence Sonlandırıldı. ***********************"
        [System.Environment]::Exit([int32]$ExitCode)
    }
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
    if (($FeatureUpdateCheck -ne $null) -and ($FeatureUpdateCheck.Deadline -eq $null) -and ($FeatureUpdateCheck.EvaluationState -ne 8)) {
        Write-Log -Level Error -Message "Upgrade_Task: Win11 available feature update gönderimi tespit edildi."
        ExitScript 0
    }

    if (($FeatureUpdateCheck -ne $null) -and (($FeatureUpdateCheck.Name -like "*consumer editions*") -or ($FeatureUpdateCheck.Name -like "*tüketici sürümleri*"))) {
        $UpgradeFileSize = "3905707736"
    }

    $ForceRequiredReg = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'ForceRequired' -ErrorAction SilentlyContinue
    if ((($ForceRequiredReg -ne $null) -and ($ForceRequiredReg -eq 1)) -or ($FeatureUpdateCheck.Deadline -like "*$ForceUpdateDate*")) { 
        $ForceMonitoring_Process = RunProcess "powershell.exe" "ForceMonitoring.ps1"
        if ($ForceMonitoring_Process -eq 0) {
            Add-UpgradeReg "PreNotification_Snooze" "0"
            Add-UpgradeReg "PreNotification_Silently" "1"
            Write-Log -Level Warn -Message "Upgrade_Task: ForceRequired algılandı. Force Monitoring scripti başlatıldı."
            Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File `"$scriptPath\ForceMonitoring.ps1`"" -WindowStyle 'Hidden' -ErrorAction 'SilentlyContinue'
            $ForceFeatureProcess = $True
        }
        ExitScript 0
    }
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
        Write-Log -Message "Upgrade_Task: Oturum açmış kullanıcı hesabı bulunamadı. Kullanıcı oturum açması beklenmektedir."
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
                Write-Log -Message "Upgrade_Task: Installing - %$PercentComplete"
            }
        }
        $LoggedOnUserCount = (LoggedOnUser).Count
        $EvaluationState = (FeatureUpdateCheck).EvaluationState
        if  (($LoggedOnUserCount -eq 0) -and ($EvaluationState -eq 8) -and (RestartRegisteryCheck -eq $True)) {
            Write-Log -Level Warn -Message "Upgrade_Task: Aktif kullanıcı oturumu bulunamadı."
            Write-Log -Level Warn -Message "Upgrade_Task: EvaluationState 8 olarak algılandı. Restart kayıt defteri verileri bulundu."
            Write-Log -Level Warn -Message "Upgrade_Task: Bilgisayar yeniden başlatılıyor."
            Write-Log -Message "*********************** Win11 Upgrade Task Sequence Sonlandırıldı. ***********************"
            Add-UpgradeReg "RestartNotification_Silent" "1"
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


## Win11 Upgrade Trigger
## Example: UpgradeTrigger
Function UpgradeTrigger {
    ## Farklı bir update yükleniyorsa aşağıdaki işlemleri script bir sonraki çalışmasına kadar sonlandırsın.
    $NotFeatureUpdateCheck = (UpdateCheck | Where-Object { ($_.Name -notlike "$FeatureUpdateName") -and ($_.EvaluationState -gt 0) -and ($_.EvaluationState -ne 13)} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue).Count
    if ($NotFeatureUpdateCheck -gt 0) {
        Write-Log -Level Error -Message "Upgrade_Task: Farklı bir update yüklemesi tespit edildiği için Trigger edilmedi. Başarısız!"
        ExitScript 0
    }
    
    $MissingUpdates = Get-WmiObject -Class CCM_SoftwareUpdate -Filter ComplianceState=0 -Namespace root\CCM\ClientSDK -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $FeatureUpdateName } -ErrorAction SilentlyContinue
    $MissingUpdatesReformatted = @($MissingUpdates | ForEach-Object -ErrorAction SilentlyContinue {if($_.ComplianceState -eq 0){[WMI]$_.__PATH}})
    $InstallReturn = Invoke-WmiMethod -ComputerName $ComputerName -Class CCM_SoftwareUpdatesManager -Name InstallUpdates -ArgumentList (,$MissingUpdatesReformatted) -Namespace root\ccm\clientsdk -ErrorAction SilentlyContinue
    Write-Log -Message "Upgrade_Task: Win11 Upgrade Software Center'da trigger edildi."
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
    $RestartNotification_Silent = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'RestartNotification_Silent' -ErrorAction SilentlyContinue
    if ($RestartNotification_Silent -eq $null) { Write-Log -Message "Upgrade_Task: $NotificationFolderName bildirimi başlatıldı." }
}


## Get Disk Size Info
## Example: GetDiskSizeInfo
function GetDiskSizeInfo() {
$diskReport = Get-WmiObject Win32_logicaldisk
$drive = $diskReport | Where-Object { $_.DeviceID -eq $SystemDrive} | Select-Object @{n="FreeSpace";e={[math]::Round($_.FreeSpace/1GB,2)}}
$result = @{
FreeSpace = $drive.Freespace
}
    return $result.Values
}


## Rerun Task Scheduler
## Example: RerunTaskScheduler "Win11_Upgrade"
Function RerunTaskScheduler ([string]$TaskSchedulerName) {
    Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File `"$scriptPath\RerunTaskScheduler.ps1`" `"$TaskSchedulerName`"" -WindowStyle 'Hidden' -ErrorAction 'SilentlyContinue'
    Write-Log -Message "Upgrade_Task: Win11 Upgrade Task yeniden başlatılıyor.."
    ExitScript 0
}


## Software Scan Policy Trigger
## Example: SoftwareScanTrigger
Function SoftwareScanTrigger {
    Write-Log -Message "Software scan tetikleniyor."
    Invoke-CimMethod -Namespace ROOT\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = "{00000000-0000-0000-0000-000000000113}"} -ErrorAction SilentlyContinue | Out-Null
    Invoke-CimMethod -Namespace ROOT\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = "{00000000-0000-0000-0000-000000000108}"} -ErrorAction SilentlyContinue | Out-Null
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



##*=============================================
##* TASK SEQUENCE PRE CHECK
##*=============================================

## Start Task
Write-Log -Message "**************************************************************************************"
Write-Log -Message "*********************** Win11 Upgrade Task Sequence Başlatıldı. ***********************"


## Logged On User Check
$LoggedOnUser_Count = (LoggedOnUser).Count
if ($LoggedOnUser_Count -gt 0) {
    $LoggedOnUserName = (LoggedOnUser).UserName
    Write-Log -Message "Upgrade_Task: Login User Name: $LoggedOnUserName"
}
else {
    Write-Log -Level Warn -Message "Upgrade_Task: Aktif kullanıcı oturumu algılanmadı."
}


## Windows Version Check
if ($BuildVersion -ge "22000") 
{
    Write-Log -Level Warn -Message "Upgrade_Task: Windows 11 versiyonu $BuildVersion olarak tespit edildi. Güncel!"
    $UpgradeStatus_Reg = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'UpgradeStatus' -ErrorAction SilentlyContinue
    if ($UpgradeStatus_Reg -ne $null) {
        Add-UpgradeReg "UpgradeStatus" "20"
        Write-Log -Message "Upgrade_Task: Hardware Scan tetiklemesi yapılmadan önce 10 dakika beklemeye alındı."
        Start-Sleep 600
        HWScanTrigger
        MachinePolicyTrigger
        Start-MultiNotification "SuccessNotification"
    }
    else {
        Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File `"$scriptPath\SuccessNotification\Remove_Task.ps1`"" -WindowStyle 'Hidden' -ErrorAction 'SilentlyContinue' 
        Add-UpgradeReg "UpgradeStatus" "20"
        Write-Log -Message "Upgrade_Task: Hardware Scan tetiklemesi yapılmadan önce 10 dakika beklemeye alındı."
        Start-Sleep 600
        HWScanTrigger
        MachinePolicyTrigger
        ExitScript 0
    }
    ExitScript 0
}
elseif (($BuildVersion -lt "19041")) {
    Write-Log -Level Warn -Message "Upgrade_Task: EsEski ndows 10 0$BuildVersion) versiyonu tespit edildi. Sonlandırıldı!"
    Write-Log -Message "Upgrade_Task: Hardware Scan tetiklemesi yapılmadan önce 10 dakika beklemeye alındı."
    Start-Sleep 600
    HWScanTrigger
    ExitScript 0
}
else {
    Write-Log -Message "Upgrade_Task: Windows 10 versiyonu $BuildVersion olarak tespit edildi. Başarılı!"
}


## Runnig Process Check
#$Upgrade_Task_Process = RunProcess "powershell.exe" "Upgrade_Task.ps1"
$DeployApplication_Process = RunProcess "powershell.exe" "Deploy-Application.ps1"
$AppDeployToolkitMain_Process = RunProcess "powershell.exe" "AppDeployToolkitMain.ps1"
$ForceMonitoring_Process = RunProcess "powershell.exe" "ForceMonitoring.ps1"

if (($DeployApplication_Process -gt 0) -or ($AppDeployToolkitMain_Process -gt 0) -or ($ForceMonitoring_Process -gt 0)) {
    if ($DeployApplication_Process -gt 0) { Write-Log -Level Error -Message "Upgrade_Task: Deploy-Application scripti çalıştığı tespit edildi. Upgrade_Task scripti sonlandırıldı!" }
    if ($AppDeployToolkitMain_Process -gt 0) { Write-Log -Level Error -Message "Upgrade_Task: AppDeployToolkitMain scripti çalıştığı tespit edildi. Upgrade_Task scripti sonlandırıldı!" }
    if ($ForceMonitoring_Process -gt 0) { Write-Log -Level Error -Message "Upgrade_Task: ForceMonitoring scripti çalıştığı tespit edildi. Upgrade_Task scripti sonlandırıldı!" }
    ExitScript 0
}


<## If it is a Desktop Computers, make the registery value "PreNotification_Snooze" 0.
if (($ComputerName -like "D*") -or ($ComputerName -like "T*")) {
    Add-UpgradeReg "PreNotification_Snooze" "0"
    Write-Log -Level Warn -Message "Upgrade_Task: Bilgisayar tipi Desktop olarak tespit edildi. Erteleme hakkı iptal edildi."
}#>


## Feature Update Force Check
FeatureUpdateCheck


## Force gönderim değil ise farklı bir update yükleniyorsa aşağıdaki işlemleri script bir sonraki çalışmasına kadar sonlandırsın.
$NotFeatureUpdateCheck = (UpdateCheck | Where-Object { ($_.Name -notlike "$FeatureUpdateName") -and ($_.EvaluationState -gt 0) -and ($_.EvaluationState -ne 13)} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue).Count
if ($NotFeatureUpdateCheck -gt 0) {
    Write-Log -Level Error -Message "Upgrade_Task: Farklı bir update yüklemesi tespit edildi. Tekrar kontrol için 15 dakika beklemeye alındı."
    Start-Sleep 900
    $NotFeatureUpdateCheck = (UpdateCheck | Where-Object { ($_.Name -notlike "$FeatureUpdateName") -and ($_.EvaluationState -gt 0) -and ($_.EvaluationState -ne 13)} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue).Count
    if ($NotFeatureUpdateCheck -gt 0) {
        Write-Log -Level Error -Message "Upgrade_Task: Farklı bir update yüklemesi tespit edildi. Başarısız!"
        ExitScript 0
    }
    else {
        Write-Log -Level Error -Message "Upgrade_Task: Tekrar kontrol sağlandı. Farklı bir update bulunamadı."
    }
}


## Evulation State Check
$EvaluationState = (FeatureUpdateCheck).EvaluationState
if ($EvaluationState -gt 0) { 
    Write-Log -Message "Upgrade_Task: Başlangıçta EvaluationState değerinin varlığı algılandı. 15 dk beklemeye alındı."
    Start-Sleep 900
    $EvaluationState = (FeatureUpdateCheck).EvaluationState
    if ($EvaluationState -eq 6) {
        ## Waiting Install  
        Write-Log -Message "Upgrade_Task: Başlangıçta EvaluationState 6 olarak algılandı. Beklemeye alındı."
        ## try it for 3 hours
        [int32]$WaitingInstallCount = 0
        While (($EvaluationState -eq 6) -and $WaitingInstallCount -lt 36)
        {
            Start-Sleep 300
            $WaitingInstallCount++
            $EvaluationState = (FeatureUpdateCheck).EvaluationState
        }

        ## Waiting Stuck Fix
        $EvaluationState = (FeatureUpdateCheck).EvaluationState
        ## Farklı bir update yükleniyorsa aşağıdaki işlemleri yapmasın.
        if ($EvaluationState -eq 6) {
            Write-Log -Message "Upgrade_Task: Waiting Install Stuck hatası tespit edildi. Onarım başlatıldı."
            # 1- Windows update service stop
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            # 2- Software Distribution Download Subitems Delete
            $SoftwareDistribution = "$envWinDir\SoftwareDistribution\Download\*"
            Remove-Item -Path $SoftwareDistribution -Recurse -Force -ErrorAction SilentlyContinue
            # 3- Windows update service start
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            # 4- SMSAgentHost restart service
            Restart-Service -Name CcmExec -Force -ErrorAction SilentlyContinue
            Start-Sleep 90
            # 5- UpgradeTrigger
            UpgradeTrigger
            # 6- Rerun Task Scheduler
            Start-Sleep 240
            RerunTaskScheduler "Win11_Upgrade"
        }
    }
    elseif ($EvaluationState -eq 7) {
        ## Installing
        Write-Log -Message "Upgrade_Task: Başlangıçta EvaluationState 7 olarak algılandı."
        Start-MultiNotification "UpgradeStatusMonitoring"
        ExitScript 0 
    }
    elseif ($EvaluationState -eq 8) {
        if (RestartRegisteryCheck -eq $True) {
            ## Pending Restart
            Write-Log -Message "Upgrade_Task: Başlangıçta EvaluationState 8 olarak algılandı. Restart kayıt defteri verileri bulundu."
            Start-MultiNotification "UpgradeNotification"
            ExitScript 0
        }
        else {
            Write-Log -Level Error -Message "Upgrade_Task: Başlangıçta EvaluationState 8 olarak algılandı. Restart kayıt defteri verileri bulunamadı."
            UpgradeTrigger
            Write-Log -Message "Upgrade_Task: Trigger edildi. 10 dakika beklemeye alındı."
            Start-Sleep 600
            $EvaluationState = (FeatureUpdateCheck).EvaluationState
            if ($EvaluationState -eq 8) {
                if (RestartRegisteryCheck -eq $True) {
                    ## Pending Restart
                    Write-Log -Message "Upgrade_Task: Başlangıçta EvaluationState 8 olarak algılandı. Restart kayıt defteri verileri bulundu."
                    Start-MultiNotification "UpgradeNotification"
                    ExitScript 0
                }
                else {
                    Add-UpgradeReg "UpgradeStatus" "0"
                    ExitScript 0
                }
            }
            else {
                RerunTaskScheduler "Win11_Upgrade"  
            }
        }
    }
    elseif ($EvaluationState -eq 13) {
        ## Error
        $FeatureErrorCode = (FeatureUpdateCheck).ErrorCode
        Write-Log -Level Error -Message "Upgrade_Task: Error Code: $FeatureErrorCode."
        Write-Log -Message "Upgrade_Task: Başlangıçta EvaluationState 13 olarak algılandı. 5 dakika beklemeye alındı."
        Add-UpgradeReg "Upgrade_ErrorCode" "$FeatureErrorCode"
        Start-Sleep 300
        Write-Log -Message "Upgrade_Task: 5 dakika bekleme sonrası $FeatureErrorCode hata kodu kontrolü sağlanıyor."
        if ( $FeatureErrorCode -eq "2149842976" ) {
            Write-Log -Message "Upgrade_Task: 2149842976 numaralı hata kodu tespit edildi. Fix uygulanıyor."
            Get-Service wuauserv | Stop-Service -Force
            Write-Log -Message "Upgrade_Task: Windows update servisi durduruldu."
            Get-Item -Path "C:\Windows\SoftwareDistribution\Download\*" | Remove-Item -Force -Recurse
            Write-Log -Message "Upgrade_Task: SoftwareDistribution Download klasörü dosyaları temizlendi."
            Start-Service wuauserv
            Write-Log -Message "Upgrade_Task: Windows update servisi başlatıldı."
            Write-Log -Message "Upgrade_Task: 5 dakika beklemeye alındı."
            Start-Sleep 300
        }
        if ( $FeatureErrorCode -eq "3247440398" ) {
            Write-Log -Message "Upgrade_Task: 3247440398 numaralı hata kodu tespit edildi. Disk alanı kontrolü sağlanıyor."
            if ((GetDiskSizeInfo) -lt 10) { 
                Write-Log -Level Error -Message "Upgrade_Task: Minumum gereken disk alanı mevcut değil!"
                [string]$FreeDiskSizeInfo = GetDiskSizeInfo
                Write-Log -Message "Upgrade_Task: Mevcut disk alanı: $FreeDiskSizeInfo"
                # Basic Disk Clean
                $CleanedCheck = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'DiskCleaner' -ErrorAction SilentlyContinue
                if ($CleanedCheck -eq $null) {
                    Write-Log -Level Error -Message "Upgrade_Task: DiskCleaner registery değeri bulunmadı. DiskCleaner temizlik işlemi başlatıldı."
                    ## CCMCache Clean
                    $ErrorActionPreference = "SilentlyContinue"
                    $UIResourceMgr = New-Object -ComObject UIResource.UIResourceMgr
                    $Cache = $UIResourceMgr.GetCacheInfo()
                    $UpgradeTask = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*Upgrade_Task.ps1*" | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
                    $ExcludeWUB = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*WindowsUpdateBox*" | Where-Object { $_.VersionInfo -like "*Windows 11*" } | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
                    $ExcludeBitlockerBoot = Get-ChildItem -Path $CacheFolder -Recurse -Filter "boot*.wim" | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
                    $ExcludeBitlockerNotification = Get-ChildItem -Path $CacheFolder -Recurse -Filter "MultiSession-Notification.ps1" | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
                    $CacheElements = $Cache.GetCacheElements() | Where-Object { ($_.Location -notlike "$UpgradeTask") -and ($_.Location -notlike "$ExcludeWUB") -and ($_.Location -notlike "$ExcludeBitlockerBoot") -and ($_.Location -notlike "$ExcludeBitlockerNotification") }
                    foreach ($Element in $CacheElements)
                    {
                        $Cache.DeleteCacheElement($Element.CacheElementID)
                    }
                    $ErrorActionPreference = "Continue"
            
                    Add-UpgradeReg "DiskCleaner" "1"
            
                    ## Recheck
                    Write-Log -Level Error -Message "Upgrade_Task: DiskCleaner temizlik sonrası disk alanı tekrar kontrol ediliyor."
                    if ((GetDiskSizeInfo) -lt 10) { 
                        [string]$FreeDiskSizeInfo = GetDiskSizeInfo
                        Write-Log -Message "Upgrade_Task: DiskCleaner temizlik sonrası mevcut disk alanı: $FreeDiskSizeInfo"
                        Write-Log -Level Error -Message "Upgrade_Task: Yetersiz disk alanı algılandı. Başarısız!"
                        Add-UpgradeReg "UpgradeStatus" "5"
                        HWScanTrigger
                        Start-MultiNotification "DiskNotification"
                        ExitScript 5
                    }
                    else {
                        [string]$FreeDiskSizeInfo = GetDiskSizeInfo
                        Write-Log -Message "Upgrade_Task: DiskCleaner temizlik sonrası mevcut disk alanı: $FreeDiskSizeInfo"
                        Write-Log -Message "Upgrade_Task: Minumum gereken disk alanı mevcut. Başarılı!"
                    }
                }
                else {
                    Add-UpgradeReg "UpgradeStatus" "5"
                    HWScanTrigger
                    Start-MultiNotification "DiskNotification"
                    ExitScript 5
                }
            }
        }
        UpgradeTrigger
        Write-Log -Message "Upgrade_Task: Tetikleme sonrası 5 dakika daha beklemeye alındı."
        Start-Sleep 300
        if ((FeatureUpdateCheck).EvaluationState -eq 13) { Write-Log -Message "Upgrade_Task: Tetikleme sonrası 10 dakika daha beklemeye alındı."; Start-Sleep 600; UpgradeTrigger }
        if ((FeatureUpdateCheck).EvaluationState -eq 13) { Write-Log -Message "Upgrade_Task: Tetikleme sonrası 10 dakika daha beklemeye alındı."; Start-Sleep 600 }
        if ((FeatureUpdateCheck).EvaluationState -eq 13) { ExitScript 13 }
        Start-MultiNotification "UpgradeStatusMonitoring"
        ExitScript 0
    }
}
elseif ($EvaluationState -eq 0) {
    Write-Log -Message "5 dakika beklemeye alındı."
    Start-Sleep 300
}


##*=============================================
##* DEFAULT VARIABLES/REGISTERY KEYS
##*=============================================
[boolean]$Task8Result = $True
[boolean]$Task9Result = $True
[int32]$GetSuccessTask = 0
[int32]$FeatureUpdateCheckCount = 0
[int32]$FileMonitoringCount = 0
[boolean]$FileMonitoring = $False
$Upgrade_Fast_Check = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'Upgrade_Fast' -ErrorAction SilentlyContinue
if (($Upgrade_Fast_Check -ne $null) -and ($Upgrade_Fast_Check -eq 1)) { 
    [boolean]$Upgrade_Fast = $True 
    New-ItemProperty -Path $registeryPath -Name "PreNotification_Snooze" -Value "0" -Force -ErrorAction Continue | Out-Null
}
else { [boolean]$Upgrade_Fast = $False }
New-ItemProperty -Path $registeryPath -Name "UpgradeStatus" -Value "0" -Force -ErrorAction Continue | Out-Null


##*=============================================
##* TASK SEQUENCE BEGINS
##*=============================================


## Task Sequence: 1
## Task Name: Pgp Check

if ($Task1 -eq $True) {
    $PGPPath = "$envProgramFilesX86\PGP Corporation\PGP Desktop\PGPwde.exe"
    if (!(Test-Path $PGPPath)) 
    {
        Write-Log -Message "Adım 1: PGP uygulaması tespit edilmedi. Başarılı!"
        $SetupConfigPath = "$SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\WSUS\Setupconfig.ini"
        if (Test-Path $SetupConfigPath) {
            Remove-Item -Path $SetupConfigPath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Log -Level Error -Message "Adım 1: PGP uygulaması tespit edildi. Başarısız!"
        Add-UpgradeReg "UpgradeStatus" "1"
        ExitScript 1
    }
}
else { Write-Log -Level Warn -Message "Adım 1: Pgp Check Kontrolü Pasif!" }


## Task Sequence: 2
## Task Name: System Type Check

if ($Task2 -eq $True) {
    if ($envOSArchitecture -eq "64-bit") {
        Write-Log -Message "Adım 2: 64-bit işletim sistemi olduğu tespit edildi. Başarılı!"
    }
    else {
        Add-UpgradeReg "UpgradeStatus" "2"
        Write-Log -Level Error -Message "Adım 2: 32-bit işletim sistemi olduğu tespit edildi. Başarısız!"
        ExitScript 2
    }
}
else { Write-Log -Level Warn -Message "Adım 2: System Type Check Kontrolü Pasif!" }


## Task Sequence: 3
## Task Name: En-Us Language Check

if ($Task3 -eq $True) {
    if ($LanguageLCID -eq "1033") 
    {
        Write-Log -Message "Adım 3: Windows dili En-Us olarak tespit edildi. Başarılı!"
    }
    else {
        Write-Log -Level Error -Message "Adım 3: Windows dili $LanguageName olarak tespit edildi. Başarısız!"
        Add-UpgradeReg "UpgradeStatus" "3"
        ExitScript 3
    }
}
else { Write-Log -Level Warn -Message "Adım 3: En-Us Language Check Kontrolü Pasif!" }


## Task Sequence: 4
## Task Name: Group Policy Files Fix

if ($Task4 -eq $True) {
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
            Write-Log -Message "Adım 4: Group Policy onarımı yapıldı. Başarılı!"
            Start-Sleep 300
            if (FeatureUpdateCheck -eq $null) { SoftwareScanTrigger }
            Start-Sleep 120
        }
        else {
            Write-Log -Message "Adım 4: Group Policy sorunu tespit edilmedi. Başarılı!"
        }
    }
    catch {
        Write-Log -Level Error -Message "Adım 4: Group Policy onarımı yapılamadı. Başarısız!"
        Add-UpgradeReg "UpgradeStatus" "4"
        ExitScript 4
    }
}
else { Write-Log -Level Warn -Message "Adım 4: Group Policy Files Fix Kontrolü Pasif!" }


## Task Sequence: 5
## Task Name: Free Space Disk Check, Cleaner and Notification

if ($Task5 -eq $True) {

    $WUBFolderPath = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*WindowsUpdateBox*" -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName -ErrorAction SilentlyContinue
        if ($WUBFolderPath -ne $null) {
            $ESDFileSize = Get-ChildItem -Path $WUBFolderPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".esd" } -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Length -ErrorAction SilentlyContinue
            if (($ESDFileSize -ne $null) -and ($ESDFileSize -eq $UpgradeFileSize)) {
            $NeedDiskSize = 20
        }
    }

    if ((GetDiskSizeInfo) -gt $NeedDiskSize) { 
        Write-Log -Message "Adım 5: Minumum gereken disk alanı mevcut. Başarılı!"
    }
    else {
        # Basic Disk Clean
        $CleanedCheck = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'DiskCleaner' -ErrorAction SilentlyContinue
        if ($CleanedCheck -eq $null) {
        
            ## CCMCache Clean
            $ErrorActionPreference = "SilentlyContinue"
            $UIResourceMgr = New-Object -ComObject UIResource.UIResourceMgr
            $Cache = $UIResourceMgr.GetCacheInfo()
            $UpgradeTask = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*Upgrade_Task.ps1*" | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
            $ExcludeWUB = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*WindowsUpdateBox*" | Where-Object { $_.VersionInfo -like "*Windows 11*" } | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
            $ExcludeBitlockerBoot = Get-ChildItem -Path $CacheFolder -Recurse -Filter "boot*.wim" | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
            $ExcludeBitlockerNotification = Get-ChildItem -Path $CacheFolder -Recurse -Filter "MultiSession-Notification.ps1" | Sort-Object CreationTime -CaseSensitive | Select-Object -First 1 -ExpandProperty DirectoryName
            $CacheElements = $Cache.GetCacheElements() | Where-Object { ($_.Location -notlike "$UpgradeTask") -and ($_.Location -notlike "$ExcludeWUB") -and ($_.Location -notlike "$ExcludeBitlockerBoot") -and ($_.Location -notlike "$ExcludeBitlockerNotification") }
            foreach ($Element in $CacheElements)
            {
                $Cache.DeleteCacheElement($Element.CacheElementID)
            }
            $ErrorActionPreference = "Continue"
            
            Add-UpgradeReg "DiskCleaner" "1"
            
            ## Recheck
            if ((GetDiskSizeInfo) -lt $NeedDiskSize) { 
                Write-Log -Level Error -Message "Adım 5: Yetersiz disk alanı algılandı. Başarısız!"
                Start-MultiNotification "DiskNotification"
                Add-UpgradeReg "UpgradeStatus" "5"
                ExitScript 5
            }
            else {
                Write-Log -Message "Adım 5: Minumum gereken disk alanı mevcut. Başarılı!"
                HWScanTrigger
            }
        }
        else {
            Write-Log -Level Error -Message "Adım 5: Yetersiz disk alanı algılandı. Başarısız!"
            Start-MultiNotification "DiskNotification"
            Add-UpgradeReg "UpgradeStatus" "5"
            ExitScript 5
        }
    }
}
else { Write-Log -Level Warn -Message "Adım 5: Free Space Disk Check, Cleaner and Notification Kontrolü Pasif!" }


## Task Sequence: 6
## Task Name: Hardware Inventory Fix

if ($Task6 -eq $True) {
    # Check InventoryAgent log for ignored message
    $InventoryAgentLog = "$envWinDir\CCM\Logs\InventoryAgent.Log"
    $ErrorActionPreference = "SilentlyContinue"
    $LogEntries = Select-String –Path $InventoryAgentLog –SimpleMatch "{00000000-0000-0000-0000-000000000001}" -ErrorAction SilentlyContinue | Select -Last 1 -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Continue"
    If ($LogEntries -match "already in queue. Message ignored.")
    {
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
            Write-Log -Message "Adım 6: HW Inventory hatası düzeltildi. Başarılı!"
        }
        catch {
            Write-Log -Level Error -Message "Adım 6: HW Inventory hatası düzeltilemedi. Başarısız!"
            Add-UpgradeReg "UpgradeStatus" "6"
            ExitScript 6
        }
    }
    else {
        Write-Log -Message "Adım 6: HW Inventory sorunu tespit edilmedi. Başarılı!"
    }
}
else { Write-Log -Level Warn -Message "Adım 6: Hardware Inventory Fix Kontrolü Pasif!" }


## Task Sequence: 7
## Task Name: Null

if ($Task7 -eq $True) {
    ## Null
}
else { Write-Log -Level Warn -Message "Adım 7: Pasif!" }


## Task Sequence: 8
## Task Name: Feature Update Check

if ($Task8 -eq $True) {
    if (FeatureUpdateCheck -ne $null) {
        Write-Log -Message "Adım 8: Win11 Upgrade güncellemesi Software Center'da tespit edildi. Başarılı!"
    }
    else {
        Write-Log -Level Error -Message "Adım 8: Win11 Upgrade güncellemesi Software Center'da tespit edilemedi. Başarısız!"
        Add-UpgradeReg "UpgradeStatus" "8"
        $Task8Result = $False
    }
}
else { Write-Log -Level Warn -Message "Adım 8: Feature Update Check Kontrolü Pasif!" }


## Task Sequence: 9
## Task Name: Feature Update File Check

if ($Task9 -eq $True) {
    if ($Task8Result -eq $True) {
        $WUBFolderPath = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*WindowsUpdateBox*" -ErrorAction SilentlyContinue | Where-Object { $_.VersionInfo -like "*Windows 11*" } | Sort-Object CreationTime -CaseSensitive -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName -ErrorAction SilentlyContinue
        if ($WUBFolderPath -ne $null) {
            $ESDFileSize = Get-ChildItem -Path $WUBFolderPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".esd" } -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Length -ErrorAction SilentlyContinue
            if (($ESDFileSize -ne $null) -and ($ESDFileSize -eq $UpgradeFileSize)) {
                Write-Log -Message "Adım 9: Win11 Upgrade dosyaları indirilmiş olarak tespit edildi. Başarılı!"
                $Task9Result = $True
                $FileMonitoring = $True
            }
            else {
                Write-Log -Level Error -Message "Adım 9: WindowsUpdateBox.exe dosyası bulundu. İndirme henüz tamamlanmadı. Başarısız!"
                Add-UpgradeReg "UpgradeStatus" "9"
                $Task9Result = $False
            }
        }
        else {
            Write-Log -Level Error -Message "Adım 9: Win11 Upgrade dosyaları bulunamadı. Başarısız!"
            Add-UpgradeReg "UpgradeStatus" "9"
            $Task9Result = $False
        }
    }
    else {
        $Task9Result = $False
        Write-Log -Message "Adım 9: Feature Update kontrolü başarısız olduğu için bu adım pas geçildi."
    }
}
else { Write-Log -Level Warn -Message "Adım 9: Feature Update File Check Kontrolü Pasif!" }


## Task Sequence: 10
## Task Name: Feature Update Monitoring

if ($Task10 -eq $True) {
    if ($Task8Result -eq $False) {
        Write-Log -Message "Adım 10: Feature Update Monitoring işlemi başlatıldı. Beklemeye alındı."
        $FeatureUpdate = FeatureUpdateCheck
        While (($FeatureUpdate -eq $null) -and ($FeatureUpdateCheckCount -lt 192) )
        {
            if (($FeatureUpdateCheckCount -eq 72) -or ($FeatureUpdateCheckCount -eq 144)) {
                SoftwareScanTrigger
            }
            Start-Sleep 300
            $FeatureUpdateCheckCount++
            $FeatureUpdate = FeatureUpdateCheck
        }
    
        if ($FeatureUpdate -ne $null) {
            Write-Log -Message "Adım 10: $FeatureUpdateCheckCount. denemede Win11 Upgrade güncellemesi Software Center'da tespit edildi. Başarılı!"
            Add-UpgradeReg "UpgradeStatus" "0"
        }
        else {
            Write-Log -Level Error -Message "Adım 10: Win11 Upgrade güncellemesi Software Center'da tespit edilemedi. Başarısız!"
            Add-UpgradeReg "UpgradeStatus" "10"
            ExitScript 10
        }
    }
    else { Write-Log -Message "Adım 10: Feature Update tespit edildi. Feature Update Monitoring pas geçildi. Başarılı!" }
}
else { Write-Log -Level Warn -Message "Adım 10: Feature Update Monitoring Kontrolü Pasif!" }



## Task Sequence: 11
## Task Name: Feature Update File Monitoring

if ($Task11 -eq $True) {
    if ($Task9Result -eq $False) {
        $FTUpdateCheck = get-wmiobject -query "SELECT * FROM CCM_SoftwareUpdate" -namespace "ROOT\ccm\ClientSDK" -ErrorAction SilentlyContinue | Where-Object {$_.Name -like "$FeatureUpdateName"} -ErrorAction SilentlyContinue 
        if (($FTUpdateCheck -ne $null) -and (($FTUpdateCheck.Name -like "*consumer editions*") -or ($FTUpdateCheck.Name -like "*tüketici sürümleri*"))) {
            $UpgradeFileSize = "3905707736"
        }
        Function ESDFileSizeCheck {
            $ESDFileSize = Get-ChildItem -Path $CacheFolder -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -eq "$UpgradeFileSize" } -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Length -ErrorAction SilentlyContinue
            if ($ESDFileSize -eq $UpgradeFileSize) {
                return $ESDFileSize
            }
        }

        ## 1- WindowsUpdateBox File Monitoring Test
        if ((ESDFileSizeCheck) -eq $null) {
            Write-Log -Message "Adım 11: Esd dosyası bulunamadı. File Monitoring işlemi başlatıldı."

            [int32]$FileMonitoring_Count = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'FileMonitoring_Count' -ErrorAction SilentlyContinue
            if ($FileMonitoring_Count -eq $null) {
                Add-UpgradeReg "FileMonitoring_Count" "0" 
            }
            else {
                if ($FileMonitoring_Count -gt 0) {
                    Write-Log -Message "Adım 11: Kayıt defterinde daha önce $FileMonitoring_Count deneme sayısı tespit edildi. File Monitoring kaldığı yerden devam ediyor."
                }
                else {
                    Write-Log -Message "Adım 11: Kayıt defterinde daha önce dosya takibi değerleri tespit edilmedi. Oluşturuldu."
                }
            }
            
            Write-Log -Message "Adım 11: WindowsUpdateBox dosyasının indirilmesi beklenmektedir."
            While (((ESDFileSizeCheck) -eq $null) -and ([int32]$FileMonitoring_Count -lt 160) )
            {
                Start-Sleep 300
                $FileMonitoring_Count++
                Add-UpgradeReg "FileMonitoring_Count" "$FileMonitoring_Count"
            }

            [int32]$FileMonitoring_Count = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'FileMonitoring_Count' -ErrorAction SilentlyContinue
            if ((ESDFileSizeCheck) -ne $null) {
                Write-Log -Message "Adım 11: Esd dosyası tespit edildi. Başarılı!"
                Add-UpgradeReg "UpgradeStatus" "0"
            }
            elseif (((ESDFileSizeCheck) -eq $null) -and ($FileMonitoring_Count -ge 160)) {
                Write-Log -Level Warn -Message "Adım 11: File monitoring $FileMonitoring_Count defa denendi. Esd dosyası tespit edilemedi."
                $Hour = (Get-Date).TimeOfDay.Hours
                if ((($Hour -ge 07) -and ($Hour -le 14))) {
                    Write-Log -Message "Adım 11: İndirmenin başlatılamadığı tespit edildi. 07:00 - 14:00 saatleri arasında bulunulduğu için elle tetikleme işlemi yapılıyor. 10 dakika beklemeye alındı."
                    UpgradeTrigger
                    Start-Sleep 600
                    $EvaluationState = (FeatureUpdateCheck).EvaluationState
                    if (($EvaluationState -eq 0) -and ((ESDFileSizeCheck) -eq $null)) {
                        Write-Log -Level Warn -Message "Adım 11: Tetikleme sonrası indirme başlatılmadı. Tekrar tetikleniyor. 5 dakika beklemeye alındı."
                        UpgradeTrigger
                        Start-Sleep 300
                        $EvaluationState = (FeatureUpdateCheck).EvaluationState
                    }
                    if (($EvaluationState -gt 0) -and ((ESDFileSizeCheck) -ne $null)) {
                        Write-Log -Message "Adım 11: Esd dosyası tespit edildi. Başarılı!"
                        Add-UpgradeReg "UpgradeStatus" "0"
                        Add-UpgradeReg "PreNotification_Snooze" "0"
                        Add-UpgradeReg "PreNotification_Silently" "1"
                    }
                    else {
                        Write-Log -Level Error -Message "Adım 11: Tetikleme sonrası Esd dosyası tespit edilemedi. Başarısız!"
                        Add-UpgradeReg "UpgradeStatus" "11"
                        ExitScript 11
                    }
                }
                else {
                    Write-Log -Level Warn -Message "Adım 11: 07:00 - 14:00 saatleri arasında bulunulmadığı için File Monitoring update trigger işlemi yapılmadı. Başarısız!"
                    Add-UpgradeReg "UpgradeStatus" "11"
                    ExitScript 11
                }
            }
            else {
                Write-Log -Level Error -Message "Adım 11: Esd dosyası tespit edilemedi. Başarısız!"
                Add-UpgradeReg "UpgradeStatus" "11"
                ExitScript 11
            }
        }
        else {
            $ESDFileNameCheck = Get-ChildItem -Path $CacheFolder -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.Length -eq "$UpgradeFileSize") -and {$_.Name -eq "B*"} } -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Length -ErrorAction SilentlyContinue
            if ($ESDFileNameCheck -ne $null) {
                Write-Log -Level Warn -Message "Adım 11: ESD Cache dosyasının varlığı tespit edildi."
            }
            else {
                Write-Log -Level Warn -Message "Adım 11: Upgrade dosyalarının varlığı tespit edildi. "
            }
        }
        
        
        ## 2- File Download Test
        $WUBFolderPath = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*WindowsUpdateBox*" -ErrorAction SilentlyContinue | Where-Object { $_.VersionInfo -like "*Windows 11*" } | Sort-Object CreationTime -CaseSensitive -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName -ErrorAction SilentlyContinue
        if ($WUBFolderPath -ne $null) {
            $ESDFileSize = Get-ChildItem -Path $WUBFolderPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".esd" } -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Length -ErrorAction SilentlyContinue
            if (($ESDFileSize -ne $null) -and ($ESDFileSize -eq $UpgradeFileSize)) {
                $FileMonitoring = $True
                Add-UpgradeReg "UpgradeStatus" "0"
            }
            else {
                $FileMonitoring = $False
            }
        }
        else {
            $FileMonitoring = $False
        }

        if ($FileMonitoring -eq $false) {
            Write-Log -Level Warn -Message "Upgrade_Task: Win11 Upgrade dosyaları indiriliyor."
        }

        While (($FileMonitoring -eq $False) -and ($FileMonitoringCount -lt 288))
        {
            ## BITS policy and Leave Computer On Notification
            if (($LeaveComputerOnNotificationCount -eq $null)) {
                if (((RegisteryCheck "HKLM:\SOFTWARE\Policies\Microsoft\Windows\BITS" "EnableBitsMaxBandwidth") -eq 1)) {
                    $Hour = (Get-Date).TimeOfDay.Hours
                    if (($Hour -ge 15) -and ($Hour -le 20)) {
                        Write-Log -Level Warn -Message "Upgrade_Task: Bilgisayar tipi Desktop olarak ve BITS policy'nin varlığı tespit edildi."
                        Write-Log -Level Warn -Message "Upgrade_Task: Saat: 15:00 ve 20:00 aralığında olduğu için kullanıcıya bilgisayarını açık bırak bildirimi gönderiliyor. "
                        Start-MultiNotification "LeaveComputerOnNotification"
                        $LeaveComputerOnNotificationCount = 1
                    }
                }
            }

            Start-Sleep 300
            $FileMonitoringCount++
            $WUBFolderPath = Get-ChildItem -Path $CacheFolder -Recurse -Filter "*WindowsUpdateBox*" -ErrorAction SilentlyContinue | Where-Object { $_.VersionInfo -like "*Windows 11*" } | Sort-Object CreationTime -CaseSensitive -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName -ErrorAction SilentlyContinue
            if ($WUBFolderPath -ne $null) {
                $ESDFileSize = Get-ChildItem -Path $WUBFolderPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".esd" } -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Length -ErrorAction SilentlyContinue
                if (($ESDFileSize -ne $null) -and ($ESDFileSize -eq $UpgradeFileSize)) {
                    $FileMonitoring = $True
                }
                else {
                    $FileMonitoring = $False
                }
            }
            else {
                $FileMonitoring = $False
            }
        }
        if ($FileMonitoring -eq $True) { 
            Write-Log -Message "Adım 11: $FileMonitoringCount. denemede Win11 Upgrade dosyaları indirilmiş olarak tespit edildi. Başarılı!"
            Add-UpgradeReg "UpgradeStatus" "0"
        }
        else {
            Write-Log -Level Error -Message "Adım 11: Win11 Upgrade dosyaları bulunamadı. Başarısız!"
            Add-UpgradeReg "UpgradeStatus" "11"
            ExitScript 11
        }
    }
    else { 
        $FileMonitoring = $True 
        Write-Log -Message "Adım 11: Feature Update dosyaları tespit edildi. File Monitoring pas geçildi. Başarılı!" 
    }
}
else { 
    Write-Log -Level Warn -Message "Adım 11: Feature Update File Monitoring Kontrolü Pasif!" 
}



## Task Sequence: 12
## Task Name: Start Multi Notification

if ($Task12 -eq $True) {
    if ((FeatureUpdateCheck -ne $null) -and ($FileMonitoring -eq $True)) {
        if ((FeatureUpdateCheck).EvaluationState -eq 13) {
            Write-Log -Level Warn -Message "Adım 12: EvulationState 13 olarak algılandı."
            ## Upgrade Trigger Yapılabilir veya UpgradeStatusMonitoring scriptinin başına eklenebilir.
            UpgradeTrigger
            Start-MultiNotification "UpgradeStatusMonitoring"
        }
        else {
            Write-Log -Message "Adım 12: Win11 Pre Notification Bildirimi Başlatıldı. Başarılı!"
            ## Silently Check
            $PreNotification_Snooze = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'PreNotification_Snooze' -ErrorAction SilentlyContinue
            $LoggedOnUser_Count = (LoggedOnUser).Count
            if ((($PreNotification_Snooze -ne $null) -and ($PreNotification_Snooze -le 1)) -and ($LoggedOnUser_Count -eq 0)) {
                UpgradeTrigger
                Add-UpgradeReg "PreNotification_Silently" "1"
                Start-MultiNotification "PreNotification"
            }
            else {
                [int32]$GetSnoozeDateTimeCount = (Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'PreNotification_SnoozeDate' -ErrorAction SilentlyContinue).count
                if (($PreNotification_Snooze -gt 1) -and ($GetSnoozeDateTimeCount -gt 0)) {
                    $GetSnoozeDateTime = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'PreNotification_SnoozeDate' -ErrorAction SilentlyContinue
                    $NewGetSnoozeDateTime = [datetime]::parseexact($GetSnoozeDateTime, 'dd-MM-yyyy HH:mm:ss', $null)
                    $CurrentDateTime = (Get-Date -ErrorAction SilentlyContinue).ToString("dd-MM-yyyy HH:mm:ss")
                    $NewCurrentDateTime = [datetime]::parseexact($CurrentDateTime, 'dd-MM-yyyy HH:mm:ss', $null)
                    $ts = New-TimeSpan -Start $NewGetSnoozeDateTime -End $NewCurrentDateTime -ErrorAction SilentlyContinue
                    if ($ts.TotalHours -lt 10) {
                        Write-Log -Level Error -Message "Upgrade_Task: PreNotification bildirimi günlük maximum gösterim sayısına ulaştı."
                        ExitScript 12
                    }
                    else {
                        Start-MultiNotification "PreNotification"
                    }
                }
                else {
                    Start-MultiNotification "PreNotification"
                }
            }
        }
    }
}
else { Write-Log -Level Warn -Message "Adım 12: Bilgilendirme Notification Adımı Pasif!" }


##*=============================================
##* TASK SEQUENCE FINISH
##*=============================================
Write-Log -Message "*********************** Win11 Upgrade Task Sequence Sonlandırıldı. ***********************"