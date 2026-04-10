@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: Set UTF-8
chcp 65001 >nul

:: Ambil ESC (warna)
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

:: Test Unicode support (karakter block █)
echo █ > tmp_test.txt
findstr /c:"█" tmp_test.txt >nul
if errorlevel 1 (
    set "USE_UNICODE=0"
) else (
    set "USE_UNICODE=1"
)
del tmp_test.txt >nul 2>&1

:: ===============================
:: HEADER
:: ===============================

if "%USE_UNICODE%"=="1" goto unicode
goto ascii

:unicode
echo %ESC%[36m======================================================%ESC%[0m
echo %ESC%[33mby KORASU%ESC%[0m
echo.
echo %ESC%[32m        ██╗  ██╗ ██████╗ ██████╗  █████╗ ███████╗██╗   ██╗%ESC%[0m
echo %ESC%[32m        ██║ ██╔╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║   ██║%ESC%[0m
echo %ESC%[32m        █████╔╝ ██║   ██║██████╔╝███████║███████╗██║   ██║%ESC%[0m
echo %ESC%[32m        ██╔═██╗ ██║   ██║██╔══██╗██╔══██║╚════██║██║   ██║%ESC%[0m
echo %ESC%[32m        ██║  ██╗╚██████╔╝██║  ██║██║  ██║███████║╚██████╔╝%ESC%[0m
echo %ESC%[32m        ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝%ESC%[0m
echo.
echo %ESC%[36m======================================================%ESC%[0m
goto headerEnd

:ascii
echo ======================================================
echo by KORASU
echo.
echo        K O R A S U
echo        NETWORK QUICK FIX TOOL
echo.
echo ======================================================

:headerEnd

echo.
echo This script sets static IPv4 and DNS on a selected interface.
echo Run as Administrator in CMD.
echo.

echo [1/7] Available interfaces:
powershell -NoProfile -Command "Get-NetAdapter -IncludeHidden | Select-Object InterfaceIndex,Name,Status,MacAddress,InterfaceDescription | Format-Table -AutoSize"
echo.

set "IF_INPUT=AUTO"
set /p IF_INPUT=Interface index or name (default: AUTO VirtIO adapter): 
if "%IF_INPUT%"=="" set "IF_INPUT=AUTO"

set "IF_INDEX="
set "IF_NAME="
for /f "usebackq tokens=1,* delims=|" %%A in (`powershell -NoProfile -Command "$in='%IF_INPUT%'; if ([string]::IsNullOrWhiteSpace($in) -or $in -eq 'AUTO') { $nic = Get-NetAdapter -IncludeHidden ^| Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -like 'Red Hat VirtIO*' } ^| Select-Object -First 1 } elseif ($in -match '^[0-9]+$') { $nic = Get-NetAdapter -InterfaceIndex ([int]$in) -ErrorAction SilentlyContinue } else { $nic = Get-NetAdapter -Name $in -ErrorAction SilentlyContinue }; if ($nic) { Write-Output ($nic.InterfaceIndex.ToString() + '|' + $nic.Name) }"`) do (
  set "IF_INDEX=%%A"
  set "IF_NAME=%%B"
)

if "%IF_INDEX%"=="" (
  echo Error: interface "%IF_INPUT%" not found.
  echo Tip: use the exact InterfaceIndex shown above, or press Enter for AUTO.
  exit /b 1
)

echo Selected interface: index=%IF_INDEX%, name="%IF_NAME%"

set /p IPV4=IPv4 Address (example 192.168.1.10): 
if "%IPV4%"=="" (
  echo Error: IPv4 Address is required.
  exit /b 1
)

set /p MASK=Subnet Mask (example 255.255.255.0): 
if "%MASK%"=="" (
  echo Error: Subnet Mask is required.
  exit /b 1
)

set /p GW=Default Gateway (example 192.168.1.1): 
if "%GW%"=="" (
  echo Error: Default Gateway is required.
  exit /b 1
)

set "DNS1=1.1.1.1"
set "DNS2=8.8.8.8"
echo DNS will be set automatically to %DNS1% and %DNS2%.

echo.
echo [2/7] Applying static IPv4...
powershell -NoProfile -Command "$ifx=[int]'%IF_INDEX%'; $mask='%MASK%'; $prefix=(([ipaddress]$mask).GetAddressBytes() | ForEach-Object { [Convert]::ToString($_,2).PadLeft(8,'0') } | ForEach-Object { ($_.ToCharArray() | Where-Object { $_ -eq '1' }).Count } | Measure-Object -Sum).Sum; Get-NetIPAddress -InterfaceIndex $ifx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue; Get-NetRoute -InterfaceIndex $ifx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue; New-NetIPAddress -InterfaceIndex $ifx -IPAddress '%IPV4%' -PrefixLength $prefix -DefaultGateway '%GW%' -AddressFamily IPv4 -ErrorAction Stop | Out-Null"
if errorlevel 1 (
  echo Error: failed to set IPv4 on interface index=%IF_INDEX%.
  exit /b 1
)

echo [3/7] Applying DNS servers...
powershell -NoProfile -Command "Set-DnsClientServerAddress -InterfaceIndex ([int]'%IF_INDEX%') -ServerAddresses @('%DNS1%','%DNS2%') -ErrorAction Stop"
if errorlevel 1 (
  echo Error: failed to set primary DNS.
  exit /b 1
)

echo [3b/7] Current IPv4 config:
netsh interface ipv4 show config name="%IF_NAME%"

echo [4/7] Checking NetKVM driver...
pnputil /enum-drivers | findstr /i netkvm

echo [5/7] Showing full IP config...
ipconfig /all

echo [6/7] Connectivity test to 1.1.1.1...
ping 1.1.1.1

echo [7/7] Connectivity test to google.com...
ping google.com

echo.
echo Done. If ping works, RDP usually works on port 3389.
pause
endlocal
