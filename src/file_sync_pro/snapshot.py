import hashlib
import json
import typing as t
from time import time

from lk_utils import fs as _fs
from .filesys import FtpFileSystem
from .filesys import LocalFileSystem


class T:
    FileSystem = t.Union[FtpFileSystem, LocalFileSystem]
    SnapshotData = t.Dict[str, int]  # {relpath: modified_time, ...}
    SnapshotItem = t.TypedDict('SnapshotItem', {
        'version': str,  # `<hash>-<time>`
        'data'   : SnapshotData,
    })
    SnapshotFull = t.TypedDict('SnapshotFull', {
        'base'   : SnapshotItem,
        'current': SnapshotItem,
    })


class Snapshot:
    fs: T.FileSystem
    snapshot_file: str
    
    def __init__(self, x: t.Union[str, T.FileSystem]) -> None:
        if isinstance(x, str):
            if x.startswith('ftp://'):
                self.fs = FtpFileSystem(x)
            else:
                self.fs = LocalFileSystem(x)
            self.snapshot_file = get_snapshot_file_for_target_root(x)
        else:
            self.fs = x
            self.snapshot_file = get_snapshot_file_for_target_root(
                x.url if isinstance(x, FtpFileSystem) else x.root
            )
        print(self.fs.root, self.snapshot_file, ':pv')
    
    def load_snapshot(self) -> T.SnapshotFull:
        x = self.fs.load(self.snapshot_file)
        if isinstance(self.fs, LocalFileSystem):
            return x
        else:
            return json.loads(x)
    
    def update_snapshot(self, data: T.SnapshotData) -> None:
        full: T.SnapshotFull
        if self.fs.exist(self.snapshot_file):
            full = self.load_snapshot()
            full['current']['version'] = '{}-{}'.format(
                self._hash_snapshot(data), int(time())
            )
            full['current']['data'] = data
            self.fs.dump(full, self.snapshot_file)
        else:
            self.rebuild_snapshot(data)
    
    def partial_update_snapshot(
        self, data: T.SnapshotData, relpath: str
    ) -> None:
        assert self.fs.exist(self.snapshot_file)
        full = self.load_snapshot()
        
        temp = {}
        for k, v in full['current']['data'].items():
            if not k.startswith(relpath):
                temp[k] = v
        temp.update(data)
        
        full['current']['data'] = temp
        full['current']['version'] = '{}-{}'.format(
            self._hash_snapshot(temp), int(time())
        )
        self.fs.dump(full, self.snapshot_file)
    
    def rebuild_snapshot(self, data: T.SnapshotData) -> None:
        full = {
            'base'   : (x := {
                'version': '{}-{}'.format(
                    self._hash_snapshot(data), int(time())
                ),
                'data'   : data,
            }),
            'current': x
        }
        self.fs.dump(full, self.snapshot_file)
    
    @staticmethod
    def _hash_snapshot(data: T.SnapshotData) -> str:
        return hashlib.md5(
            json.dumps(data, sort_keys=True).encode()
            #                ~~~~~~~~~~~~~~ recursively sort.
            #   the order of keys affects hash result. since -
            #   `FtpFileSystem.findall_files` has a random order, we need to -
            #   sort them.
        ).hexdigest()


def get_snapshot_file_for_target_root(root: str) -> str:
    if not root.startswith('ftp://'):
        root = _fs.abspath(root)
    return 'data/snapshots/{}.json'.format(
        hashlib.md5(root.encode()).hexdigest()
    )
