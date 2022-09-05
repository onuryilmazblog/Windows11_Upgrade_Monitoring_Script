''''Way 1
currentdir=Left(WScript.ScriptFullName,InStrRev(WScript.ScriptFullName,"\"))

''''Way 2
With CreateObject("WScript.Shell")
CurrentPath=.CurrentDirectory
End With

''''Way 3
With WSH
CurrentDirr=Replace(.ScriptFullName,.ScriptName,"")
End With

Set WshShell = CreateObject("WScript.Shell") 
WshShell.Run "%Windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command & { & '"& currentdir &""& WScript.Arguments(0) &"' -DeploymentType 'Install' -DeployMode 'Interactive'; Exit $LastExitCode }" , 0
Set WshShell = Nothing