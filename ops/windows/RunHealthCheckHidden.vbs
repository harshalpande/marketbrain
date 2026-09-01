Option Explicit

Dim fileSystem, shell, scriptDirectory, powerShellScript, command

Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powerShellScript = fileSystem.BuildPath(scriptDirectory, "RunHealthCheck.ps1")
command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & powerShellScript & """"

' Window style 0 is hidden. True waits for the health check to complete so the
' scheduler does not start overlapping instances.
shell.Run command, 0, True
