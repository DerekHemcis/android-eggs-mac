#!/usr/bin/env python3
"""Switch the macOS 26 lock-screen (Idle) wallpaper.
Usage: lock-set.py video | sim | default
  video   -> our Landroid aerial video (animated lock screen, works immediately)
  sim     -> our Landroid.saver (live simulation, starts after idle)
  default -> back to the system wallpaper
"""
import plistlib, os, subprocess, sys

STORE = os.path.expanduser('~/Library/Application Support/com.apple.wallpaper/Store/Index.plist')
AID = "395D5CF8-D075-42B0-AC11-604A3E75B02B"
SAVER = 'file://' + os.path.expanduser('~/Library/Screen Savers/Landroid.saver').replace(' ', '%20')

CHOICES = {
    'video':   ('com.apple.wallpaper.choice.aerials', {'assetID': AID}),
    'sim':     ('com.apple.wallpaper.choice.screen-saver', {'module': {'relative': SAVER}}),
    'default': ('com.apple.wallpaper.choice.macintosh', None),
}

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'video'
    provider, config = CHOICES[mode]
    d = plistlib.load(open(STORE, 'rb'))
    for top in ('AllSpacesAndDisplays', 'SystemDefault'):
        node = d.get(top)
        if not isinstance(node, dict):
            continue
        entry = node.get('Idle') or {'LastSet': None, 'LastUse': None,
                                     'Content': {'Choices': [{'Files': []}],
                                                 'EncodedOptionValues': b'', 'Shuffle': '$null'}}
        ch = entry['Content']['Choices'][0]
        ch['Provider'] = provider
        ch['Configuration'] = plistlib.dumps(config) if config else b''
        ch.setdefault('Files', [])
        entry['Content']['Choices'][0] = ch
        node['Idle'] = entry
        node.setdefault('Type', 'individual')
    plistlib.dump(d, open(STORE, 'wb'), fmt=plistlib.FMT_BINARY)
    subprocess.run(['killall', 'WallpaperAgent'], stderr=subprocess.DEVNULL)
    print('锁屏已切换为:', mode)

main()
