"""Exercise Radio.ps1 with two real MPV decoders and local tones, on Linux/Windows.
No network or physical sound is used. Requires pwsh/powershell, mpv, and Python.
"""
import json
import math
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import time
import wave

root = Path(__file__).resolve().parents[1]
powershell = shutil.which('pwsh') or shutil.which('powershell')
mpv = shutil.which('mpv')
assert powershell and mpv, 'PowerShell and MPV are required'


def query(endpoint, name):
    if os.name == 'nt':
        stream = open(r'\\.\pipe' + chr(92) + endpoint, 'r+b', buffering=0)
        sock = None
    else:
        sock = socket.socket(socket.AF_UNIX)
        sock.settimeout(2)
        sock.connect(endpoint)
        stream = sock.makefile('rwb', buffering=0)
    try:
        stream.write((json.dumps({'command': ['get_property', name], 'request_id': 99}) + '\n').encode())
        while True:
            result = json.loads(stream.readline())
            if result.get('request_id') == 99:
                assert result['error'] == 'success', result
                return result.get('data')
    finally:
        stream.close()
        if sock:
            sock.close()


with tempfile.TemporaryDirectory(prefix='radio-crossfade-') as directory:
    work = Path(directory)
    config = work / 'portable_config'
    (config / 'scripts').mkdir(parents=True)
    (config / 'script-opts').mkdir()
    shutil.copy(root / 'payload/portable_config/scripts/random-start.lua', config / 'scripts')
    (config / 'mpv.conf').write_text('ao=null\nvo=null\n')
    (config / 'script-opts/random-start.conf').write_text(
        'section_mode=yes\nmin_duration_minutes=0.01\nsection_min_minutes=0.12\n'
        'section_max_minutes=0.12\ncrossfade_seconds=2\ncheckpoint_seconds=1\n')
    tracks = []
    for i, freq in enumerate((220, 440, 660)):
        path = work / f'tone-{i}.wav'
        with wave.open(str(path), 'wb') as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(8000)
            wav.writeframes(b''.join(struct.pack('<h', int(8000 * math.sin(2 * math.pi * freq * j / 8000))) for j in range(15 * 8000)))
        tracks.append(str(path))
    playlist = work / 'test.m3u'
    playlist.write_text('\n'.join(tracks) + '\n')
    log = work / 'controller.log'
    with log.open('w') as output:
        process = subprocess.Popen([powershell, '-NoProfile', '-File', str(root / 'payload/Radio.ps1'),
            '-Playlist', str(playlist), '-MpvFolder', str(work), '-MpvExecutable', mpv,
            '-DurationSeconds', '27'], stdout=output, stderr=subprocess.STDOUT)
    overlap = False
    positions = {}
    started = time.monotonic()
    try:
        while process.poll() is None and time.monotonic() - started < 40:
            session_path = work / 'radio-session.json'
            if session_path.exists():
                try:
                    session = json.loads(session_path.read_text())
                    decks = []
                    for endpoint in session['endpoints']:
                        status = json.loads(query(endpoint, 'user-data/radio-status'))
                        volume = query(endpoint, 'volume')
                        old = positions.get(endpoint, -1)
                        decks.append((status, volume, old))
                        positions[endpoint] = status['position']
                    if all(s['playing'] and not s['paused'] and v > 5 and s['position'] > old for s, v, old in decks):
                        overlap = True
                except (OSError, ValueError, AssertionError):
                    pass  # Player can finish or atomically update between probe requests.
            time.sleep(0.15)
        code = process.wait(timeout=5)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    print(log.read_text())
    assert code == 0, f'controller exit status {code}'
    assert overlap, 'Never observed two advancing, audible-gain streams simultaneously'
    rows = (config / 'recent-track-history.txt').read_text().splitlines()
    assert len(rows) >= 3, 'Did not hear at least three track starts'
    heard = [r.split('|') for r in (config / 'heard-sections.txt').read_text().splitlines() if not r.startswith('#')]
    assert len({r[1] for r in heard}) >= 2, 'Both decks did not persist played sections'
    assert all(0 < float(r[3]) - float(r[2]) < 10 for r in heard), 'Counted unplayed audio'
    assert not (work / 'radio-session.json').exists(), 'Controller did not clean up its live status'
    print('PASS: real two-player overlap, IPC settings, sample transitions, shared histories, duration and cleanup.')
