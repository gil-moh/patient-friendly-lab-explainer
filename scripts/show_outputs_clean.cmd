@echo off
setlocal

powershell -ExecutionPolicy Bypass -File "%~dp0show_outputs_clean.ps1"

endlocal
