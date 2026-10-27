param(
    [string]$Disc = (Join-Path $PSScriptRoot '..\Game\Harvest Moon - Back to Nature (USA).bin'),
    [string]$Python = 'C:\Users\kottalo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$godotExe = Join-Path $PSScriptRoot '..\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $Python (Join-Path $PSScriptRoot 'tools\import_disc.py') $Disc
if ($LASTEXITCODE -ne 0) { throw 'Disc conversion failed' }
& $godotExe --headless --path $PSScriptRoot --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot PNG import failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/bake_assets.gd
if ($LASTEXITCODE -ne 0) { throw 'Native scene baking failed' }
& $godotExe --headless --path $PSScriptRoot --script tools/verify_runtime.gd
if ($LASTEXITCODE -ne 0) { throw 'Native runtime check failed' }
