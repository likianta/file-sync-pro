import os
from lk_utils import fs
from .snapshot import Snapshot


def fix_mtime(snapshot_file):
    snap = Snapshot(snapshot_file)
    snap_data = snap.load_snapshot()
    root = snap_data['root']
    
    for relpath, mtime0 in snap_data['current']['data'].items():
        abspath = '{}/{}'.format(root, relpath)
        mtime1 = fs.filetime(abspath)
        if mtime1 == mtime0:
            print(':v4', relpath)
        elif mtime1 - mtime0 == 28800:
            print(':v8', relpath)
            os.utime(abspath, (mtime0, mtime0))
        else:
            print(':v6', relpath)
