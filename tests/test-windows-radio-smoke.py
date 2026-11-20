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
base = [powershell, '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass']
with tempfile.TemporaryDirectory(prefix='radio single player ') as directory:
    work = pathlib.Path(directory)
    for name in ('Radio.ps1', 'Check-Radio.ps1'):
        shutil.copy2(root / 'payload' / name, work / name)
    starter = work / 'Radio-Hidden.exe'
    subprocess.run(base + ['-File', str(root / 'payload/Build-HiddenStarter.ps1'),
        '-OutputPath', str(starter)], check=True, timeout=30)
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

    def launch(seconds, manual=False, video=False):
        handle = (work / f'launch-{len(launches)}.log').open('w', encoding='utf-8')
        handles.append(handle)
        arguments = [str(starter), '-MpvExecutable', mpv, '-Playlist', str(media)]
        if seconds is not None:
            arguments += ['-DurationSeconds', str(seconds)]
        if manual:
            arguments += ['-Manual']
        if video:
            arguments += ['-Video']
        process = subprocess.Popen(arguments, stdout=handle, stderr=subprocess.STDOUT)
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

    def radio_command(command):
        env = dict(os.environ, RADIO_TEST_FOLDER=str(work), RADIO_TEST_COMMAND=json.dumps(command))
        script = ". (Join-Path $env:RADIO_TEST_FOLDER 'Radio.ps1') -FunctionsOnly; $endpoint = 'mpv-radio-' + (Get-RadioKey $env:RADIO_TEST_FOLDER); try { $value = Invoke-RadioCommand $endpoint ($env:RADIO_TEST_COMMAND | ConvertFrom-Json); @{ok=$true; data=$value} | ConvertTo-Json -Depth 8 -Compress } catch { @{ok=$false; error=$_.Exception.Message} | ConvertTo-Json -Compress }"
        result = subprocess.run(base + ['-Command', script], env=env, capture_output=True, text=True, check=True, timeout=10)
        return json.loads(result.stdout)

    def check_manual(process, video=False):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            assert process.poll() is None, 'Manual supervisor exited before playback'
            position = radio_command(['get_property', 'time-pos'])
            if position['ok'] and isinstance(position['data'], (int, float)) and position['data'] >= 1.5:
                break
            time.sleep(0.2)
        else:
            raise AssertionError('Manual MPV did not start playing: ' + repr(position))
        assert len(radio_processes()) == 1, 'Manual playback must have exactly one owned MPV'
        assert not radio_command(['get_property', 'user-data/radio-status'])['ok'], 'Manual playback loaded the radio/history script'
        mode = radio_command(['get_property', 'options/vid'])
        assert mode['ok'] and mode['data'] == ('auto' if video else 'no'), 'Manual audio/video mode changed'

    def history_snapshot():
        return {name: (config / name).read_bytes() if (config / name).exists() else None
                for name in ('recent-track-history.txt', 'random-start-history.txt', 'heard-sections.txt')}

    try:
        first = launch(60)
        check(first)
        initial = radio_processes()
        assert len(initial) == 1, f'Expected one radio MPV, found {initial}'
        # The scheduled player must not open or keep a separate terminal alive.
        env = dict(os.environ, RADIO_TEST_FOLDER=str(work))
        probe = ". (Join-Path $env:RADIO_TEST_FOLDER 'Radio.ps1') -FunctionsOnly; $endpoint = 'mpv-radio-' + (Get-RadioKey $env:RADIO_TEST_FOLDER); if ((Invoke-RadioCommand $endpoint @('get_property','options/terminal')) -ne $false) { throw 'MPV terminal must be disabled' }"
        subprocess.run(base + ['-Command', probe], env=env, check=True, timeout=10)
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

        # Manual shortcuts share ownership without sampling, shuffling, or writing
        # radio history. A manual player must not become an untracked extra window.
        before_manual = history_snapshot()
        manual_first = launch(None, manual=True)
        check_manual(manual_first)
        first_manual_ids = radio_processes()
        manual_second = launch(None, manual=True, video=True)
        assert manual_first.wait(timeout=20) == 0, 'Manual/manual replacement did not close the first supervisor'
        check_manual(manual_second, video=True)
        assert radio_processes() != first_manual_ids, 'Manual/manual replacement kept the old player'
        assert history_snapshot() == before_manual, 'Manual playback changed radio histories'
        scheduled_again = launch(60)
        assert manual_second.wait(timeout=20) == 0, 'Scheduled playback did not replace the manual player'
        check(scheduled_again)
        assert len(radio_processes()) == 1, 'Manual/scheduled transition created overlapping players'

        manual_stop = launch(None, manual=True)
        assert scheduled_again.wait(timeout=20) == 0, 'Manual playback did not replace the scheduled player'
        check_manual(manual_stop)
        subprocess.run(base + ['-File', str(work / 'Radio.ps1'), '-Stop'], check=True, timeout=20)
        assert manual_stop.wait(timeout=10) == 0
        assert radio_processes() == [], 'Stop left a manual player alive'
        assert unrelated.poll() is None, 'Manual replacement or stop closed an unrelated MPV'

        before_manual = history_snapshot()
        started = time.monotonic()
        manual_timed = launch(10, manual=True)
        check_manual(manual_timed)
        assert manual_timed.wait(timeout=20) == 0, 'Explicit manual duration was not honored'
        assert time.monotonic() - started < 20, 'Manual runtime limit was not enforced'
        assert radio_processes() == [], 'Manual runtime limit left a player alive'
        assert history_snapshot() == before_manual, 'Timed manual playback changed radio histories'
        assert unrelated.poll() is None, 'Manual duration closed an unrelated MPV'
        print('PASS: hidden starter; one owned MPV across scheduled/manual audio/video transitions; diagnostics, stop, durations, sampling and saved history; manual histories unchanged; unrelated MPV survived.')
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
        error_log = work / 'Radio-Hidden-error.log'
        if error_log.exists():
            print(error_log.name + '\n' + error_log.read_text(encoding='utf-8', errors='replace'))
