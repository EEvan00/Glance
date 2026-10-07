#!/usr/bin/env python3
"""Write a Finder drag-to-install layout without driving Finder or AppleScript."""
import pathlib
import sys
from ds_store import DSStore
from mac_alias import Alias, Bookmark
volume = pathlib.Path(sys.argv[1]).resolve()
app_name = sys.argv[2]
background = Alias.for_file(str(volume / '.background' / 'install.png')).to_bytes()
with DSStore.open(str(volume / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['bwsp'] = {
        'ShowStatusBar': False, 'ShowToolbar': False, 'ShowSidebar': False,
        'ShowPathbar': False, 'ShowTabView': False,
        'WindowBounds': '{{180, 160}, {640, 400}}', 'SidebarWidth': 0,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundColorRed': 1.0, 'backgroundColorGreen': 1.0, 'backgroundColorBlue': 1.0,
        'backgroundImageAlias': background, 'iconSize': 96.0,
        'gridSpacing': 100.0, 'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0, 'textSize': 14.0, 'labelOnBottom': True, 'arrangeBy': 'none',
        'showIconPreview': True, 'showItemInfo': False,
    }
    store['.']['pBBk'] = Bookmark.for_file(str(volume / '.background' / 'install.png'))
    store['.']['icvl'] = ('type', b'icnv')
    store[f'{app_name}.app']['Iloc'] = (170, 170)
    store['Applications']['Iloc'] = (470, 170)
with DSStore.open(str(volume / '.DS_Store'), 'r') as store:
    assert store[f'{app_name}.app']['Iloc'] == (170, 170)
    assert store['Applications']['Iloc'] == (470, 170)
