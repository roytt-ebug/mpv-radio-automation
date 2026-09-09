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
powershell = (shutil.which('powershell') if os.name == 'nt' else shutil.which('pwsh'))
mpv = shutil.which('mpv')
assert powershell and mpv, 'PowerShell and MPV are required'


class Probe:
    def __init__(self, endpoint):
        if os.name == 'nt':
            self.stream = open(r'\\.\pipe' + chr(92) + endpoint, 'r+b', buffering=0)
            self.sock = None
        else:
            self.sock = socket.socket(socket.AF_UNIX)
            self.sock.settimeout(2)
            self.sock.connect(endpoint)
            self.stream = self.sock.makefile('rwb', buffering=0)

    def query(self, name):
        self.stream.write((json.dumps({'command': ['get_property', name], 'request_id': 99}) + '\n').encode())
        while True:
            result = json.loads(self.stream.readline())
            if result.get('request_id') == 99:
                assert result['error'] == 'success', result
                return result.get('data')

    def close(self):
        self.stream.close()
        if self.sock:
            self.sock.close()


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
            '-DurationSeconds', '27', '-Verbose'], stdout=output, stderr=subprocess.STDOUT)
    probes = {}
    probe_errors = []
    probe_states = []
    overlap = False
    overlap_samples = 0
    observed_gains = []
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
                        if endpoint not in probes:
                            probes[endpoint] = Probe(endpoint)
                        probe = probes[endpoint]
                        status = json.loads(probe.query('user-data/radio-status'))
                        volume = probe.query('volume')
                        status['position'] = probe.query('time-pos')
                        status['paused'] = probe.query('pause')
                        old = positions.get(endpoint, -1)
                        decks.append((status, volume, old))
                        positions[endpoint] = status['position']
                    if session['fading']:
                        probe_states.append([[s['playing'], s['paused'], round(s['position'], 2), round(old, 2), round(v, 1)] for s, v, old in decks])
                    if all(s['playing'] and not s['paused'] and v > 5 and s['position'] > old for s, v, old in decks):
                        overlap = True
                        overlap_samples += 1
                        observed_gains.append([round(v, 1) for _, v, _ in decks])
                except (OSError, ValueError, AssertionError) as error:
                    if len(probe_errors) < 5:
                        probe_errors.append(repr(error))
                    # A paused idle deck can have no time-pos yet; retry next poll.
            time.sleep(0.15)
        code = process.wait(timeout=5)
    finally:
        for probe in probes.values():
            probe.close()
        if process.poll() is None:
            process.kill()
            process.wait()
    print(log.read_text())
    print('Overlap probes:', overlap_samples, 'gain pairs:', observed_gains[:16])
    print('Probe errors:', probe_errors)
    print('Fade probe states:', probe_states[:16])
    assert code == 0, f'controller exit status {code}'
    assert overlap, 'Never observed two advancing, audible-gain streams simultaneously'
    assert any(5 < a < 95 and 5 < b < 95 for a, b in observed_gains), 'No intermediate fade gains observed'
    rows = (config / 'recent-track-history.txt').read_text().splitlines()
    assert len(rows) >= 3, 'Did not hear at least three track starts'
    heard = [r.split('|') for r in (config / 'heard-sections.txt').read_text().splitlines() if not r.startswith('#')]
    assert len({r[1] for r in heard}) >= 2, 'Both decks did not persist played sections'
    assert all(0 < float(r[3]) - float(r[2]) < 10 for r in heard), 'Counted unplayed audio'
    assert not (work / 'radio-session.json').exists(), 'Controller did not clean up its live status'
    print('PASS: real two-player overlap, IPC settings, sample transitions, shared histories, duration and cleanup.')
