@echo off
chcp 65001 >nul
setlocal
if "%~1"=="" (
  echo.
  echo 用法：把要检查的 .ipa 文件拖到这个 bat 上，或者：
  echo    检查IPA.bat "C:\某目录\某.ipa"
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0检查IPA.ps1" -Ipa "%~1"
echo.
pause
