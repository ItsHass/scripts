@echo off
set AGE=0
set EXCLUDE="Public" "Default" "defaultuser0" "%username%" "default" "public" "Administrator"
for /d %%D in (C:\users\*) do (
    echo %EXCLUDE% | find /i """%%~nD""" >nul
    if errorlevel 1 (
        set too_new=0
        robocopy "%%D" "%%D" /L /v /s /xjd /minage:%AGE% | findstr /r /c:"^. *too new" >nul
        if errorlevel 1 (
            echo Deleting %%D
            rd /s /q "%%D"
        )
    )
)
pause