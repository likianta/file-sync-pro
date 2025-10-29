import airmise as air
import json
import os
import typing as t
from lk_utils import fs
from .base import BaseFileSystem
from .base import T
from .local import LocalFileSystem


# noinspection PyMethodMayBeStatic
class AirFileSystem(BaseFileSystem):
    """
    # --- android termux ---
    sshd
    # --- pc ---
    dufs . -p <pc_dufs_port>
    ssh <android_host> -p 8022
    # --- ssh ---
    python -m pip install -r <pc_dufs_host>:<pc_dufs_port>/requirements.txt
    python -m file_sync_pro run-air-server
    # --- pc ---
    strun 2163 src/file_sync_pro/ui.py
    """
    _fs: LocalFileSystem
    
    @classmethod
    def create_from_url(cls, url: str) -> t.Tuple['AirFileSystem', T.Path]:
        a, b, c, d = url.split('/', 3)
        #   e.g. 'air://172.20.128.123:2160/storage/emulated/0/Likianta/test
        #   /snapshot.json'
        #       a = 'air:'
        #       b = ''
        #       c = '172.20.128.123:2160'
        #       d = 'storage/emulated/0/Likianta/test/snapshot.json'
        assert a == 'air:' and b == '' and ':' in c
        assert d == '' or d.startswith('storage/emulated/0/Likianta')
        e, f = c.split(':')
        return AirFileSystem(host=e, port=int(f)), '/' + d
    
    def __init__(self, host: str, port: int = 2160) -> None:
        air.config(host, port, verbose=True)
        air.connect()
        self.url = f'air://{host}:{port}'
        self._fs = t.cast(LocalFileSystem, air.delegate(LocalFileSystem))
    
    # -------------------------------------------------------------------------
    # overrides
    
    def dump(self, data: t.Any, file: T.Path) -> None:
        self._fs.dump(self._serialize_data(data), file, binary=True)
    
    def exist(self, path: T.Path) -> bool:
        return self._fs.exist(path)
    
    def findall_files(
        self, root: T.Path, history: T.Tree = None, ignores: T.Ignores = None
    ) -> t.Iterator[t.Tuple[T.Path, T.Time]]:
        yield from self._fs.findall_files(root, history, ignores)
    
    def load(self, file: T.Path, *, binary: bool = False) -> t.Any:
        return self._fs.load(file, binary=binary)
    
    def make_dir(self, dirpath: T.Path) -> None:
        self._fs.make_dir(dirpath)
    
    def make_dirs(self, dirpath: T.Path) -> None:
        if not self._fs.exist(dirpath):
            self._fs.make_dirs(dirpath)
    
    def modify_mtime(self, path: T.Path, mtime: int) -> None:
        self._fs.modify_mtime(path, mtime)
    
    def remove_dir(self, dir: T.Path) -> None:
        self._fs.remove_dir(dir)
    
    def remove_file(self, file: T.Path) -> None:
        self._fs.remove_file(file)
    
    # -------------------------------------------------------------------------
    
    def download_file(
        self, file_i: T.Path, file_o: T.Path, mtime: T.Time = None
    ) -> None:
        data = self._fs.load(file_i, binary=True)
        fs.dump(data, file_o, 'binary')
        
        # assert file_i.startswith('/storage/emulated/0/Likianta/')
        # url = 'http://{}:{}/{}'.format(
        #     re.search(r'air://([.\d]+):', self.url).group(1),
        #     2161,
        #     file_i.replace('/storage/emulated/0/Likianta/', '', 1)
        # )
        # data = requests.get(url).content
        # fs.dump(data, file_o, 'binary')
        
        if mtime is None:
            mtime = air.exec('fs.filetime(file)', file=file_i)
        os.utime(file_o, (mtime, mtime))
    
    def upload_file(
        self, file_i: T.Path, file_o: T.Path, mtime: T.Time = None
    ) -> None:
        data = fs.load(file_i, 'binary')
        self._fs.dump(data, file_o, binary=True)
        
        # assert file_o.startswith('/storage/emulated/0/Likianta/')
        # url = 'http://{}:{}/{}'.format(
        #     re.search(r'air://([.\d]+):', self.url).group(1),
        #     2161,
        #     file_o.replace('/storage/emulated/0/Likianta/', '', 1)
        # )
        # requests.put(url, fs.load(file_i, 'binary'))
        
        air.exec(
            '''
            import os
            os.utime(file, (mtime, mtime))
            ''',
            file=file_o,
            mtime=mtime or fs.filetime(file_i),
        )
    
    def _serialize_data(self, data: t.Any) -> bytes:
        if isinstance(data, bytes):
            return data
        elif isinstance(data, dict):
            text = json.dumps(data, indent=2, ensure_ascii=False)
            return text.encode('utf-8')
        else:
            raise NotImplementedError
