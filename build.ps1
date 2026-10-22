# Zenith Linux — envoltorio de Windows para construir desde WSL2
#
#   .\build.ps1 check
#   .\build.ps1 image
#   .\build.ps1 vmdk
#   .\build.ps1 iso
#   .\build.ps1 all
#
# Requiere WSL2 con una distro y Podman instalado dentro. Si no se indica
# -Distro se usa la primera distro Ubuntu* disponible (p. ej. Ubuntu-24.04).

param(
    [ValidateSet("check", "image", "lint", "verify", "vmdk", "qcow2", "raw", "iso", "all")]
    [string]$Target = "image",
    [string]$Distro = ""
)

$ErrorActionPreference = "Stop"

if (-not $Distro) {
    # wsl.exe escribe en UTF-16: se limpian los NUL que PowerShell deja al
    # capturar la salida.
    $distros = @(wsl -l -q 2>$null |
        ForEach-Object { ($_ -replace "`0", "").Trim() } |
        Where-Object { $_ })
    $Distro = $distros | Where-Object { $_ -like "Ubuntu*" } | Select-Object -First 1
    if (-not $Distro) { $Distro = $distros | Select-Object -First 1 }
    if (-not $Distro) {
        throw "No hay ninguna distro WSL instalada. Ejecuta: wsl --install -d Ubuntu-24.04"
    }
}

Write-Host "Distro WSL: $Distro" -ForegroundColor Cyan

$repo = (Resolve-Path $PSScriptRoot).Path
$drive = $repo.Substring(0, 1).ToLower()
$rest = $repo.Substring(2) -replace '\\', '/'
$wslPath = "/mnt/$drive$rest"

Write-Host "Repositorio en WSL: $wslPath" -ForegroundColor Cyan
Write-Host "Construyendo: $Target" -ForegroundColor Cyan

wsl -d $Distro -- bash -lc "cd '$wslPath' && chmod +x build.sh && ./build.sh $Target"
if ($LASTEXITCODE -ne 0) {
    throw "La construcción falló con código $LASTEXITCODE"
}
