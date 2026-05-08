@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Store Recovery Center
color 0B

set "LOG=%USERPROFILE%\Desktop\MicrosoftStoreRecovery.log"
set "PS1=%TEMP%\microsoft_store_repair_%RANDOM%.ps1"
set "MODE=DEFAULT"
set "BAR============================================================================"

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    color 0C
    cls
    echo.
    echo  %BAR%
    echo                       ADMINISTRATOR REQUIRED
    echo  %BAR%
    echo.
    echo   Right-click this file and choose Run as administrator.
    echo.
    echo  %BAR%
    pause
    exit /b 1
)

:MENU
cls
color 0B
echo.
echo  ============================================================================
echo                          STORE RECOVERY CENTER
echo  ============================================================================
echo.
echo   Microsoft Store repair utility for Windows.
echo   Made by Mizae.
echo.
echo  ----------------------------------------------------------------------------
echo   DISCLAIMER
echo  ----------------------------------------------------------------------------
echo   This tool is provided as-is, without any warranty.
echo   It may change Microsoft Store, Windows Update, package, service, cache,
echo   and network settings while attempting to repair Store-related issues.
echo   Use it at your own risk. Review the commands before publishing or running
echo   this script, and make sure important data is backed up.
echo.
echo  ----------------------------------------------------------------------------
echo   RECOVERY MODES
echo  ----------------------------------------------------------------------------
echo   [1] SOFT RECOVERY
echo       Resets Store cache, starts required services, and performs light repair.
echo.
echo   [2] DEFAULT RECOVERY
echo       Soft recovery plus BITS, Delivery Optimization, App Installer, and Store repair.
echo.
echo   [3] HARD RECOVERY
echo       Default recovery plus Windows Update cache reset, DISM, SFC, Winsock, and DNS.
echo.
echo   [4] EXIT
echo.
choice /C 1234 /N /M " Select recovery mode [1/2/3/4]: "

if errorlevel 4 exit /b 0
if errorlevel 3 set "MODE=HARD"
if errorlevel 2 set "MODE=DEFAULT"
if errorlevel 1 set "MODE=SOFT"

cls
echo.
echo  %BAR%
echo                         SELECTED MODE: %MODE%
echo                            Made by Mizae
echo  %BAR%
echo.
echo   Close Microsoft Store and any browser windows before continuing.
echo   The process can take a long time, especially in HARD mode.
echo.
echo   By continuing, you confirm that you understand the disclaimer.
echo.
choice /C YN /N /M " Continue recovery? [Y/N]: "
if errorlevel 2 goto MENU

echo %BAR% > "%LOG%"
echo Mizae Microsoft Store Recovery Center >> "%LOG%"
echo Made by Mizae >> "%LOG%"
echo Mode: %MODE% >> "%LOG%"
echo Started: %date% %time% >> "%LOG%"
echo Log file: %LOG% >> "%LOG%"
echo %BAR% >> "%LOG%"

call :HEAD "0" "INITIALIZING RECOVERY ENGINE"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Checkpoint-Computer -Description 'Mizae Store Recovery' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop } catch { Write-Host ('Restore point skipped: ' + $_.Exception.Message) }" >> "%LOG%" 2>&1

call :HEAD "1" "CLOSING MICROSOFT STORE PROCESSES"
taskkill /f /im WinStore.App.exe >> "%LOG%" 2>&1
taskkill /f /im Microsoft.StorePurchaseApp.exe >> "%LOG%" 2>&1
taskkill /f /im StoreExperienceHost.exe >> "%LOG%" 2>&1
taskkill /f /im ApplicationFrameHost.exe >> "%LOG%" 2>&1
taskkill /f /im RuntimeBroker.exe >> "%LOG%" 2>&1
timeout /t 2 /nobreak >nul

call :HEAD "2" "STARTING CORE SERVICES"
call :SERVICE bits demand
call :SERVICE wuauserv demand
call :SERVICE dosvc demand
call :SERVICE InstallService demand
call :SERVICE AppXSvc demand
call :SERVICE ClipSVC demand
call :SERVICE cryptsvc auto
call :START bits
call :START wuauserv
call :START dosvc
call :START InstallService
call :START AppXSvc
call :START ClipSVC
call :START cryptsvc

call :HEAD "3" "RESETTING MICROSOFT STORE CACHE"
wsreset.exe >> "%LOG%" 2>&1
timeout /t 5 /nobreak >nul

call :HEAD "4" "CLEANING USER STORE CACHE"
set "STOREPKG=%LOCALAPPDATA%\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe"
if exist "%STOREPKG%\LocalCache" rmdir /s /q "%STOREPKG%\LocalCache" >> "%LOG%" 2>&1
if exist "%STOREPKG%\LocalState\Cache" rmdir /s /q "%STOREPKG%\LocalState\Cache" >> "%LOG%" 2>&1
if exist "%STOREPKG%\TempState" rmdir /s /q "%STOREPKG%\TempState" >> "%LOG%" 2>&1

if /I "%MODE%"=="SOFT" goto POWERSHELL_REPAIR

call :HEAD "5" "RESETTING BITS AND DELIVERY OPTIMIZATION"
bitsadmin /reset /allusers >> "%LOG%" 2>&1
net stop bits >> "%LOG%" 2>&1
net stop dosvc >> "%LOG%" 2>&1
del /f /q "%ALLUSERSPROFILE%\Microsoft\Network\Downloader\qmgr*.dat" >> "%LOG%" 2>&1
del /f /q "%ProgramData%\Microsoft\Network\Downloader\qmgr*.dat" >> "%LOG%" 2>&1
if exist "%ProgramData%\Microsoft\Windows\DeliveryOptimization\Cache" rmdir /s /q "%ProgramData%\Microsoft\Windows\DeliveryOptimization\Cache" >> "%LOG%" 2>&1
call :START bits
call :START dosvc

if /I "%MODE%"=="DEFAULT" goto POWERSHELL_REPAIR

call :HEAD "6" "HARD RESETTING WINDOWS STORE BACKEND"
net stop wuauserv >> "%LOG%" 2>&1
net stop bits >> "%LOG%" 2>&1
net stop dosvc >> "%LOG%" 2>&1
net stop cryptsvc >> "%LOG%" 2>&1
net stop msiserver >> "%LOG%" 2>&1

if exist "%windir%\SoftwareDistribution\Download" del /f /s /q "%windir%\SoftwareDistribution\Download\*" >> "%LOG%" 2>&1
if exist "%windir%\SoftwareDistribution\DataStore\Logs" del /f /s /q "%windir%\SoftwareDistribution\DataStore\Logs\*" >> "%LOG%" 2>&1
if exist "%windir%\System32\catroot2" ren "%windir%\System32\catroot2" "catroot2.mizae_old_%RANDOM%" >> "%LOG%" 2>&1

call :START cryptsvc
call :START msiserver
call :START bits
call :START dosvc
call :START wuauserv

call :HEAD "7" "RESETTING NETWORK STACK"
ipconfig /flushdns >> "%LOG%" 2>&1
netsh winsock reset >> "%LOG%" 2>&1
netsh int ip reset >> "%LOG%" 2>&1

:POWERSHELL_REPAIR
call :HEAD "8" "RE-REGISTERING MICROSOFT STORE APPS"

del /f /q "%PS1%" >nul 2>&1
echo Write-Host "Mizae PowerShell Store Repair Starting..." > "%PS1%"
echo $apps = @( >> "%PS1%"
echo "Microsoft.WindowsStore", >> "%PS1%"
echo "Microsoft.StorePurchaseApp", >> "%PS1%"
echo "Microsoft.DesktopAppInstaller", >> "%PS1%"
echo "Microsoft.Services.Store.Engagement" >> "%PS1%"
echo ) >> "%PS1%"
echo foreach ($name in $apps) { >> "%PS1%"
echo     Get-AppxPackage -AllUsers $name ^| ForEach-Object { >> "%PS1%"
echo         $manifest = Join-Path $_.InstallLocation "AppXManifest.xml" >> "%PS1%"
echo         if (Test-Path $manifest) { >> "%PS1%"
echo             Write-Host "Repairing $name" >> "%PS1%"
echo             Add-AppxPackage -DisableDevelopmentMode -Register $manifest >> "%PS1%"
echo         } >> "%PS1%"
echo     } >> "%PS1%"
echo } >> "%PS1%"
echo Write-Host "Mizae PowerShell Store Repair Finished." >> "%PS1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" >> "%LOG%" 2>&1
del /f /q "%PS1%" >nul 2>&1

if /I not "%MODE%"=="HARD" goto VERIFY

call :HEAD "9" "RUNNING DISM HEALTH RESTORE"
call :RUN_PROGRESS "DISM RestoreHealth" "DISM.exe" "/Online|/Cleanup-Image|/RestoreHealth"

call :HEAD "10" "RUNNING SYSTEM FILE CHECKER"
call :RUN_PROGRESS "System File Checker" "sfc.exe" "/scannow"

:VERIFY
call :HEAD "11" "VERIFYING SERVICES"
call :CHECK bits
call :CHECK wuauserv
call :CHECK dosvc
call :CHECK InstallService
call :CHECK AppXSvc
call :CHECK ClipSVC
call :CHECK cryptsvc

call :HEAD "12" "OPENING MICROSOFT STORE"
start "" "ms-windows-store:"
timeout /t 3 /nobreak >nul

echo. >> "%LOG%"
echo Finished: %date% %time% >> "%LOG%"
echo Log file: %LOG% >> "%LOG%"

color 0A
echo.
echo  ============================================================================
echo                                RECOVERY DONE
echo                                Made by Mizae
echo  ============================================================================
echo.
echo   Completed mode : %MODE%
echo   Log file       : %LOG%
echo.
echo   Recommended next steps:
echo   1. Restart your PC.
echo   2. Open Microsoft Store.
echo   3. Go to Library.
echo   4. Select Get updates.
echo   5. Try the failed installation or update again.
echo.
echo   If SOFT mode did not fix the issue, run DEFAULT mode.
echo   If DEFAULT mode did not fix the issue, run HARD mode.
echo.
pause
exit /b 0

:HEAD
echo.
echo  %BAR%
echo    [%~1] %~2
echo  %BAR%
echo. >> "%LOG%"
echo [%~1] %~2 >> "%LOG%"
echo %BAR% >> "%LOG%"
exit /b 0

:SERVICE
sc config %~1 start= %~2 >> "%LOG%" 2>&1
exit /b 0

:START
net start %~1 >> "%LOG%" 2>&1
exit /b 0

:RUN_PROGRESS
del /f /q "%PS1%" >nul 2>&1
echo param([string]$Label,[string]$File,[string]$ArgumentText,[string]$Log) > "%PS1%"
echo $arguments = $ArgumentText -split '\^|' >> "%PS1%"
echo $width = 40 >> "%PS1%"
echo function Show-Bar { >> "%PS1%"
echo     param([string]$Text,[int]$Percent) >> "%PS1%"
echo     if ($Percent -lt 0) { $Percent = 0 } >> "%PS1%"
echo     if ($Percent -gt 100) { $Percent = 100 } >> "%PS1%"
echo     $done = [Math]::Floor($Percent * $width / 100) >> "%PS1%"
echo     $left = $width - $done >> "%PS1%"
echo     $bar = ('#' * $done) + ('-' * $left) >> "%PS1%"
echo     [Console]::Write(("`r   {0} [{1}] {2,3}%%" -f $Text, $bar, $Percent)) >> "%PS1%"
echo } >> "%PS1%"
echo Add-Content -LiteralPath $Log -Value "" >> "%PS1%"
echo Add-Content -LiteralPath $Log -Value ("Running: {0} {1}" -f $File, ($arguments -join ' ')) >> "%PS1%"
echo $startInfo = New-Object System.Diagnostics.ProcessStartInfo >> "%PS1%"
echo $startInfo.FileName = $File >> "%PS1%"
echo $quotedArguments = foreach ($argument in $arguments) { >> "%PS1%"
echo     if ($argument -match '\s') { >> "%PS1%"
echo         ([char]34) + $argument + ([char]34) >> "%PS1%"
echo     } else { >> "%PS1%"
echo         $argument >> "%PS1%"
echo     } >> "%PS1%"
echo } >> "%PS1%"
echo $startInfo.Arguments = $quotedArguments -join ' ' >> "%PS1%"
echo $startInfo.RedirectStandardOutput = $true >> "%PS1%"
echo $startInfo.RedirectStandardError = $true >> "%PS1%"
echo $startInfo.UseShellExecute = $false >> "%PS1%"
echo $startInfo.CreateNoWindow = $true >> "%PS1%"
echo $process = [System.Diagnostics.Process]::Start($startInfo) >> "%PS1%"
echo $buffer = New-Object System.Text.StringBuilder >> "%PS1%"
echo $lastPercent = 0 >> "%PS1%"
echo Show-Bar $Label 0 >> "%PS1%"
echo while (-not $process.HasExited -or $process.StandardOutput.Peek() -ge 0 -or $process.StandardError.Peek() -ge 0) { >> "%PS1%"
echo     while ($process.StandardOutput.Peek() -ge 0) { >> "%PS1%"
echo         $char = [char]$process.StandardOutput.Read() >> "%PS1%"
echo         if ($char -eq "`r" -or $char -eq "`n") { >> "%PS1%"
echo             $line = $buffer.ToString() >> "%PS1%"
echo             if ($line.Trim().Length -gt 0) { >> "%PS1%"
echo                 Add-Content -LiteralPath $Log -Value $line >> "%PS1%"
echo                 if ($line -match '(\d+(?:\.\d+)?)\s*%%') { >> "%PS1%"
echo                     $lastPercent = [int][Math]::Round([double]$matches[1]) >> "%PS1%"
echo                     Show-Bar $Label $lastPercent >> "%PS1%"
echo                 } >> "%PS1%"
echo             } >> "%PS1%"
echo             [void]$buffer.Clear() >> "%PS1%"
echo         } else { >> "%PS1%"
echo             [void]$buffer.Append($char) >> "%PS1%"
echo             $current = $buffer.ToString() >> "%PS1%"
echo             if ($current -match '(\d+(?:\.\d+)?)\s*%%') { >> "%PS1%"
echo                 $lastPercent = [int][Math]::Round([double]$matches[1]) >> "%PS1%"
echo                 Show-Bar $Label $lastPercent >> "%PS1%"
echo             } >> "%PS1%"
echo         } >> "%PS1%"
echo     } >> "%PS1%"
echo     while ($process.StandardError.Peek() -ge 0) { >> "%PS1%"
echo         $errorLine = $process.StandardError.ReadLine() >> "%PS1%"
echo         if ($null -ne $errorLine -and $errorLine.Trim().Length -gt 0) { Add-Content -LiteralPath $Log -Value $errorLine } >> "%PS1%"
echo     } >> "%PS1%"
echo     Start-Sleep -Milliseconds 120 >> "%PS1%"
echo } >> "%PS1%"
echo $process.WaitForExit() >> "%PS1%"
echo $remaining = $buffer.ToString() >> "%PS1%"
echo if ($remaining.Trim().Length -gt 0) { Add-Content -LiteralPath $Log -Value $remaining } >> "%PS1%"
echo if ($process.ExitCode -eq 0) { Show-Bar $Label 100 } else { Show-Bar $Label $lastPercent } >> "%PS1%"
echo [Console]::WriteLine("") >> "%PS1%"
echo Add-Content -LiteralPath $Log -Value ("Exit code: {0}" -f $process.ExitCode) >> "%PS1%"
echo exit $process.ExitCode >> "%PS1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" "%~1" "%~2" "%~3" "%LOG%"
set "PROGRESS_ERROR=%errorlevel%"
del /f /q "%PS1%" >nul 2>&1
exit /b %PROGRESS_ERROR%

:CHECK
for /f "tokens=3 delims=: " %%A in ('sc query %~1 ^| findstr /I "STATE"') do (
    echo   %~1 = %%A
    echo %~1 = %%A >> "%LOG%"
)
exit /b 0
