@echo off
title ybzapret-upx - Install Service

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Please run as Administrator!
    pause
    exit /b
)

set "BASE_DIR=%~dp0.."
set "BIN=%BASE_DIR%\bin\winws.exe"
set "LIST=%BASE_DIR%\lists\blacklist.txt"
set "IPSET=%BASE_DIR%\lists\ipset-all.txt"
set "FAKE_TLS=%BASE_DIR%\bin\tls_clienthello_www_google_com.bin"
set "FAKE_QUIC=%BASE_DIR%\bin\quic_initial_www_google_com.bin"
set "SERVICE_NAME=ybzapret"

if not exist "%BIN%" (
    echo [ERROR] winws.exe not found in bin\ folder!
    pause
    exit /b
)

sc query "%SERVICE_NAME%" >nul 2>&1
if %errorlevel% equ 0 (
    sc stop "%SERVICE_NAME%" >nul 2>&1
    sc delete "%SERVICE_NAME%" >nul 2>&1
    timeout /t 2 >nul
)

sc create "%SERVICE_NAME%" binPath= "\"%BIN%\" --wf-tcp=80,443 --wf-udp=443,50000-50100 --filter-udp=443 --hostlist=\"%LIST%\" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic=\"%FAKE_QUIC%\" --new --filter-udp=50000-50100 --ipset=\"%IPSET%\" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new --filter-tcp=443 --hostlist=\"%LIST%\" --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=2 --dpi-desync-fooling=badseq --dpi-desync-fake-tls=\"%FAKE_TLS%\"" start= auto DisplayName= "ybzapret-upx DPI Bypass" >nul

if %errorlevel% equ 0 (
    sc start "%SERVICE_NAME%" >nul
    echo [OK] Service installed and running in background!
) else (
    echo [ERROR] Failed to create service.
)
pause
