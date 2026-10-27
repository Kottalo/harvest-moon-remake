@echo off
cd /d "%~dp0"
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
set "GODOT_AI_DISABLE_TELEMETRY=true"
start "" "%~dp0..\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --editor --path "%~dp0."
