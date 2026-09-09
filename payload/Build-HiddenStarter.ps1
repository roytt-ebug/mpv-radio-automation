# Build the launch-only helper using the .NET Framework already used by Windows PowerShell.
# No downloads, task changes, playback changes or history writes.
[CmdletBinding()]
param([string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Build this helper with Windows PowerShell 5.1 (powershell.exe).'
}
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'Radio-Hidden.exe' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) {
    throw "Already exists: $OutputPath. Stop the radio and back up that helper before rebuilding, or use a new -OutputPath."
}
$source = Join-Path $PSScriptRoot 'Radio-Hidden.cs'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $source" }
$buildFolder = Join-Path ([IO.Path]::GetTempPath()) ('mpv-radio-build-' + [guid]::NewGuid().ToString('N'))
$provider = $null
try {
    New-Item -ItemType Directory -Path $buildFolder | Out-Null
    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $parameters = New-Object System.CodeDom.Compiler.CompilerParameters
    $parameters.GenerateExecutable = $true
    $parameters.GenerateInMemory = $false
    $parameters.TreatWarningsAsErrors = $true
    $parameters.CompilerOptions = '/target:winexe /optimize+ /platform:anycpu'
    $parameters.OutputAssembly = Join-Path $buildFolder 'Radio-Hidden.exe'
    $parameters.TempFiles = New-Object System.CodeDom.Compiler.TempFileCollection($buildFolder, $false)
    [void]$parameters.ReferencedAssemblies.Add('System.dll')
    $result = $provider.CompileAssemblyFromFile($parameters, $source)
    if ($result.Errors.Count) {
        throw ('Hidden starter build failed: ' + (($result.Errors | ForEach-Object { $_.ToString() }) -join "`n"))
    }
    # Move only a complete build. Never replace an existing executable implicitly.
    [IO.File]::Move($parameters.OutputAssembly, $OutputPath)
    Write-Host "Built hidden starter: $OutputPath"
} finally {
    if ($provider) { $provider.Dispose() }
    # This is only the unique temporary directory created by this invocation.
    if (Test-Path -LiteralPath $buildFolder) { Remove-Item -LiteralPath $buildFolder -Recurse -Force }
}
