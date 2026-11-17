@echo off
setlocal

rem Package the existing SYNC_WeatherFX Release AUF2 and update its catalog hash.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0make_release_zip.ps1" %*
set "packageExitCode=%errorlevel%"
exit /b %packageExitCode%
