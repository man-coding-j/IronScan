"""Inspect the actual encoded MP4, including every internal phone-transition frame.
Run with the repository virtualenv (NumPy required):
  ../../.venv/bin/python scripts/verify-output.py
"""
import json
from pathlib import Path
import subprocess
import struct
import numpy as np

root = Path(__file__).resolve().parents[1]
config = json.loads(subprocess.check_output([
    'node', '--input-type=module', '-e',
    "import {config} from './src/config.ts'; console.log(JSON.stringify(config))",
], cwd=root))
video = root / config['output']['video']
binary = next((root / 'node_modules/@remotion').glob('compositor-*/ffmpeg'))
probe = binary.with_name('ffprobe')
metadata = json.loads(subprocess.check_output([
    str(probe), '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(video),
], cwd=binary.parent))
streams = metadata['streams']
assert len(streams) == 1 and streams[0]['codec_type'] == 'video', 'Expected a silent video-only file'
stream = streams[0]
fps = config['video']['fps']
scenes = config['timing']['scenes']
expected_frames = round(sum(scenes.values()) * fps)
assert stream['width'] == config['video']['width'] and stream['height'] == config['video']['height']
assert stream['codec_name'] == 'h264'
assert stream['r_frame_rate'] == f'{fps}/1'
assert int(stream['nb_frames']) == expected_frames
assert abs(float(metadata['format']['duration']) - expected_frames/fps) < 0.001

start = scenes['opening'] + scenes['problem'] + scenes['process']
length = scenes['showcase']
roi = config['verification']['roi']
w, h = roi['width'], roi['height']
minimum = config['verification']['minimumTealPixels']
frame_bytes = w*h*3

def teal_pixels(data, bgr=False):
    pixels = np.frombuffer(data, dtype=np.uint8).reshape(h,w,3).astype(np.int16)
    if bgr:
        pixels = pixels[:,:,::-1]
    red, green, blue = pixels[:,:,0], pixels[:,:,1], pixels[:,:,2]
    return int(np.count_nonzero((green-red > 14) & (green-blue > 3) & (green < 185)))

# Sanity-check that a blank warm-sand image fails the detector.
sand = bytes.fromhex(config['colors']['sand'][1:]) * (w*h)
assert teal_pixels(sand) == 0
command = [str(binary), '-v', 'error', '-ss', str(start), '-i', str(video), '-t', str(length),
           '-vf', f"crop={w}:{h}:{roi['x']}:{roi['y']}", '-an', '-c:v', 'rawvideo',
           '-pix_fmt', 'bgr24', '-f', 'avi', 'pipe:1']
process = subprocess.Popen(command, cwd=binary.parent, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
# The bundled ffmpeg has a rawvideo encoder but no rawvideo muxer.
# Stream uncompressed BGR frames in AVI instead; keep every frame in order.
def read_exact(size):
    data = bytearray()
    while len(data) < size:
        part = process.stdout.read(size-len(data))
        if not part:
            break
        data.extend(part)
    return data

header = read_exact(12)
assert header[:4] == b'RIFF' and header[8:12] == b'AVI ', 'Expected AVI pipe header'
counts = []
while True:
    chunk = read_exact(8)
    if not chunk:
        break
    assert len(chunk) == 8, 'Truncated AVI chunk'
    kind = bytes(chunk[:4])
    size = struct.unpack('<I',chunk[4:])[0]
    if kind == b'LIST':
        list_type = read_exact(4)
        if list_type == b'movi':
            continue
        read_exact(max(0,size-4))
    elif kind in (b'00db',b'00dc'):
        data = read_exact(size)
        assert len(data) == frame_bytes, f'Unexpected BGR frame size: {len(data)}'
        counts.append(teal_pixels(data,bgr=True))
    else:
        read_exact(size)
    if size % 2:
        read_exact(1)
errors = process.stderr.read().decode()
assert process.wait() == 0, errors
assert len(counts) == round(length*fps)
# Exclude the deliberate scene-entry/closing fades, never an internal slide change.
margin = round(config['timing']['transition']*fps)
checked = counts[margin:len(counts)-margin]
blank_frames = [i+margin+round(start*fps) for i,count in enumerate(checked) if count < minimum]
assert not blank_frames, f'Blank phone interior at absolute frames: {blank_frames}'

transitions = []
relative_start = 0
for screen in config['copy']['screens'][:-1]:
    relative_start += screen['duration']
    first = round(relative_start*fps)
    samples = counts[first:first+round(config['timing']['screenshotSlide']*fps)]
    assert len(samples) == round(config['timing']['screenshotSlide']*fps)
    assert min(samples) >= minimum, f'Blank transition at {start+relative_start}s'
    transitions.append({'time_seconds': start+relative_start, 'frames_checked': len(samples),
                        'minimum_teal_ui_pixels': min(samples), 'blank_frames': 0})
subprocess.run([str(binary), '-v', 'error', '-i', str(video), '-c:v', 'libx264',
                '-preset', 'ultrafast', '-f', 'null', '-'], cwd=binary.parent, check=True)
report = {
    'file': config['output']['video'], 'width': stream['width'], 'height': stream['height'],
    'fps': fps, 'frames': expected_frames, 'duration_seconds': expected_frames/fps,
    'codec': stream['codec_name'], 'audio_streams': 0, 'full_decode': 'passed',
    'carousel_frames_decoded': len(counts), 'fully_visible_phone_frames_checked': len(checked),
    'minimum_teal_ui_pixels': min(checked), 'blank_phone_frames': len(blank_frames),
    'detector': 'Deep-teal UI pixel coverage within the phone interior; blank sand negative control passed',
    'excluded': 'Only the deliberate carousel scene-entry and closing fades',
    'roi': roi, 'internal_transitions': transitions,
}
output = root / config['output']['verification']
output.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
