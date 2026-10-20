param(
    [string]$Target = "x86_64-windows-gnu"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Version = if ($env:ZIGINE_VERSION) { $env:ZIGINE_VERSION } else { "dev" }
$Out = Join-Path $Root "dist\zigine-$Target"
$Archive = Join-Path $Root "dist\zigine-$Target.zip"

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$Out\bin", "$Out\lib", "$Out\templates", "$Out\assets" | Out-Null

Push-Location $Root
try {
    zig build "-Dtarget=$Target" -Doptimize=ReleaseSafe

    $ZigEnv = zig env
    $ZigExeMatch = $ZigEnv | Select-String '\.zig_exe = "([^"]+)"'
    $ZigLibMatch = $ZigEnv | Select-String '\.lib_dir = "([^"]+)"'
    $RuntimeZig = if ($env:ZIGINE_RUNTIME_ZIG) { $env:ZIGINE_RUNTIME_ZIG } else { $ZigExeMatch.Matches.Groups[1].Value }
    $RuntimeLib = if ($env:ZIGINE_RUNTIME_LIB_DIR) { $env:ZIGINE_RUNTIME_LIB_DIR } else { $ZigLibMatch.Matches.Groups[1].Value }

    Copy-Item "$Root\zig-out\bin\zigine.exe" "$Out\bin\zigine.exe"
    Copy-Item $RuntimeZig "$Out\bin\zig.exe"
    Copy-Item $RuntimeLib "$Out\lib\zig" -Recurse
    Copy-Item "$Root\templates\sdl3" "$Out\templates\sdl3" -Recurse
    Copy-Item "$Root\templates\raylib" "$Out\templates\raylib" -Recurse
    Copy-Item "$Root\assets\*" "$Out\assets" -Recurse -ErrorAction SilentlyContinue

    @"
Zigine $Version ($Target)

Run bin\zigine.exe to start the editor.
The bundled Zig compiler is used by the embedded terminal and project runner.
SDL3 and raylib project templates are in templates\.
"@ | Set-Content "$Out\README.txt"

    if (Test-Path $Archive) { Remove-Item $Archive -Force }
    Compress-Archive -Path $Out -DestinationPath $Archive
    Write-Host "Created $Archive"
}
finally {
    Pop-Location
}
