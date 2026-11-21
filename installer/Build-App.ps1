[CmdletBinding()]
param([string]$OutputDirectory = '', [switch]$SkipInstaller)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Build with Windows PowerShell 5.1 on Windows x64.'
}
$repo = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$package = Join-Path $OutputDirectory 'AutomaticMusic'
if (Test-Path -LiteralPath $package) {
    throw "Build output already exists: $package. Use a new OutputDirectory or remove only that generated folder."
}
[void][IO.Directory]::CreateDirectory($package)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework C# compiler is missing.' }

# A code-drawn icon keeps the app asset reproducible without third-party artwork.
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object Drawing.Bitmap(256,256)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$background = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(22,91,108))
$foreground = New-Object Drawing.SolidBrush([Drawing.Color]::White)
$pen = New-Object Drawing.Pen([Drawing.Color]::White,17)
try {
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.FillEllipse($background,8,8,240,240)
    $graphics.DrawLine($pen,101,86,101,177)
    $graphics.DrawLine($pen,178,69,178,160)
    $graphics.DrawLine($pen,101,85,178,68)
    $graphics.DrawLine($pen,101,106,178,89)
    $graphics.FillEllipse($foreground,59,160,50,33)
    $graphics.FillEllipse($foreground,136,143,50,33)
    $png = New-Object IO.MemoryStream
    try {
        $bitmap.Save($png, [Drawing.Imaging.ImageFormat]::Png)
        $bytes = $png.ToArray()
        $iconPath = Join-Path $package 'AutomaticMusic.ico'
        $stream = [IO.File]::Create($iconPath)
        $writer = New-Object IO.BinaryWriter($stream)
        try {
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
            $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$bytes.Length); $writer.Write([uint32]22); $writer.Write($bytes)
        } finally { $writer.Dispose(); $stream.Dispose() }
    } finally { $png.Dispose() }
} finally { $pen.Dispose(); $foreground.Dispose(); $background.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }

$references = @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll',
    'System.Web.Extensions.dll','System.Xml.dll','System.Net.Http.dll','Microsoft.CSharp.dll',
    'System.IO.Compression.dll','System.IO.Compression.FileSystem.dll')
$arguments = @('/nologo','/target:winexe','/platform:x64','/optimize+','/warnaserror+','/codepage:65001',
    ('/out:' + (Join-Path $package 'AutomaticMusic.exe')),
    ('/win32manifest:' + (Join-Path $repo 'app\app.manifest')),
    ('/win32icon:' + $iconPath))
$arguments += $references | ForEach-Object { '/reference:' + $_ }
$arguments += Get-ChildItem -LiteralPath (Join-Path $repo 'app') -Filter '*.cs' | ForEach-Object { $_.FullName }
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw "App compilation failed ($LASTEXITCODE)." }

Copy-Item -LiteralPath (Join-Path $repo 'app\AutomaticMusic.exe.config') -Destination $package
Copy-Item -LiteralPath (Join-Path $repo 'app\Install-Components.ps1') -Destination $package
Copy-Item -LiteralPath (Join-Path $repo 'app\components.lock.json') -Destination $package
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $package
Copy-Item -LiteralPath (Join-Path $repo 'THIRD_PARTY.md') -Destination $package
Copy-Item -LiteralPath (Join-Path $repo 'docs\WINDOWS-APP.md') -Destination (Join-Path $package 'START-HERE.md')
$engine = Join-Path $package 'engine'
[void][IO.Directory]::CreateDirectory($engine)
foreach ($name in @('Radio.ps1','Check-Radio.ps1','Radio-Hidden.cs','Build-HiddenStarter.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repo ('payload\' + $name)) -Destination $engine
}
Copy-Item -LiteralPath (Join-Path $repo 'payload\portable_config') -Destination $engine -Recurse
& (Join-Path $repo 'payload\Build-HiddenStarter.ps1') -OutputPath (Join-Path $engine 'Radio-Hidden.exe')

$portable = Join-Path $OutputDirectory 'Automatic-Music-0.2.0-beta.2-portable.zip'
Compress-Archive -LiteralPath $package -DestinationPath $portable -CompressionLevel Optimal
if (-not $SkipInstaller) {
    $iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    if (-not (Test-Path -LiteralPath $iscc)) {
        $found = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($found) { $iscc = $found.Source } else { throw 'Install Inno Setup 6 to build the setup EXE, or use -SkipInstaller for the portable app.' }
    }
    & $iscc ('/DAppFiles=' + $package) ('/DArtifactDir=' + $OutputDirectory) (Join-Path $PSScriptRoot 'AutomaticMusic.iss')
    if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed ($LASTEXITCODE)." }
}
$hashes = @(Get-ChildItem -LiteralPath $OutputDirectory -File | Where-Object { $_.Extension -in @('.exe','.zip') } | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.Name
})
[IO.File]::WriteAllLines((Join-Path $OutputDirectory 'SHA256SUMS.txt'), $hashes, [Text.UTF8Encoding]::new($false))
Write-Host "Built Automatic Music 0.2.0-beta.2: $OutputDirectory"
