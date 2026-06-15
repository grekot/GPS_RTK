@echo off
REM Buduje i uruchamia natywny symulator firmware. Dwuklik w Eksploratorze Windows.
cd /d "%~dp0"

REM Znajdz katalog z g++ i dodaj go na POCZATEK PATH - inaczej cc1plus/as moga nie
REM znalezc swoich bibliotek DLL (kompilacja padlaby po cichu).
set "GXXDIR="
for /f "delims=" %%i in ('where g++ 2^>nul') do if not defined GXXDIR set "GXXDIR=%%~dpi"
if not defined GXXDIR if exist "C:\msys64\mingw64\bin\g++.exe" set "GXXDIR=C:\msys64\mingw64\bin\"
if not defined GXXDIR (
  echo [BLAD] Nie znaleziono g++. Zainstaluj MSYS2 i pakiet mingw-w64-x86_64-gcc,
  echo        albo dodaj katalog z g++.exe do PATH.
  pause
  exit /b 1
)
set "PATH=%GXXDIR%;%PATH%"

echo Kompiluje symulator (%GXXDIR%g++.exe)...
g++ -std=c++17 -Wall -O2 -static -I. -I..\include device_sim.cpp ..\src\gnss_status.cpp ..\src\status_led.cpp ..\src\telemetry.cpp ..\src\display.cpp -o device_sim.exe
if errorlevel 1 (
  echo [BLAD] Kompilacja nieudana.
  pause
  exit /b 1
)

echo.
"%~dp0device_sim.exe"
echo.
pause
