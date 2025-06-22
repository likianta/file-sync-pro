import ftplib
import hashlib
import io
import json
import os
import re
import typing as t
from contextlib import contextmanager
from datetime import datetime
from lk_utils import fs
from time import time
from uuid import uuid1


class T:
    Path = str
    Time = int
    SnapshotData = t.Dict[Path, Time]  # {relpath: modified_time, ...}
    SnapshotItem = t.TypedDict('SnapshotItem', {
        'version': str,  # `<hash>-<time>`
        'data'   : SnapshotData,
    })
    SnapshotFull = t.TypedDict('SnapshotFull', {
        'base'   : SnapshotItem,
        'current': SnapshotItem,
    })


class BaseFileSystem:
    def __init__(self, root: T.Path) -> None:
        self.root = root
        self.snapshot_file = f'{root}/snapshot.json'
    
    def load_snapshot(self) -> T.SnapshotFull:
        return self.load(self.snapshot_file)
    
    def update_snapshot(self, data: T.SnapshotData) -> None:
        full: T.SnapshotFull
        if self.exist(self.snapshot_file):
            full = self.load_snapshot()
            full['current']['version'] = '{}-{}'.format(
                self._hash_snapshot(data), int(time())
            )
            full['current']['data'] = data
            self.dump(full, self.snapshot_file)
        else:
            self.rebuild_snapshot(data)
        
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
        self.dump(full, self.snapshot_file)
    
    # -------------------------------------------------------------------------
    
    def dump(self, data: t.Any, file: T.Path) -> None:
        raise NotImplementedError
    
    def exist(self, path: T.Path) -> bool:
        raise NotImplementedError
    
    def findall_files(self) -> t.Iterable[t.Tuple[T.Path, int]]:
        raise NotImplementedError
    
    def load(self, file: T.Path) -> t.Any:
        raise NotImplementedError
    
    def make_dirs(self, dirpath: T.Path) -> None:
        raise NotImplementedError
    
    def remove(self, file: T.Path) -> None:
        raise NotImplementedError
    
    @staticmethod
    def _hash_snapshot(data: T.SnapshotData) -> str:
        return hashlib.md5(
            json.dumps(data, sort_keys=True).encode()
            #                ~~~~~~~~~~~~~~ recursively sort.
            #   the order of keys affects hash result. since -
            #   `FtpFileSystem.findall_files` has a random order, we need to -
            #   sort them.
        ).hexdigest()


class LocalFileSystem(BaseFileSystem):
    def __init__(self, root: T.Path) -> None:
        super().__init__(fs.abspath(root))
    
    def dump(self, data: t.Any, file: T.Path, binary: bool = False) -> None:
        fs.dump(data, file, type='binary' if binary else 'auto')
        
    def exist(self, path: T.Path) -> bool:
        return fs.exist(path)
    
    def findall_files(self) -> t.Iterator[t.Tuple[T.Path, int]]:
        for f in fs.findall_files(self.root):
            yield f.path, fs.filetime(f.path)
    
    def load(self, file: T.Path, binary: bool = False) -> t.Any:
        return fs.load(file, type='binary' if binary else 'auto')
    
    def make_dirs(self, dirpath: T.Path) -> None:
        assert dirpath.startswith(self.root)
        if not fs.exist(dirpath):
            fs.make_dirs(dirpath)
    
    def remove(self, file: T.Path) -> None:
        fs.remove_file(file)


class FtpFileSystem(BaseFileSystem):
    def __init__(self, url: str) -> None:
        # e.g. url = 'ftp://192.168.8.31:2024/Likianta/documents'
        #   ->  host = '192.168.8.31'
        #       port = 2024
        #       path = '/Likianta/documents'
        a, b, c, d = url.split('/', 3)
        assert a == 'ftp:' and b == '' and d.startswith('Likianta/')
        e, f = c.rsplit(':', 1)
        host, port, root = e, int(f), f'/{d}'
        assert '[' not in root and ']' not in root, (
            'ftp cannot list files if square bracket characters in the root '
            'path', root
        )
        
        super().__init__(root)
        
        self._ftp = ftplib.FTP()
        self._ftp.connect(host, port)
        self._ftp.login()
        self._ftp.cwd(root)
    
    def load_snapshot(self) -> T.SnapshotFull:
        data_bytes = self.load(self.snapshot_file)
        return json.loads(data_bytes)
    
    def download_file(
        self, file_i: T.Path, file_o: T.Path, mtime: int = None
    ) -> None:
        data = self.load(file_i)
        fs.dump(data, file_o, 'binary')
        if mtime is None:  # TODO
            print(':v6', 'please manually pass mtime of {}'.format(file_i))
            return
        os.utime(file_o, (mtime, mtime))
    
    def dump(
        self, data: t.Any, file: T.Path, overwrite: t.Optional[True] = None
    ) -> None:
        # file = self._normpath(file)
        
        if isinstance(data, bytes):
            data_bytes = data
        elif isinstance(data, dict):
            text = json.dumps(data, indent=2, ensure_ascii=False)
            data_bytes = text.encode('utf-8')
        else:
            raise NotImplementedError
        
        """
        note: `ftplib.storbinary` doesn't truncate file (i.e. empty the file) -
        if target already exists. this means if an existing file "foo.txt" -
        contained "abcde", and we want to write "123" to it, it finally -
        becomes "123de". to resolve this problem, we need to check-and-delete -
        the exiting file.
        """
        
        if overwrite or self.exist(file):
            self._ftp.delete(file)
        with io.BytesIO(data_bytes) as f:
            self._ftp.storbinary(f'STOR {file}', f)
            #   note: we don't need to quote `file` even it has whitespaces.
            #   i.e. 'STOR 01 02.txt' is legal.
            #   besides, 'STOR "01 02.txt"' will report an error.
    
    def exist(self, path: T.Path) -> bool:
        # path = self._normpath(path)
        a, b = path.rsplit('/', 1)
        if b[0] == '.':
            for n, _ in self._find_hidden_names(a):
                if n == b:
                    return True
        else:
            for name in self._ftp.nlst(a):
                if name == b:
                    return True
        return False
    
    def findall_files(self) -> t.Iterator[t.Tuple[T.Path, int]]:
        def get_modify_time_of_hidden_file(file: T.Path) -> int:
            with self._temp_rename_file(file) as file_x:
                a, b = fs.split(file_x)
                for name, info in self._ftp.mlsd(a):
                    if name == b:
                        return self._time_str_2_int(info['modify'])
                else:
                    raise Exception(file)
        
        hidden_files = []
        for file, info in self._findall_files(self.root):
            if info is None:
                hidden_files.append(file)
            else:
                yield file, self._time_str_2_int(info['modify'])
        for file in hidden_files:
            print(file, ':v6i')
            yield file, get_modify_time_of_hidden_file(file)
    
    def load(self, file: T.Path) -> bytes:
        with io.BytesIO() as f:
            self._ftp.retrbinary(f'RETR {file}', f.write)
            f.seek(0)
            return f.read()
    
    def make_dirs(self, dirpath: T.Path, precheck: bool = True) -> None:
        assert dirpath.startswith(self.root)
        if not precheck or not self.exist(dirpath):
            self._ftp.mkd(dirpath)
    
    make_dir = make_dirs
    
    def remove(self, file: T.Path) -> None:
        self._ftp.delete(file)
    
    def upload_file(
        self, file_i: T.Path, file_o: T.Path, mtime: int = None
    ) -> None:
        # this method similar to `self.dump`, but keeps origin file's modify -
        # time for target.
        with open(file_i, 'rb') as f:
            self.dump(f.read(), file_o)
        self._ftp.sendcmd('MFMT {} {}'.format(
            self._time_int_2_str(mtime or fs.filetime(file_i)), file_o
        ))
    
    # noinspection PyTypeChecker
    def _find_hidden_names(self, dir: T.Path) -> t.Iterator[
        t.Tuple[str, t.Literal['dir', 'file']]
    ]:
        ls: t.List[str] = []
        self._ftp.retrlines('LIST -a {}'.format(dir), ls.append)
        pattern = re.compile(
            r'([-d])rwx?-+ +'
            r'0 user group +'
            r'\d+ '  # size
            r'\w+ +\d+ +(?:\d\d:\d\d|\d{4}) '  # time
            r'(.+)'  # name
        )
        for line in ls:
            assert (m := pattern.match(line)), line
            a, b = m.groups()
            if b[0] == '.':
                yield b, 'dir' if a == 'd' else 'file'
            else:
                break
    
    def _findall_files(
        self, root: T.Path, _outward_path: T.Path = None
    ) -> t.Iterator[t.Tuple[T.Path, t.Optional[dict]]]:
        assert root.startswith('/') and '[' not in root and ']' not in root
        
        files = []
        subdirs = []
        
        for name, info in self._ftp.mlsd(root):
            if info['type'] == 'file':
                files.append((name, info))
            elif info['type'] == 'dir':
                subdirs.append(name)
            else:
                raise Exception((_outward_path, root), name, info)
            
        for name, type in self._find_hidden_names(root):
            if type == 'file':
                files.append((name, None))
            else:
                subdirs.append(name)
        
        for name, info in sorted(files, key=lambda x: x[0]):
            yield f'{_outward_path or root}/{name}', info
        
        for name in sorted(subdirs):
            if '[' in name or ']' in name:
                with self._temp_rename_dir(f'{root}/{name}') as temp_dir:
                    yield from self._findall_files(
                        root=temp_dir,
                        _outward_path=f'{_outward_path or root}/{name}'
                    )
            else:
                yield from self._findall_files(
                    root=f'{root}/{name}',
                    _outward_path=f'{_outward_path or root}/{name}'
                )
    
    # def _normpath(self, path: T.Path) -> T.Path:
    #     if path == '.':
    #         return self.root
    #     elif path.startswith(('./', '../')):
    #         return fs.normpath('{}/{}'.format(self.root, path))
    #     else:
    #         return path
    
    @contextmanager
    def _temp_rename(self, a: T.Path, b: T.Path) -> t.Iterator[T.Path]:
        self._ftp.rename(a, b)
        try:
            yield b
        except Exception as e:
            raise e
        finally:
            self._ftp.rename(b, a)
    
    # _temp_rename_dir = partial(
    #     _temp_rename, b='/Likianta/test/_local_file_sync/_temp_dir'
    # )
    # _temp_rename_file = partial(
    #     _temp_rename, b='/Likianta/test/_local_file_sync/_temp_file'
    # )
    
    @contextmanager
    def _temp_rename_dir(
        self, a: T.Path, b: T.Path = None
    ) -> t.Iterator[T.Path]:
        if b is None:
            b = (
                '/Likianta/test/_local_file_sync/'
                '._temp_dir_{}'.format(uuid1().hex)
            )
        with self._temp_rename(a, b) as x:
            yield x
    
    @contextmanager
    def _temp_rename_file(
        self, a: T.Path, b: T.Path = None
    ) -> t.Iterator[T.Path]:
        if b is None:
            b = (
                '/Likianta/test/_local_file_sync/'
                '_temp_file_{}'.format(uuid1().hex)
            )
        with self._temp_rename(a, b) as x:
            yield x
    
    @staticmethod
    def _time_int_2_str(mtime: int) -> str:
        dt = datetime.fromtimestamp(mtime)
        return dt.strftime('%Y%m%d%H%M%S')
    
    @staticmethod
    def _time_str_2_int(mtime: str) -> int:
        """
        mtime: e.g. '20250619064438.504'
        """
        dt = datetime(
            *map(int, (
                mtime[0:4],
                mtime[4:6],
                mtime[6:8],
                mtime[8:10],
                mtime[10:12],
                mtime[12:14],
            ))
        )
        return int(dt.timestamp())
