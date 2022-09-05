Set WshShell = CreateObject("WScript.Shell") 
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Install\Windows11Upgrade\Win11\Upgrade_Task.ps1" , 0 , False
Set WshShell = Nothing