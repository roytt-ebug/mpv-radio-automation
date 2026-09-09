"""Real headless mpv with generated local WAV. No YouTube or physical audio output.
Run on Linux after installing mpv: python3 tests/test-mpv-sections-smoke.py
"""
import pathlib
import shutil
import subprocess
import tempfile
import wave

root = pathlib.Path(__file__).resolve().parents[1]
mpv = shutil.which('mpv')
if not mpv:
    raise SystemExit('mpv is required for this smoke test')
with tempfile.TemporaryDirectory(prefix='mpv-radio-smoke-') as directory:
    work = pathlib.Path(directory)
    media = work / 'generated-long-mix.wav'
    with wave.open(str(media), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(8000)
        for _ in range(1300):
            wav.writeframesraw(b'\0' * 16000)
    controller = work / 'smoke-controller.lua'
    controller.write_text('''local loads=0
mp.register_event("file-loaded", function()
    loads=loads+1
    if loads>=3 then mp.add_timeout(0.2, function()
        if math.abs(mp.get_property_number("volume",100)-100)>0.1 then
            mp.msg.error("SMOKE FAILED: gain not restored"); mp.commandv("quit","2")
        else mp.msg.info("SMOKE PASS: three loads, restored gain"); mp.commandv("quit","0") end
    end) end
end)
mp.add_timeout(22, function() mp.msg.error("SMOKE FAILED: timed out"); mp.commandv("quit","3") end)
''', encoding='utf-8')
    command = [mpv, '--config-dir=' + str(work), '--terminal=yes', '--ao=null', '--vo=null', '--vid=no',
        '--volume=100', '--loop-playlist=inf', '--shuffle',
        '--script=' + str(root / 'payload/portable_config/scripts/random-start.lua'),
        '--script=' + str(controller),
        '--script-opts=random-start-section_mode=yes,random-start-section_min_minutes=0.04,random-start-section_max_minutes=0.04,random-start-fade_seconds=1,random-start-checkpoint_seconds=1',
        str(media)]
    result = subprocess.run(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=30)
    print(result.stdout)
    assert result.returncode == 0, 'MPV smoke test did not exit successfully'
    assert 'SMOKE PASS' in result.stdout, 'MPV did not progress through three loads'
    # Windows paths are literal filenames on Linux; production paths remain unchanged.
    section_file = work / 'heard-sections.txt'
    records = [line for line in section_file.read_text().splitlines() if not line.startswith('#')]
    assert len(records) >= 2, 'Estimated playback from both completed samples was not saved'
    for line in records:
        columns = line.split('|')
        a, b = float(columns[2]), float(columns[3])
        assert 0 < b - a < 6, 'Seeked/unplayed content was incorrectly logged'
    print('PASS: real MPV headless sample transitions, looping, restored volume and interval checkpoints.')
