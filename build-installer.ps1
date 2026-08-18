$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root "dist"
$payload = Join-Path $dist "payload_gestor_clean.zip"
$exe = Join-Path $dist "Instalador_Foroactivo_Multilenguaje.exe"
$alias = Join-Path $dist "Forum_Theme_Programmer.exe"
$launcher = Join-Path $root "installer-builder\Program.cs"
$icon = Join-Path $root "assets\foroactivo_installer.ico"
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

function Get-FreeSubstDrive {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($letter in @("Z","Y","X","W","V","U","T","S","R","Q","P")) {
        if ($used -notcontains $letter) {
            return ($letter + ":")
        }
    }
    throw "No hay una letra de unidad libre para compilar en una ruta sin acentos."
}

if (-not (Test-Path -LiteralPath $csc)) {
    throw "No se encontró csc.exe en $csc"
}

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "No se encontró el lanzador en $launcher"
}

if (-not (Test-Path -LiteralPath $icon)) {
    throw "No se encontró el icono en $icon"
}

if (Test-Path -LiteralPath $dist) {
    Remove-Item -LiteralPath $dist -Recurse -Force
}
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$payloadItems = @(
    "assets",
    "docs",
    "migrations",
    "panel",
    "scripts",
    "src",
    "ABRIR_INSTALADOR.bat",
    "abrir-instalador.sh",
    "INSTALAR_SIN_CONSOLA.bat",
    "package.json",
    "README.md",
    "RELEASE_NOTES_V1.txt",
    "RELEASE_NOTES_V1_4.txt",
    "RELEASE_NOTES_V1_5.txt",
    "wrangler.jsonc"
)

$paths = foreach ($item in $payloadItems) {
    $path = Join-Path $root $item
    if (Test-Path -LiteralPath $path) { $path }
}

Compress-Archive -LiteralPath $paths -DestinationPath $payload -Force

$buildDrive = Get-FreeSubstDrive
try {
    & cmd.exe /c "subst $buildDrive `"$root`""
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo montar la unidad temporal $buildDrive"
    }

    $driveRoot = $buildDrive + "\"
    $mappedPayload = Join-Path $driveRoot "dist\payload_gestor_clean.zip"
    $mappedLauncher = Join-Path $driveRoot "installer-builder\Program.cs"
    $mappedIcon = Join-Path $driveRoot "assets\foroactivo_installer.ico"
    $mappedExe = Join-Path $driveRoot "dist\Instalador_Foroactivo_Multilenguaje.exe"

    $args = @(
        "/nologo",
        "/target:winexe",
        "/platform:x64",
        "/out:$mappedExe",
        "/win32icon:$mappedIcon",
        "/resource:$mappedPayload,InstallerPayload.zip",
        "/reference:System.Windows.Forms.dll",
        "/reference:System.Drawing.dll",
        "/reference:System.Management.dll",
        "/reference:System.IO.Compression.dll",
        "/reference:System.IO.Compression.FileSystem.dll",
        $mappedLauncher
    )

    & $csc @args
    if ($LASTEXITCODE -ne 0) {
        throw "Falló la compilación del instalador."
    }
}
finally {
    & cmd.exe /c "subst $buildDrive /d" 2>$null | Out-Null
}

Copy-Item -LiteralPath $exe -Destination $alias -Force

Get-Item -LiteralPath $exe, $alias, $payload |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize
