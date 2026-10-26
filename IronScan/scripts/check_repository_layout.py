#!/usr/bin/env python3
"""Validate the two-folder app layout, Xcode references, and relocation hashes (macOS)."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
project = root / 'Apps/IronScan/IronScan.xcodeproj/project.pbxproj'
objects = json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(project)]))['objects']
target = root / 'Apps/IronScan/IronScan'
allowed = {'AppAndUI','CoreAndML'}
assert {p.name for p in target.iterdir() if p.is_dir()} == allowed
app_group = objects['C95B9885ADEEBE1D600981D2']
assert {objects[key].get('path') for key in app_group['children'] if objects[key]['isa']=='PBXGroup'} == allowed
checked = 0
for group in app_group['children']:
    obj = objects[group]
    if obj['isa'] != 'PBXGroup':
        continue
    for key in obj['children']:
        item = objects[key]
        if item.get('sourceTree') == '<group>':
            path = target / obj['path'] / item['path']
        elif item.get('sourceTree') == 'SOURCE_ROOT':
            path = project.parent.parent / item['path']
        else:
            raise AssertionError(f'Unexpected source tree: {key}')
        assert path.exists(), f'Missing Xcode reference: {path.relative_to(root)}'
        checked += 1
if '--verify-relocation-hashes' in sys.argv:
    mapping = json.loads((root.parent/'Documentation/docs/repository-reorganization-map.json').read_text())
    for entry in mapping['files']:
        path = target / entry['to']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256'], f'Changed relocated content: {entry["to"]}'
    print(f'Relocation audit: {len(mapping["files"])} file hashes unchanged.')
assert (root.parent / 'Documentation/docs').is_dir()
assert not any((root.parent / name).exists() for name in ['Apps', 'Models', 'Packages', 'MLTraining', 'docs', 'compliance', 'Video', 'scripts'])
print(f'Layout: IronScan + Documentation at repository root; 2 app source folders; {checked} Xcode references resolve.')
