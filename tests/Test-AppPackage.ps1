[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SetupPath,
    [switch]$Child,
    [string]$ResultPath = '',
    [string]$BackendTestsPath = ''
)
$ErrorActionPreference = 'Stop'
$SetupPath = [IO.Path]::GetFullPath($SetupPath)
if ($Child) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $exitCode = 0
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Package test must run as a standard user.' }
        $local = [Environment]::GetFolderPath('LocalApplicationData')
        if (-not $local) { throw 'The test user profile was not loaded.' }
        $app = Join-Path $local 'Programs\Automatic Music'
        $data = Join-Path $local 'Automatic Music'
        if ((Test-Path -LiteralPath $app) -or (Test-Path -LiteralPath $data)) { throw 'Refusing to use an existing app/data directory.' }
        $lines.Add('PASS: running under a new standard-user Windows account.')
        $installArgs = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + (Join-Path (Split-Path $ResultPath) 'install.log') + '"'))
        $install = Start-Process -FilePath $SetupPath -ArgumentList $installArgs -PassThru -Wait
        if ($install.ExitCode -ne 0) { throw "Installer exited $($install.ExitCode)." }
        $exe = Join-Path $app 'AutomaticMusic.exe'
        if (-not (Test-Path -LiteralPath $exe)) { throw 'App did not install at its per-user default path.' }
        if (-not (Test-Path -LiteralPath (Join-Path $app 'Install-Components.ps1'))) { throw 'Component setup script was not installed.' }
        $registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{AB9A4557-CEAB-4FA8-9044-5330EF7175DE}_is1'
        if (-not (Test-Path -LiteralPath $registry)) { throw 'Per-user Windows uninstall registration is missing.' }
        $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Automatic Music.lnk'
        if (-not (Test-Path -LiteralPath $shortcut)) { throw 'Start menu shortcut is missing.' }
        $lines.Add('PASS: standard-user install, app files, Start menu shortcut and HKCU uninstall entry.')
        $ui = Start-Process -FilePath $exe -ArgumentList '--self-test' -Wait -PassThru
        if ($ui.ExitCode -ne 0) { throw 'Installed UI self-test failed.' }
        $lines.Add('PASS: installed native app starts and its UI self-test passes.')

        if ($BackendTestsPath) {
            $testExe = Join-Path $app 'AppBackendTests.exe'
            Copy-Item -LiteralPath $BackendTestsPath -Destination $testExe
            try {
                $taskOutput = Join-Path (Split-Path $ResultPath) 'task-tests.txt'
                $taskErrors = Join-Path (Split-Path $ResultPath) 'task-errors.txt'
                $taskTest = Start-Process -FilePath $testExe -ArgumentList @('--scheduler-only', ('"' + $app + '"')) -Wait -PassThru -RedirectStandardOutput $taskOutput -RedirectStandardError $taskErrors
                if (Test-Path -LiteralPath $taskOutput) { foreach ($line in Get-Content -LiteralPath $taskOutput) { $lines.Add($line) } }
                if ($taskTest.ExitCode -ne 0) { throw ('Standard-user scheduler tests failed. ' + [IO.File]::ReadAllText($taskErrors)) }
                $lines.Add('PASS: real task registration and ownership checks work without administrator membership.')
            } finally { Remove-Item -LiteralPath $testExe -Force -ErrorAction SilentlyContinue }
        }

        [void][IO.Directory]::CreateDirectory((Join-Path $data 'Player\portable_config'))
        $settings = Join-Path $data 'settings.json'
        $history = Join-Path $data 'Player\portable_config\recent-track-history.txt'
        [IO.File]::WriteAllText($settings, '{"Schema":1,"AudioDeviceId":"auto","Volume":61,"SamplingEnabled":true,"CutoffMinutes":15,"SampleMinMinutes":10,"SampleMaxMinutes":30,"FadeSeconds":5,"Morning":{"Enabled":false,"PlaylistUrl":"","StartTime":"06:45","Days":["Mon"],"DurationMinutes":180},"Finisher":{"Enabled":false,"PlaylistUrl":"","StartTime":"15:45","Days":["Fri"],"DurationMinutes":180}}')
        [IO.File]::WriteAllText($history, '2026-11-19|package-test-preserve')
        $settingsHash = (Get-FileHash -LiteralPath $settings).Hash
        $historyHash = (Get-FileHash -LiteralPath $history).Hash
        $upgrade = Start-Process -FilePath $SetupPath -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -PassThru -Wait
        if ($upgrade.ExitCode -ne 0) { throw "Upgrade exited $($upgrade.ExitCode)." }
        if ((Get-FileHash -LiteralPath $settings).Hash -ne $settingsHash -or (Get-FileHash -LiteralPath $history).Hash -ne $historyHash) { throw 'Upgrade changed settings or history.' }
        $lines.Add('PASS: repeat installation preserves settings and listening history byte-for-byte.')

        $uninstaller = Join-Path $app 'unins000.exe'
        $remove = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -PassThru -Wait
        if ($remove.ExitCode -ne 0) { throw "Uninstall exited $($remove.ExitCode)." }
        # Inno's cloned uninstaller may still be completing file cleanup at return.
        for ($attempt = 0; $attempt -lt 30 -and (Test-Path -LiteralPath $exe); $attempt++) { Start-Sleep -Milliseconds 200 }
        if (Test-Path -LiteralPath $exe) { throw 'Uninstall left the app executable behind.' }
        if (Test-Path -LiteralPath $registry) { throw 'Uninstall left its Windows registration behind.' }
        if (Test-Path -LiteralPath $shortcut) { throw 'Uninstall left its Start menu shortcut behind.' }
        if ((Get-FileHash -LiteralPath $settings).Hash -ne $settingsHash -or (Get-FileHash -LiteralPath $history).Hash -ne $historyHash) { throw 'Uninstall changed retained settings or history.' }
        $lines.Add('PASS: standard-user uninstall removes app, shortcut and registration, retaining preferences/history.')
    } catch {
        $lines.Add('FAIL: ' + $_.Exception.ToString())
        $exitCode = 1
    } finally {
        [IO.File]::WriteAllLines($ResultPath, $lines, [Text.UTF8Encoding]::new($false))
    }
    exit $exitCode
}

# Dedicated hosted Windows test: create an isolated non-administrator account.
# No passwords or user files are printed. Everything belongs to this fixture.
$account = 'amtest' + [guid]::NewGuid().ToString('N').Substring(0,8)
$root = Join-Path $env:PUBLIC ('AutomaticMusic-package-test-' + [guid]::NewGuid().ToString('N'))
$userCreated = $false
try {
    [void][IO.Directory]::CreateDirectory($root)
    $password = ConvertTo-SecureString ('Am!' + [guid]::NewGuid().ToString('N') + '9a') -AsPlainText -Force
    $user = New-LocalUser -Name $account -Password $password -Description 'Temporary Automatic Music installer acceptance test' -PasswordNeverExpires
    $userCreated = $true
    $usersGroup = Get-LocalGroup -SID 'S-1-5-32-545'
    Add-LocalGroupMember -Group $usersGroup -Member $user
    & icacls.exe $root /grant ($account + ':(OI)(CI)M') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not set fixture folder permissions.' }
    $setupCopy = Join-Path $root 'Setup.exe'
    $scriptCopy = Join-Path $root 'Test-AppPackage.ps1'
    $result = Join-Path $root 'result.txt'
    Copy-Item -LiteralPath $SetupPath -Destination $setupCopy
    Copy-Item -LiteralPath $PSCommandPath -Destination $scriptCopy
    if (-not $BackendTestsPath) { $BackendTestsPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\AutomaticMusic\AppBackendTests.exe' }
    $backendCopy = Join-Path $root 'AppBackendTests.exe'
    Copy-Item -LiteralPath $BackendTestsPath -Destination $backendCopy
    $credentials = New-Object Management.Automation.PSCredential(($env:COMPUTERNAME + '\' + $account), $password)
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptCopy + '" -Child -SetupPath "' + $setupCopy + '" -ResultPath "' + $result + '" -BackendTestsPath "' + $backendCopy + '"'
    $process = Start-Process -FilePath $powershell -Credential $credentials -LoadUserProfile -WorkingDirectory $root -ArgumentList $arguments -PassThru
    if (-not $process.WaitForExit(180000)) { $process.Kill(); throw 'Standard-user installer test timed out.' }
    if (Test-Path -LiteralPath $result) { Get-Content -LiteralPath $result }
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $result)) { throw 'Standard-user package acceptance failed.' }
} finally {
    if ($userCreated) { Remove-LocalUser -Name $account -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
