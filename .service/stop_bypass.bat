@echo off
title ybzapret-upx - Stop Bypass

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Please run as Administrator!
    pause
    exit /b
)

taskkill /F /IM winws.exe >nul 2>&1
sc stop ybzapret >nul 2>&1
sc delete ybzapret >nul 2>&1
sc stop WinDivert >nul 2>&1
sc delete WinDivert >nul 2>&1
sc stop WinDivert14 >nul 2>&1
sc delete WinDivert14 >nul 2>&1

echo [OK] Stopped and cleaned up!
timeout /t 2 >nul
