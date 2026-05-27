@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_all_demos.ps1"

endlocal
