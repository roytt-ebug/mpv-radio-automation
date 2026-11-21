# Automatic Music: pinned, per-user component installation for Windows x64.
# -FunctionsOnly imports helpers for offline tests; it never installs anything.
[CmdletBinding()]
param(
    [string]$DataRoot = '',
    [string]$ManifestPath = '',
    [switch]$CheckOnly,
    [switch]$Repair,
    [switch]$FunctionsOnly
)
$ErrorActionPreference = 'Stop'

function Read-RadioComponentJson([string]$Path, [int]$MaximumBytes = 1048576) {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -gt $MaximumBytes -or $item.Length -eq 0) { throw "Invalid or oversized component metadata: $Path" }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Component metadata cannot be a link: $Path" }
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $text = $utf8.GetString([IO.File]::ReadAllBytes($Path)).TrimStart([char]0xFEFF)
    return $text | ConvertFrom-Json
}

function Assert-RadioComponentPath([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Component paths cannot pass through links or junctions: $current" }
        }
        $parent = [IO.Path]::GetDirectoryName($current.TrimEnd([char[]]'\/'))
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Get-RadioComponentChildPath([string]$Directory, [string]$RelativePath) {
    $relative = $RelativePath.Replace('\', '/')
    while ($relative.StartsWith('./')) { $relative = $relative.Substring(2) }
    $relative = $relative.TrimEnd('/')
    if (-not $relative -or $relative -match '[\x00-\x1f:*?"<>|]' -or [IO.Path]::IsPathRooted($relative)) { throw "Unsafe component archive path: $RelativePath" }
    foreach ($part in ($relative -split '/')) {
        if (-not $part -or $part -in @('.', '..') -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') { throw "Unsafe component archive path: $RelativePath" }
    }
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $Directory $relative))
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "Component path escapes its bundle: $RelativePath" }
    return $full
}

function Read-RadioComponentManifest([string]$Path) {
    $manifest = Read-RadioComponentJson $Path
    if ($manifest.schema -ne 1 -or $manifest.architecture -cne 'x64' -or $manifest.bundle -cnotmatch '\A[0-9][A-Za-z0-9._-]{0,63}\z' -or $manifest.bundle.EndsWith('.')) { throw 'Unsupported component manifest schema, architecture or bundle ID.' }
    if (@($manifest.components).Count -ne 3) { throw 'The component manifest must contain MPV, yt-dlp and Deno exactly once.' }
    $seen = @{}
    foreach ($component in $manifest.components) {
        if ($seen.ContainsKey([string]$component.id)) { throw 'The component manifest contains a duplicate component.' }
        $seen[[string]$component.id] = $true
        $expected = ''
        switch -CaseSensitive ($component.id) {
            'mpv' {
                if ($component.version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+\z' -or $component.format -cne 'zip') { throw 'Invalid official x64 MPV component.' }
                $expected = 'https://github.com/mpv-player/mpv/releases/download/v' + $component.version + '/mpv-v' + $component.version + '-x86_64-pc-windows-msvc.zip'
            }
            'ytDlp' {
                if ($component.version -cnotmatch '\A[0-9]{4}\.[0-9]{2}\.[0-9]{2}\z' -or $component.format -cne 'exe') { throw 'Invalid yt-dlp component.' }
                $expected = 'https://github.com/yt-dlp/yt-dlp/releases/download/' + $component.version + '/yt-dlp.exe'
            }
            'deno' {
                if ($component.version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+\z' -or [version]$component.version -lt [version]'2.3.0' -or $component.format -cne 'zip') { throw 'Invalid supported Deno component.' }
                $expected = 'https://github.com/denoland/deno/releases/download/v' + $component.version + '/deno-x86_64-pc-windows-msvc.zip'
            }
            default { throw 'Unknown component in the manifest.' }
        }
        if ($component.url -cne $expected -or $component.sha256 -cnotmatch '\A[a-f0-9]{64}\z' -or ($component.size -isnot [int] -and $component.size -isnot [long]) -or $component.size -lt 1024 -or $component.size -gt 536870912) { throw "Invalid pinned URL, SHA-256 or size for $($component.id)." }
    }
    return $manifest
}

function Join-RadioComponentArguments([string[]]$Values) {
    return (($Values | ForEach-Object {
        $escaped = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
    }) -join ' ')
}

function Invoke-RadioComponentProcess([string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory, [int]$TimeoutSeconds = 20) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = Join-RadioComponentArguments $Arguments
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not start $Executable." }
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Only terminate this invocation's own child and its descendants.
            $killer = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
            if (Test-Path -LiteralPath $killer) { try { & $killer /PID $process.Id /T /F 2>&1 | Out-Null } catch { } }
            if (-not $process.HasExited) { $process.Kill() }
            throw "Component command timed out: $([IO.Path]::GetFileName($Executable))."
        }
        if (-not $output.Wait(2000) -or -not $errors.Wait(2000)) { throw 'Component output did not finish.' }
        if ($output.Result.Length -gt 2097152 -or $errors.Result.Length -gt 2097152) { throw 'Component command returned too much output.' }
        if ($process.ExitCode -ne 0) { throw "$([IO.Path]::GetFileName($Executable)) failed (exit $($process.ExitCode)): $($errors.Result.Trim())" }
        return [pscustomobject]@{ Output=$output.Result; Error=$errors.Result }
    } finally { $process.Dispose() }
}

function Get-RadioComponentDownload($Component, [string]$Destination) {
    Write-Host "Downloading $($Component.id) $($Component.version)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create([uri]$Component.url)
    $request.UserAgent = 'AutomaticMusic-Setup/1'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $request.MaximumAutomaticRedirections = 5
    $response = $null; $downloadInput = $null; $downloadOutput = $null
    try {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $response = $request.GetResponse()
        $hostName = $response.ResponseUri.DnsSafeHost
        if ($response.ResponseUri.Scheme -cne 'https' -or ($hostName -ine 'github.com' -and -not $hostName.EndsWith('.githubusercontent.com', [StringComparison]::OrdinalIgnoreCase))) { throw 'The official component download redirected outside its trusted HTTPS asset hosts.' }
        if ($response.ContentLength -ge 0 -and $response.ContentLength -ne $Component.size) { throw "Downloaded $($Component.id) has the wrong declared size." }
        $downloadInput = $response.GetResponseStream()
        $downloadOutput = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 65536
        $total = [long]0; $reported = [long]0
        while (($count = $downloadInput.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $count
            if ($total -gt $Component.size) { throw 'Component download exceeded its pinned size.' }
            if ($clock.Elapsed.TotalSeconds -gt 600) { throw 'Component download timed out.' }
            $downloadOutput.Write($buffer, 0, $count)
            if ($total - $reported -ge 5242880) {
                Write-Host ("Downloading {0}: {1}%" -f $Component.id, [math]::Floor(100 * $total / $Component.size))
                $reported = $total
            }
        }
        if ($total -ne $Component.size) { throw 'Component download ended before the complete file arrived.' }
    } finally {
        if ($downloadOutput) { $downloadOutput.Dispose() }
        if ($downloadInput) { $downloadInput.Dispose() }
        if ($response) { $response.Dispose() }
        $request.Abort()
    }
}

function Assert-RadioComponentDownload($Component, [string]$Path) {
    if ((Get-Item -LiteralPath $Path).Length -ne $Component.size) { throw "Downloaded $($Component.id) has the wrong size. Nothing was activated." }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Component.sha256) { throw "SHA-256 mismatch for $($Component.id). Nothing was activated." }
    Write-Host "Verified $($Component.id) download."
}

# Upstream mpv-player's signed-release artifact includes mpv.exe, mpv.com and
# the Vulkan loader (needed even for audio-only starts on some Windows systems).
# Reuse our path-safe, bounded ZIP extractor below.
function Expand-RadioMpvArchive([string]$Archive, [string]$Destination) {
    Expand-RadioDenoArchive $Archive $Destination
    foreach ($required in @('mpv.exe', 'mpv.com', 'vulkan-1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Destination $required) -PathType Leaf)) {
            throw "The official MPV archive is missing $required."
        }
    }
}
function Expand-RadioDenoArchive([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $entries = @($zip.Entries)
        if (-not $entries.Count -or $entries.Count -gt 100) { throw 'Unexpected Deno archive entry count.' }
        $total = [long]0
        $seen = @{}
        # Validate all entries before creating even the first extracted file.
        foreach ($entry in $entries) {
            $target = Get-RadioComponentChildPath $Destination $entry.FullName
            if ($seen.ContainsKey($target)) { throw 'The Deno archive contains duplicate paths.' }
            $seen[$target] = $true
            $mode = ($entry.ExternalAttributes -shr 16) -band 61440
            if ($mode -in @(40960,24576,8192,49152,4096) -or ($entry.ExternalAttributes -band 1024) -ne 0) { throw 'The Deno archive contains a link or special file.' }
            $total += $entry.Length
            if ($total -gt 1073741824) { throw 'The Deno archive expands beyond its allowed size.' }
        }
        foreach ($entry in $entries) {
            $target = Get-RadioComponentChildPath $Destination $entry.FullName
            if ($entry.FullName.EndsWith('/')) { New-Item -ItemType Directory -Path $target -Force | Out-Null; continue }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
        }
    } finally { $zip.Dispose() }
}

function Get-RadioComponentFiles([string]$Directory) {
    Assert-RadioComponentPath $Directory
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($Directory)
    $files = New-Object 'System.Collections.Generic.List[IO.FileInfo]'
    $count = 0
    while ($pending.Count) {
        $nextDirectory = $pending.Dequeue()
        foreach ($item in (Get-ChildItem -LiteralPath $nextDirectory -Force)) {
            $count++
            if ($count -gt 5000) { throw 'The component bundle contains too many files.' }
            # Check each directory before descending, never follow a junction.
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Component bundles must not contain links or junctions.' }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
            else { $files.Add($item) }
        }
    }
    $total = [long]0
    foreach ($item in ($files | Sort-Object FullName)) {
        $relative = $item.FullName.Substring($root.Length).Replace('\', '/')
        $null = Get-RadioComponentChildPath $Directory $relative
        if ($relative -ceq 'bundle.json') { continue }
        $total += $item.Length
        if ($total -gt 1073741824) { throw 'The component bundle exceeds its size limit.' }
        [pscustomobject]@{ path=$relative; length=$item.Length; sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
}

function Test-RadioMpvVersionOutput([string]$Output, [string]$ExpectedHash) {
    # Use MPV's own header, not linked FFmpeg/library version numbers.
    $header = [regex]::Match($Output, '(?im)^[\t ]*mpv[\t ]+(?<version>\S+)')
    if (-not $header.Success) { return $false }
    if ($ExpectedHash -match '\A[0-9]+\.[0-9]+\.[0-9]+\z') {
        return $header.Groups['version'].Value -ceq ('v' + $ExpectedHash)
    }
    if ($ExpectedHash -notmatch '\A[0-9a-f]{7,40}\z') { return $false }
    $match = [regex]::Match($header.Groups['version'].Value, '(?i)(?:-g|^g?)(?<hash>[0-9a-f]{7,40})(?:-dirty)?$')
    if (-not $match.Success) { return $false }
    $reportedHash = $match.Groups['hash'].Value
    return ($ExpectedHash.StartsWith($reportedHash, [StringComparison]::OrdinalIgnoreCase) -or $reportedHash.StartsWith($ExpectedHash, [StringComparison]::OrdinalIgnoreCase))
}

function Test-RadioComponentVersions([string]$Directory, $Versions) {
    foreach ($name in @('mpv.exe','mpv.com','yt-dlp.exe','deno.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory $name) -PathType Leaf)) { throw "Component bundle is missing $name." }
    }
    Write-Host 'Checking MPV, yt-dlp and Deno...'
    $checks = @(
        @{ File='mpv.com'; Arguments=@('--no-config','--load-scripts=no','--version'); Token=([string]$Versions.mpv -replace '^.*-git-', '') },
        @{ File='yt-dlp.exe'; Arguments=@('--ignore-config','--version'); Token=[string]$Versions.ytDlp },
        @{ File='deno.exe'; Arguments=@('--version'); Token=('deno ' + $Versions.deno) }
    )
    foreach ($check in $checks) {
        if (-not $check.Token) { throw 'Missing component version in the bundle receipt.' }
        $result = Invoke-RadioComponentProcess (Join-Path $Directory $check.File) $check.Arguments $Directory 20
        $matchesVersion = if ($check.File -eq 'mpv.com') { Test-RadioMpvVersionOutput $result.Output $check.Token } else { $result.Output.IndexOf($check.Token, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
        if (-not $matchesVersion) {
            $stdout = $result.Output.Trim()
            $stderr = $result.Error.Trim()
            if ($stdout.Length -gt 1024) { $stdout = $stdout.Substring(0, 1024) + '... [truncated]' }
            if ($stderr.Length -gt 1024) { $stderr = $stderr.Substring(0, 1024) + '... [truncated]' }
            throw "$($check.File) did not report its expected version ($($check.Token)). Standard output: $stdout; Standard error: $stderr"
        }
    }
}

function Get-RadioInstalledComponents([string]$Root, [string]$ExpectedManifestHash = '') {
    $pointer = Read-RadioComponentJson (Join-Path $Root 'components.json')
    if ($pointer.schema -ne 1 -or $pointer.bundle -cnotmatch '\A[0-9][A-Za-z0-9._-]{0,63}\z' -or -not [IO.Path]::IsPathRooted([string]$pointer.directory)) { throw 'Invalid installed component pointer.' }
    $componentsRoot = [IO.Path]::GetFullPath((Join-Path $Root 'Components')).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    $directory = [IO.Path]::GetFullPath([string]$pointer.directory).TrimEnd([char[]]'\/')
    if (-not $directory.StartsWith($componentsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Installed component directory is outside this application.' }
    Assert-RadioComponentPath $directory
    $receipt = Read-RadioComponentJson (Join-Path $directory 'bundle.json')
    if ($receipt.schema -ne 1 -or $receipt.bundle -cne $pointer.bundle -or $receipt.manifestSha256 -cnotmatch '\A[a-f0-9]{64}\z') { throw 'Invalid component bundle receipt.' }
    if ($ExpectedManifestHash -and $receipt.manifestSha256 -cne $ExpectedManifestHash) { throw 'The installed component bundle does not match this app version.' }
    foreach ($id in @('mpv','ytDlp','deno')) {
        if (-not $pointer.versions.$id -or $pointer.versions.$id -cne $receipt.versions.$id) { throw 'Component versions do not match the bundle receipt.' }
    }
    $actual = @(Get-RadioComponentFiles $directory)
    if ($actual.Count -ne @($receipt.files).Count -or -not $actual.Count) { throw 'Component files do not match the bundle receipt.' }
    $expectedFiles = @{}
    foreach ($file in $receipt.files) {
        $null = Get-RadioComponentChildPath $directory ([string]$file.path)
        if ($expectedFiles.ContainsKey([string]$file.path) -or $file.sha256 -cnotmatch '\A[a-f0-9]{64}\z') { throw 'Invalid component file receipt.' }
        $expectedFiles[[string]$file.path] = $file
    }
    foreach ($file in $actual) {
        $expected = $expectedFiles[$file.path]
        if (-not $expected -or $file.length -ne $expected.length -or $file.sha256 -cne $expected.sha256) { throw "Component changed or is damaged: $($file.path). Use Repair components." }
    }
    Test-RadioComponentVersions $directory $pointer.versions
    return $pointer
}

function Write-RadioComponentJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

function Install-RadioComponents([string]$Root, [string]$LockPath, [switch]$OnlyCheck, [switch]$ForceRepair) {
    if (-not $Root -or -not [IO.Path]::IsPathRooted($Root)) { throw 'Supply an absolute per-user DataRoot folder.' }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    if ($rootPath -notmatch '^[A-Za-z]:\\.+' -or $rootPath -eq [IO.Path]::GetPathRoot($rootPath).TrimEnd('\')) { throw 'DataRoot must be a local application folder, not a drive root or network share.' }
    Assert-RadioComponentPath $rootPath
    $manifest = Read-RadioComponentManifest $LockPath
    $manifestHash = (Get-FileHash -LiteralPath $LockPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $lock = $null; $staging = $null; $pointerTemporary = $null
    try {
        if (-not $OnlyCheck) {
            New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
            try { $lock = [IO.File]::Open((Join-Path $rootPath 'components.install.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
            catch { throw 'Another component installation is already running, or this application folder is not writable.' }
        }
        try {
            $current = Get-RadioInstalledComponents $rootPath $manifestHash
            if ($OnlyCheck -or -not $ForceRepair) { return $current }
            Write-Host 'Preparing a verified replacement; the current bundle will be retained.'
        } catch {
            if ($OnlyCheck) { throw }
            Write-Host ('Components need installation or repair: ' + $_.Exception.Message)
        }
        $staging = Join-Path $rootPath ('component-staging-' + [guid]::NewGuid().ToString('N'))
        $downloads = Join-Path $staging 'downloads'
        $bundle = Join-Path $staging 'bundle'
        New-Item -ItemType Directory -Path $downloads,$bundle -Force | Out-Null
        # Verify every archive first. No downloaded executable runs until all
        # three pinned artifacts have passed size and SHA-256 verification.
        foreach ($component in $manifest.components) {
            $download = Join-Path $downloads ($component.id + '.' + $component.format)
            Get-RadioComponentDownload $component $download
            Assert-RadioComponentDownload $component $download
        }
        Write-Host 'Extracting verified components...'
        Expand-RadioMpvArchive (Join-Path $downloads 'mpv.zip') $bundle
        Expand-RadioDenoArchive (Join-Path $downloads 'deno.zip') $bundle
        [IO.File]::Copy((Join-Path $downloads 'ytDlp.exe'), (Join-Path $bundle 'yt-dlp.exe'), $false)
        $versions = [ordered]@{}
        foreach ($component in $manifest.components) { $versions[$component.id] = $component.version }
        $files = @(Get-RadioComponentFiles $bundle)
        Test-RadioComponentVersions $bundle $versions
        $installedUtc = [datetime]::UtcNow.ToString('o')
        $receipt = [ordered]@{ schema=1; bundle=$manifest.bundle; manifestSha256=$manifestHash; versions=$versions; files=$files; installedUtc=$installedUtc }
        Write-RadioComponentJson (Join-Path $bundle 'bundle.json') $receipt
        $componentsRoot = Join-Path $rootPath 'Components'
        Assert-RadioComponentPath $componentsRoot
        New-Item -ItemType Directory -Path $componentsRoot -Force | Out-Null
        $destination = Join-Path $componentsRoot $manifest.bundle
        if (Test-Path -LiteralPath $destination) { $destination += '-repair-' + [guid]::NewGuid().ToString('N') }
        [IO.Directory]::Move($bundle, $destination)
        $pointer = [ordered]@{ schema=1; bundle=$manifest.bundle; directory=$destination; versions=$versions; installedUtc=$installedUtc }
        $pointerPath = Join-Path $rootPath 'components.json'
        Assert-RadioComponentPath $pointerPath
        $pointerTemporary = Join-Path $rootPath ('components-pointer-' + [guid]::NewGuid().ToString('N') + '.tmp')
        Write-RadioComponentJson $pointerTemporary $pointer
        if (Test-Path -LiteralPath $pointerPath -PathType Leaf) {
            $previous = Join-Path $rootPath 'components.previous.json'
            Assert-RadioComponentPath $previous
            [IO.File]::Replace($pointerTemporary, $pointerPath, $previous)
        } else { [IO.File]::Move($pointerTemporary, $pointerPath) }
        Write-Host 'Verified components activated. Previous bundles were kept.'
        return [pscustomobject]$pointer
    } finally {
        if ($pointerTemporary -and (Test-Path -LiteralPath $pointerTemporary)) { Remove-Item -LiteralPath $pointerTemporary -Force }
        if ($staging -and (Test-Path -LiteralPath $staging)) { Remove-Item -LiteralPath $staging -Recurse -Force }
        if ($lock) { $lock.Dispose() }
    }
}

if ($FunctionsOnly) { return }
try {
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw 'Run this setup with 64-bit Windows PowerShell 5.1 on Windows 10 (2004+) or Windows 11 x64.' }
    if ($CheckOnly -and $Repair) { throw 'Choose CheckOnly or Repair, not both.' }
    if (-not $ManifestPath) { $ManifestPath = Join-Path $PSScriptRoot 'components.lock.json' }
    $result = Install-RadioComponents -Root $DataRoot -LockPath $ManifestPath -OnlyCheck:$CheckOnly -ForceRepair:$Repair
    Write-Host ('Components ready: ' + $result.bundle)
    exit 0
} catch {
    Write-Error ('Component setup failed: ' + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
