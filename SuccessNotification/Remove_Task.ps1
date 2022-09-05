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
    [string]$registeryPath = $Xml.Configuration.Option | Select-Object -ExpandProperty registeryPath -ErrorAction SilentlyContinue
    [string]$LogFolderPath = $Xml.Configuration.Option | Select-Object -ExpandProperty LogFolderPath -ErrorAction SilentlyContinue
}


##*=============================================
##* VARIABLE DECLARATION
##*=============================================
[string]$SystemDrive = $env:SystemDrive
[string]$envWinDir = $env:WINDIR
[string]$UpgradeTaskName = "Win11_Upgrade"
[string]$RemoveTaskName = "Win11_Upgrade_Success"
$UpgradeFolderPath = $scriptPath
$UpgradeMainFolderPath = Split-Path -Path $scriptPath -Parent
$SuccessFolderPath = "$UpgradeFolderPath\SuccessNotification"
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


## Process Check
## Example: RunProcess "powershell.exe" "Pre_Monitoring.ps1"
Function RunProcess ($ProcessName,$ProcessCommand) {
    (Get-WmiObject Win32_Process -Filter "name = ""$ProcessName""" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$ProcessCommand*"} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CommandLine -ErrorAction SilentlyContinue).count
}


## Get Task Function
## Example: GetTask "Win11_Upgrade"
Function GetTask ($GetTaskName) {
    (Get-ScheduledTask -TaskPath "\" -TaskName "$GetTaskName" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TaskName -ErrorAction SilentlyContinue).Count
}


## Start Upgrade Deployment
Write-Log -Message "*********************** Win11 Remove Task Scripti Başlatıldı. ***********************"

Write-Log -Message "Remove_Task: 1 dakika beklemeye alındı."
Start-Sleep 60 

## Win11_Upgrade Remove Task
if ((GetTask $UpgradeTaskName) -gt 0) {
    Write-Log -Message "Remove_Task: $UpgradeTaskName taskı bulundu. Siliniyor."     
    Unregister-ScheduledTask -TaskPath "\" -TaskName "$UpgradeTaskName" -Confirm:$false -ErrorAction SilentlyContinue
    if ((GetTask $UpgradeTaskName) -eq 0) {
        Write-Log -Message "Remove_Task: $UpgradeTaskName taskı bulundu. Başarıyla silindi."
    }
    else {
        Write-Log -Level Error -Message "Remove_Task: $UpgradeTaskName taskı silinemedi."
    }
}
else {
    Write-Log -Message "Remove_Task: $UpgradeTaskName taskı bulunmadı."
}

## Proccess Check
$Upgrade_Task_Process = RunProcess "powershell.exe" "Upgrade_Task.ps1"
$DeployApplication_Process = RunProcess "powershell.exe" "Deploy-Application.ps1"
$AppDeployToolkitMain_Process = RunProcess "powershell.exe" "AppDeployToolkitMain.ps1"
if (($Upgrade_Task_Process -gt 0) -or ($DeployApplication_Process -gt 0) -or ($AppDeployToolkitMain_Process -gt 0)) {
    $RunningAppID = Get-WmiObject Win32_Process -Filter "name = ""powershell.exe""" -ErrorAction SilentlyContinue | Where-Object { ($_.CommandLine -like "*Upgrade_Task.ps1*") -or ($_.CommandLine -like "*Deploy-Application.ps1*") -or ($_.CommandLine -like "*AppDeployToolkitMain.ps1*")} -ErrorAction SilentlyContinue | Select -ExpandProperty ProcessId -ErrorAction SilentlyContinue
    If ($RunningAppID -ne $null) {
        Stop-Process -Id $RunningAppID -Force -ErrorAction SilentlyContinue
        Write-Log -Message "Remove_Task: Çalışan işlemler sonlandırıldı."
    }
    else {
        Write-Log -Message "Remove_Task: Çalışan bir işlem bulunamadı."
    }
}


## Remove Upgrade Folder
if (Test-Path $UpgradeFolderPath) {
    Write-Log -Message "Remove_Task: $UpgradeFolderPath klasörü siliniyor."
    Remove-Item -Path "$UpgradeFolderPath" -Recurse -Force -ErrorAction SilentlyContinue
}
Start-Sleep 30
if (Test-Path $UpgradeFolderPath) {
    Write-Log -Level Error -Message "Remove_Task: $UpgradeFolderPath klasörü silinemedi. 1 dakika sonra tekrar deneniyor."
    Start-Sleep 60
    Remove-Item -Path "$UpgradeFolderPath" -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    Write-Log -Message "Remove_Task: $UpgradeFolderPath klasörü başarıyla silindi."
}
if (Test-Path $UpgradeFolderPath) {
    Write-Log -Level Error -Message "Remove_Task: $UpgradeFolderPath klasörü silinemedi."
}


## Win11_Upgrade_Success Remove Task
if ((GetTask $RemoveTaskName) -gt 0) {
    Write-Log -Message "Remove_Task: $RemoveTaskName taskı bulundu. Siliniyor."
    Unregister-ScheduledTask -TaskPath "\" -TaskName "$RemoveTaskName" -Confirm:$false -ErrorAction SilentlyContinue
    if ((GetTask $RemoveTaskName) -eq 0) {
    Write-Log -Message "Remove_Task: $RemoveTaskName taskı bulundu. Başarıyla silindi."
    }
    else {
        Write-Log -Level Error -Message "Remove_Task: $RemoveTaskName taskı silinemedi."
    }
}
else {
    Write-Log -Message "Remove_Task: $RemoveTaskName taskı bulunmadı."
}

## End
Write-Log -Message "*********************** Win11 Remove Task Sonlandırıldı. ***********************"

##*=============================================
##* REMOVE TASK FINISH
##*=============================================