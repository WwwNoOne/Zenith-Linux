# Zenith Linux — envoltorio de Windows para construir desde WSL2
#
#   .\build.ps1 check
#   .\build.ps1 image
#   .\build.ps1 vmdk
#   .\build.ps1 iso
#   .\build.ps1 all
#
# Requiere WSL2 con una distro (por defecto Ubuntu) y Podman instalado dentro.

param(
    [ValidateSet("check", "image", "lint", "vmdk", "qcow2", "raw", "iso", "all")]
    [string]$Target = "image",
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"

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
