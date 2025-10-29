"""
about snapshot file:
    -   the file extension is ".json".
    -   the file should be path irrelevant, i.e. you can put it at any position,
        either in local disk, or usb, or mobile sdcard.
"""

import hashlib
import json
import typing as t
from lk_utils import fs as lkfs
from time import time
from ..filesys import AirFileSystem
from ..filesys import FtpFileSystem
from ..filesys import LocalFileSystem


class T:
    FileSystem = t.Union[AirFileSystem, FtpFileSystem, LocalFileSystem]
    
    AbsPath = AnyPath = Path = str
    #   AbsPath: be noted this can be a local path, or remote path.
    #       for examples:
    #           C:/Likianta/documents/gitbook
    #           /storage/emulated/0/Likianta/documents/gitbook
    #       the remote abspath must start with '/'.
    #   AnyPath: abspaths, relpaths, regular slash separators (/), back
    #   slashes (\\), 'air://...' paths, 'ftp://...' paths... they are all
    #   allowed.
    Key = str  # a relpath
    Movement = t.Literal['+>', '=>', '->', '<+', '<=', '<-']
    #   +>  add to right
    #   =>  overwrite to right
    #   ->  delete to right
    #   <+  add to left
    #   <=  overwrite to left
    #   <-  delete to left
    #   ==  no change
    Time = int
    
    ComposedAction = t.Tuple[Key, Movement, Time]
    SnapshotData = t.Dict[Path, int]  # {relpath: modified_time, ...}
    
    SnapshotItem = t.TypedDict('SnapshotItem', {
        'version': str,  # `<hash>-<time>`
        'data'   : SnapshotData,
    })
    
    SnapshotFull = t.TypedDict('SnapshotFull', {
        'root'   : Path,
        'ignores': t.FrozenSet[Path],
        'base'   : SnapshotItem,
        'current': SnapshotItem,
    })


class Snapshot:
    fs: T.FileSystem
    snapshot_file: T.AbsPath
    source_root: T.AbsPath
    _is_snapshot_file_remote: bool
    
    def __init__(self, snapshot_file: T.AnyPath) -> None:
        assert snapshot_file.endswith('.json')
        if snapshot_file.startswith(('air://', 'ftp://')):
            self._is_snapshot_file_remote = True
            prefix = snapshot_file.split('://', 1)[0]
            syscls = {'air': AirFileSystem, 'ftp': FtpFileSystem}[prefix]
            self.fs, self.snapshot_file = syscls.create_from_url(snapshot_file)
            if self.fs.exist(self.snapshot_file):
                self.source_root = self.load_snapshot()['root']
        else:
            self._is_snapshot_file_remote = False
            if lkfs.exist(snapshot_file):
                root = lkfs.load(snapshot_file)['root']
                if root.startswith(('air://', 'ftp://')):
                    prefix = root.split('://', 1)[0]
                    syscls = \
                        {'air': AirFileSystem, 'ftp': FtpFileSystem}[prefix]
                    self.fs, self.source_root = syscls.create_from_url(root)
                else:
                    self.fs, self.source_root = LocalFileSystem(), root
            else:
                self.fs = LocalFileSystem()
            self.snapshot_file = lkfs.abspath(snapshot_file)
        # note: `self.source_root` may be undefined if snap file not exists.
    
    def load_snapshot(self, _absroot: bool = True) -> T.SnapshotFull:
        data: T.SnapshotFull
        if self._is_snapshot_file_remote:
            data = json.loads(self.fs.load(self.snapshot_file))
        else:
            data = lkfs.load(self.snapshot_file)
            if data['root'].startswith(('air://', 'ftp://')):
                data['root'] = '/' + data['root'].split('/', 3)[-1]
        if _absroot:
            if data['root'] in ('.', '..') or data['root'].startswith('../'):
                data['root'] = lkfs.normpath('{}/{}'.format(
                    lkfs.parent(self.snapshot_file), data['root']
                ))
        if x := data.get('ignores'):
            data['ignores'] = frozenset(x)
        return data
    
    def update_snapshot(self, data: T.SnapshotData) -> None:
        full = self.load_snapshot(_absroot=False)
        full['current']['version'] = '{}-{}'.format(
            self._hash_snapshot(data), int(time())
        )
        full['current']['data'] = data
        self.fs.dump(full, self.snapshot_file)
    
    def partial_update_snapshot(
        self, data: T.SnapshotData, relpath: str
    ) -> None:
        full = self.load_snapshot(_absroot=False)
        
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
    
    def rebuild_snapshot(self, data: T.SnapshotData, root: T.AbsPath) -> None:
        """
        root: must be a normalized abspath.
            be careful using `self.fs.root` as root. if your snapshot file is -
            stored in an isolated place, which is not `data:keys` relative to, -
            then using `self.fs.root` would be definitely wrong.
        """
        # check if snapshot file stored inside file-sync-pro project.
        # if so, no need to convert root path from absolute to relative.
        # is_snapshot_inside = (
        #     isinstance(self.fs, LocalFileSystem) and
        #     self.snapshot_file.startswith(lkfs.xpath('../../data/snapshots'))
        # )
        
        if isinstance(self.fs, (AirFileSystem, FtpFileSystem)):
            if not root.startswith(('air://', 'ftp://')):
                assert root.startswith('/')
                root = '{}/{}'.format(self.fs.url, root[1:])
                print(root, ':p')
        
        full = {
            # 'root'   :
            #     # root if root.startswith(('air://', 'ftp://')) else
            #     root if is_snapshot_inside else
            #     (self._prefer_relpath(root) or root),
            'root'   : root,
            'ignores': [],  # you can manually edit this later.
            'base'   : (x := {
                'version': '{}-{}'.format(
                    self._hash_snapshot(data), int(time())
                ),
                'data'   : data,
            }),
            'current': x
        }
        if self._is_snapshot_file_remote:
            self.fs.dump(full, self.snapshot_file)
        else:
            lkfs.dump(full, self.snapshot_file)
    
    @staticmethod
    def _hash_snapshot(data: T.SnapshotData) -> str:
        return hashlib.md5(
            json.dumps(data, sort_keys=True).encode()
            #                ~~~~~~~~~~~~~~ recursively sort.
            #   the order of keys affects hash result. since -
            #   `FtpFileSystem.findall_files` has a random order, we need to -
            #   sort them.
        ).hexdigest()
    
    def _prefer_relpath(self, target: T.AbsPath) -> t.Optional[T.Path]:
        relpath = lkfs.relpath(target, lkfs.parent(self.snapshot_file))
        if relpath.count('../') < 3:
            return relpath
        else:
            print(
                'cannot use relpath for `root` key: '
                'the turning point is too far',
                target, relpath, ':pv5'
            )
            return None
