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
    [string]$LogFolderPath = $Xml.Configuration.Option | Select-Object -ExpandProperty LogFolderPath -ErrorAction SilentlyContinue
}

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

[string]$envWinDir = $env:WINDIR

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