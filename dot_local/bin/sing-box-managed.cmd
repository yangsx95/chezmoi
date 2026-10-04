@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.local\libexec\sing-box-windows-managed.ps1" %*
exit /b %errorlevel%
