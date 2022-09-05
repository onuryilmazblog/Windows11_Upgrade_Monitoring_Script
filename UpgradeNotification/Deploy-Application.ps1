<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = ''
	[string]$appName = 'Upgrade Restart Notification'
	[string]$appVersion = ''
	[string]$appArch = ''
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.0.0'
	[string]$appScriptDate = '11/12/2021'
	[string]$appScriptAuthor = 'onuryilmaz'
    [string]$ErrorPrompt = $False
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = 'Microsoft Windows 11 Güncellemesi'

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.0'
	[string]$deployAppScriptDate = '23/09/2019'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

        ##### CUSTOM REGION BEGIN #####

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
        ##* LOG BUILDER
        ##*=============================================
function Write-Logger() {
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

        ## Registery Check
        ## Example: RegisteryCheck "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData" "NotfiyUI"
        Function RegisteryCheck ($RegPath,$RegisteryValue) {
            Get-ItemProperty -Path "$RegPath" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "$RegisteryValue" -ErrorAction SilentlyContinue
        }

        Write-Logger -Message "RestartNotification: script başlatıldı."
        $ACProcessCheck = Get-ItemProperty -Path $registeryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'ACProcessCheck' -ErrorAction SilentlyContinue
        if ($ACProcessCheck -ne $null) { Remove-ItemProperty -Path $registeryPath -Name "ACProcessCheck" -Force -ErrorAction Continue | Out-Null }
        New-ItemProperty -Path $registeryPath -Name "Restart_Notification" -Value "1" -Force -ErrorAction Continue | Out-Null


        $NotfiyUIReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'NotifyUI' -ErrorAction SilentlyContinue
        $RebootByReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'RebootBy' -ErrorAction SilentlyContinue
        if (($NotfiyUIReg -ne $null) -and ($NotfiyUIReg -eq 1) -and ($RebootByReg -ne 0)) {
            Write-Logger -Level Warn -Message "RestartNotification: NotifyUI 1 değeri algılandı. Zamanlayıcı olamadan bildirim görüntüleniyor."        
            $UpgradeFolderPath = Split-Path -Path $scriptPath -Parent
            [string[]]$ReferencedAssemblies = 'System.Drawing', 'System.Windows.Forms', 'System.DirectoryServices'
            Add-Type -Path "$UpgradeFolderPath\UpgradeNotificationTimerPersist\AppDeployToolkit\AppDeployToolkitMain.cs" -ReferencedAssemblies $ReferencedAssemblies
            $NoTimerRestartPath = "$UpgradeFolderPath\UpgradeNotificationTimerPersist"
            $User=[PSADT.QueryUser]::GetUserSessionInfo("$env:ComputerName")
            $UserSessionID = ("$($User.SessionId)").Split("{ }")
            foreach ($SessionID in $UserSessionID) {
                $wshell = new-object -com wscript.shell
                $CommandLine = "$UpgradeFolderPath\ServiceUI.exe -session:$SessionID $env:windir\system32\wscript.exe " + '"'+"$NoTimerRestartPath\Deploy-Application.vbs"+'"' + " " + '"Deploy-Application.ps1"'
                $wshell.run("cmd /c $CommandLine",0, $False)
            }
            Write-Logger -Level Warn -Message "RestartNotification: Script Sonlandırıldı."
            [System.Environment]::Exit(0)
        }
        else {
            [string]$ComputerName = $env:COMPUTERNAME
            if (((($ComputerName -like "D*") -or ($ComputerName -like "T*")) -and ((RegisteryCheck "HKLM:\SOFTWARE\Policies\Microsoft\Windows\BITS" "EnableBitsMaxBandwidth") -eq 1)) -or ($ComputerName -like "D*-1048")) {
                $Hour = (Get-Date).TimeOfDay.Hours
                if (($Hour -ge 00) -and ($Hour -le 06)) {
                    # Restart Promt
                    Write-Logger -Level Warn -Message "RestartNotification: Bilgisayar tipi Desktop olarak ve BITS policy'nin varlığı tespit edildi."
                    Write-Logger -Level Warn -Message "RestartNotification: Gece 12:00 ile 07:00 aralığında olduğu görüldü. Yarım saatlik yeniden başlatma bildirimi başlatılıyor."
                    Show-InstallationRestartPrompt -Countdownseconds 3600 -CountdownNoHideSeconds 1800
                }
                else {
                    # Restart Promt
                    Write-Logger -Message "RestartNotification: 8 saatlik yeniden başlatma bildirimi başlatılıyor."
                    Show-InstallationRestartPrompt -Countdownseconds 28800 -CountdownNoHideSeconds 3600
                }
            }
            else {
                # Restart Promt
                Write-Logger -Message "RestartNotification: 8 saatlik yeniden başlatma bildirimi başlatılıyor."
                Show-InstallationRestartPrompt -Countdownseconds 28800 -CountdownNoHideSeconds 3600
            }
        }

        ##### CUSTOM REGION END #####
        
		## Show Progress Message (with the default message)
		

		## <Perform Pre-Installation tasks here>


		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>
        
        
		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		## Display a message at the end of the install
		If (-not $useDefaultMsi) { 

        }
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		
		## Show Progress Message (with the default message)
		
		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>
        
		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>
        
	}

	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	if ($ErrorPrompt -eq $True) { Show-DialogBox -Text $mainErrorMessage -Icon 'Stop' }
	Exit-Script -ExitCode $mainExitCode
}
