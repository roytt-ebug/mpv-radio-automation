"""Windows-only integration: one actual MPV, Lua acknowledgement and owned shutdown.
Uses generated local audio and null output; no YouTube or physical speaker.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import wave

# MPV logs may contain symbols outside the Windows console code page.
sys.stdout.reconfigure(errors='backslashreplace')

if os.name != 'nt':
    raise SystemExit('This test exercises Windows named pipes and requires Windows.')
root = pathlib.Path(__file__).resolve().parents[1]
mpv = shutil.which('mpv')
powershell = shutil.which('powershell')
assert mpv and powershell, 'MPV and Windows PowerShell are required'
base = [powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass']
with tempfile.TemporaryDirectory(prefix='radio single player ') as directory:
    work = pathlib.Path(directory)
    for name in ('Radio.ps1', 'Check-Radio.ps1'):
        shutil.copy2(root / 'payload' / name, work / name)
    config = work / 'portable_config'
    (config / 'scripts').mkdir(parents=True)
    (config / 'script-opts').mkdir()
    shutil.copy2(root / 'payload/portable_config/scripts/random-start.lua', config / 'scripts')
    (config / 'mpv.conf').write_text('ao=null\nvo=null\nvolume=80\n', encoding='utf-8')
    (config / 'script-opts/random-start.conf').write_text(
        'section_mode=yes\nsection_min_minutes=0.04\nsection_max_minutes=0.04\nfade_seconds=1\ncheckpoint_seconds=1\n', encoding='utf-8')
    media = work / 'local test mix.wav'
    with wave.open(str(media), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(8000)
        for _ in range(930):
            wav.writeframesraw(b'\0' * 16000)
    # A separate player must survive radio replacement, timeout and Stop.
    unrelated = subprocess.Popen([mpv, '--no-config', '--load-scripts=no', '--idle=yes', '--ao=null', '--vo=null'], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    launches = []
    handles = []

    def launch(seconds):
        handle = (work / f'launch-{len(launches)}.log').open('w', encoding='utf-8')
        handles.append(handle)
        process = subprocess.Popen(base + ['-File', str(work / 'Radio.ps1'), '-MpvExecutable', mpv,
            '-Playlist', str(media), '-DurationSeconds', str(seconds)], stdout=handle, stderr=subprocess.STDOUT)
        launches.append(process)
        return process

    def check(process):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            assert process.poll() is None, 'Launcher exited before its diagnostic check'
            result = subprocess.run(base + ['-File', str(work / 'Check-Radio.ps1')], capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and 'PASS:' in result.stdout:
                print(result.stdout)
                return
            time.sleep(0.2)
        raise AssertionError('Lua did not acknowledge Check Radio: ' + result.stdout + result.stderr)

    def radio_processes():
        # Match only real MPV processes with our temporary configuration path.
        env = dict(os.environ, RADIO_TEST_FOLDER=str(work))
        result = subprocess.run(base + ['-Command', "@(Get-CimInstance Win32_Process -Filter \"Name = 'mpv.exe'\" | Where-Object { $_.CommandLine.Contains($env:RADIO_TEST_FOLDER) } | Select-Object -ExpandProperty ProcessId) | ConvertTo-Json -Compress"], env=env, capture_output=True, text=True, check=True, timeout=10)
        values = json.loads(result.stdout or '[]')
        return values if isinstance(values, list) else [values]

    try:
        first = launch(60)
        check(first)
        initial = radio_processes()
        assert len(initial) == 1, f'Expected one radio MPV, found {initial}'
        second = launch(60)
        assert first.wait(timeout=20) == 0, 'Previous radio launcher failed to close cleanly'
        check(second)
        replacement = radio_processes()
        assert len(replacement) == 1 and replacement != initial, 'Session replacement must close the old MPV before playing'
        subprocess.run(base + ['-File', str(work / 'Radio.ps1'), '-Stop'], check=True, timeout=20)
        assert second.wait(timeout=10) == 0
        assert radio_processes() == [], 'Stop left a radio player alive'
        assert unrelated.poll() is None, 'Stop closed an unrelated MPV'
        started = time.monotonic()
        timed = launch(10)
        check(timed)
        assert timed.wait(timeout=20) == 0, 'Timed session failed'
        assert time.monotonic() - started < 20, 'Runtime limit was not enforced'
        assert radio_processes() == [], 'Runtime limit left a radio player alive'
        assert unrelated.poll() is None, 'Timed session closed an unrelated MPV'
        tracks = (config / 'recent-track-history.txt').read_text().splitlines()
        assert len(tracks) >= 4, 'Sampling did not move through the looping playlist'
        heard = [x for x in (config / 'heard-sections.txt').read_text().splitlines() if not x.startswith('#')]
        assert len(heard) >= 2, 'Section checkpoints were not retained'
        print('PASS: one MPV, Lua acknowledgement, session replacement, stop, runtime, sampling and saved history; unrelated MPV survived.')
    finally:
        for process in launches:
            if process.poll() is None:
                subprocess.run(base + ['-File', str(work / 'Radio.ps1'), '-Stop'], timeout=20, check=False)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        unrelated.terminate()
        unrelated.wait(timeout=10)
        for handle in handles:
            handle.close()
        for log in work.glob('launch-*.log'):
            print(log.name + '\n' + log.read_text(encoding='utf-8', errors='replace'))
