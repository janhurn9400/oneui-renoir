@echo off
rem One UI 8.0 for renoir: flash everything from the bootloader (Windows). ERASES ALL DATA.
rem Phone: stock MIUI V14.0.7.0.TKIMIXM firmware, unlocked bootloader, power off, hold Power + Volume down, USB.
setlocal
cd /d "%~dp0"
set "FB=fastboot"
if exist "%~dp0platform-tools\fastboot.exe" set "FB=%~dp0platform-tools\fastboot.exe"
"%FB%" --version >nul 2>&1 || (echo fastboot not found: install Android platform-tools or put them into .\platform-tools & goto fail)
for %%f in (super vendor_boot vbmeta vbmeta_system) do if not exist "images\%%f.img" (echo missing images\%%f.img & goto fail)
echo Waiting for the phone in fastboot mode ...
:waitdev
"%FB%" devices | findstr /c:"fastboot" >nul || (timeout /t 2 /nobreak >nul & goto waitdev)
"%FB%" getvar product 2>&1 | findstr /r /c:"^product: *renoir" >nul || (echo This is not a Mi 11 Lite 5G / renoir. & goto fail)
"%FB%" getvar is-userspace 2>&1 | findstr /c:"is-userspace: no" >nul || (echo Phone is in fastbootd: run "fastboot reboot bootloader" first. & goto fail)
echo.
set "OK="
set /p "OK=This flashes One UI 8.0 and ERASES ALL DATA on the phone. Type YES to continue: "
if not "%OK%"=="YES" (echo cancelled & goto fail)
"%FB%" --disable-verity --disable-verification flash vbmeta_ab images\vbmeta.img || goto fail
"%FB%" --disable-verity --disable-verification flash vbmeta_system_ab images\vbmeta_system.img || goto fail
"%FB%" flash vendor_boot_ab images\vendor_boot.img || goto fail
"%FB%" flash super images\super.img || goto fail
rem userdata and metadata belong together (metadata holds the /data encryption keys)
"%FB%" erase userdata || goto fail
"%FB%" erase metadata || goto fail
rem Xiaomi's bootloader may still be writing super in the background: wait until it answers again
for /l %%i in (1,1,90) do (
  "%FB%" getvar product 2>&1 | findstr /r /c:"^product: *renoir" >nul && goto ready
  timeout /t 5 /nobreak >nul
)
:ready
set "SLOT="
for /f "tokens=2 delims=: " %%s in ('call "%FB%" getvar current-slot 2^>^&1 ^| findstr current-slot') do set "SLOT=%%s"
if /i not "%SLOT%"=="a" (
  "%FB%" reboot bootloader
  timeout /t 10 /nobreak >nul
  "%FB%" set_active a
)
"%FB%" reboot
echo Done. The first boot takes 5-10 minutes. If a fastboot command ever hangs: wait, then replug the cable.
pause
exit /b 0
:fail
echo Flashing stopped.
pause
exit /b 1
