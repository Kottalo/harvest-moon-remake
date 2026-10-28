param(
    [string]$Disc = (Join-Path $PSScriptRoot '..\Game\Harvest Moon - Back to Nature (USA).bin'),
    [string]$Python = 'C:\Users\kottalo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$godotExe = Join-Path $PSScriptRoot '..\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $Python (Join-Path $PSScriptRoot 'tools\import_disc.py') $Disc
if ($LASTEXITCODE -ne 0) { throw 'Disc conversion failed' }
& $Python (Join-Path $PSScriptRoot 'tools\import_player_actions.py') $Disc
if ($LASTEXITCODE -ne 0) { throw 'Player action conversion failed' }
& $Python (Join-Path $PSScriptRoot 'tools\import_day_cycle.py') $Disc
if ($LASTEXITCODE -ne 0) { throw 'Day cycle conversion failed' }
$openEditor = Get-Process Godot* -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'Harvest Moon BTN - Godot Remake.*Godot Engine' }
if ($openEditor) {
    $mcpPython = Join-Path $env:APPDATA 'uv\tools\godot-ai\Scripts\python.exe'
    & $mcpPython (Join-Path $PSScriptRoot 'tools\scan_editor.py')
} else {
    & $godotExe --headless --path $PSScriptRoot --editor --import --quit
}
if ($LASTEXITCODE -ne 0) { throw 'Godot asset refresh failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/bake_assets.gd
if ($LASTEXITCODE -ne 0) { throw 'Native scene baking failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/verify_runtime.gd
if ($LASTEXITCODE -ne 0) { throw 'Native runtime check failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/verify_actions.gd
if ($LASTEXITCODE -ne 0) { throw 'Source action check failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/verify_day_cycle.gd
if ($LASTEXITCODE -ne 0) { throw 'Day cycle and sleep check failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/verify_world.gd
if ($LASTEXITCODE -ne 0) { throw 'World navigation check failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/verify_collision.gd
if ($LASTEXITCODE -ne 0) { throw 'Original ground collision check failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/verify_stair_transitions.gd
if ($LASTEXITCODE -ne 0) { throw 'Room stair transitions check failed' }
& $Python (Join-Path $PSScriptRoot 'tools\check_structure.py')
if ($LASTEXITCODE -ne 0) { throw 'Directory structure check failed' }
