#!/usr/bin/env python3
"""Publish a video as the macOS 26 lock-screen (Idle) aerial wallpaper.

Creates a fresh asset ID each run (busts every cache), registers it in the
aerial manifest (entries.json and manifest.tar), installs the .mov, points the
Idle scope at it and restarts WallpaperAgent.

Usage: apply-lock.py [path/to/video.mov]
"""
import json, os, plistlib, subprocess, sys, tarfile, shutil, tempfile, uuid

HOME = os.path.expanduser('~')
AER = os.path.join(HOME, 'Library/Application Support/com.apple.wallpaper/aerials')
MANIFEST = os.path.join(AER, 'manifest/entries.json')
TAR = os.path.join(AER, 'manifest.tar')
VIDEOS = os.path.join(AER, 'videos')
STORE = os.path.join(HOME, 'Library/Application Support/com.apple.wallpaper/Store/Index.plist')
SHOT_ID = 'LANDROID_01'


def add_asset(mov_path: str) -> str:
    os.makedirs(VIDEOS, exist_ok=True)
    with open(MANIFEST) as f:
        d = json.load(f)
    # drop any previous Landroid entries so only one is listed
    d['assets'] = [a for a in d['assets'] if a.get('shotID') != SHOT_ID]
    tpl = next((a for a in d['assets'] if a.get('id') == '4DFE24ED-71CC-42D4-9FE8-3B8959B6CC19'), None)
    if tpl is None:
        tpl = d['assets'][0]
    aid = str(uuid.uuid4()).upper()
    entry = json.loads(json.dumps(tpl))
    entry.update({
        'id': aid,
        'accessibilityLabel': 'Landroid',
        'shotID': SHOT_ID,
        'preferredOrder': -1,
        'includeInShuffle': False,
        'showInTopLevel': True,
        'pointsOfInterest': {},
        'variant': {'appearance': 'dark', 'orientation': 'landscape'},
        'videoGravity': 'resize',
        'localizedNameKey': tpl.get('localizedNameKey', 'DYNAMIC_LIGHT_KEY'),
    })
    entry['url-4K-SDR-240FPS'] = 'file://' + os.path.join(VIDEOS, aid + '.mov')
    entry['previewImage'] = 'file://' + os.path.join(VIDEOS, aid + '.mov')
    d['assets'].insert(0, entry)
    with open(MANIFEST, 'w') as f:
        json.dump(d, f, indent=1)

    # keep manifest.tar in sync so a re-extraction does not lose the asset
    if os.path.exists(TAR):
        tmp = tempfile.mkdtemp()
        with tarfile.open(TAR) as t:
            t.extractall(tmp)
        with open(os.path.join(tmp, 'entries.json'), 'w') as f:
            json.dump(d, f, indent=1)
        with tarfile.open(TAR, 'w') as t:
            for name in os.listdir(tmp):
                t.add(os.path.join(tmp, name), arcname=name)
        shutil.rmtree(tmp)

    shutil.copyfile(mov_path, os.path.join(VIDEOS, aid + '.mov'))
    return aid


def set_idle(aid: str):
    with open(STORE, 'rb') as f:
        d = plistlib.load(f)
    for top in ('AllSpacesAndDisplays', 'SystemDefault'):
        node = d.get(top)
        if not isinstance(node, dict):
            continue
        entry = node.get('Idle') or {'LastSet': None, 'LastUse': None,
                                     'Content': {'Choices': [{'Files': []}],
                                                 'EncodedOptionValues': b'', 'Shuffle': '$null'}}
        ch = entry['Content']['Choices'][0]
        ch['Provider'] = 'com.apple.wallpaper.choice.aerials'
        ch['Configuration'] = plistlib.dumps({'assetID': aid})
        ch.setdefault('Files', [])
        entry['Content']['Choices'][0] = ch
        node['Idle'] = entry
        node.setdefault('Type', 'individual')
    with open(STORE, 'wb') as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)


def main():
    mov = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'Landroid 锁屏.mov')
    aid = add_asset(mov)
    set_idle(aid)
    subprocess.run(['killall', 'WallpaperAerialsExtension'], stderr=subprocess.DEVNULL)
    subprocess.run(['killall', 'WallpaperAgent'], stderr=subprocess.DEVNULL)
    print('已发布资产并设为锁屏:', aid)
    print('提示：锁屏后若仍是旧画面，锁一次再解锁即可刷新。')


main()
