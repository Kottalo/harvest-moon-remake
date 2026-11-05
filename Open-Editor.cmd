@echo off
cd /d "%~dp0"
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
set "GODOT_AI_DISABLE_TELEMETRY=true"
if not defined GODOT_AI_VENV_PYTHON (
    for /f "tokens=2 delims==" %%V in ('findstr /b /c:"version=" "%~dp0addons\godot_ai\plugin.cfg"') do (
        if exist "%LOCALAPPDATA%\godot-ai\HarvestMoonBTN\python-3.12\%%~V\Scripts\python.exe" (
            set "GODOT_AI_VENV_PYTHON=%LOCALAPPDATA%\godot-ai\HarvestMoonBTN\python-3.12\%%~V\Scripts\python.exe"
        )
    )
)
start "" "%~dp0..\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --editor --path "%~dp0."
