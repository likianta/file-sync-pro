import airmise as air
import ftplib
import io
import json
import os
import re
import requests
import typing as t
from contextlib import contextmanager
from datetime import datetime
from lk_utils import fs
from uuid import uuid1


class T:
    Path = str
    Time = int


class BaseFileSystem:
    def dump(self, data: t.Any, file: T.Path) -> None:
        raise NotImplementedError
    
    def exist(self, path: T.Path) -> bool:
        raise NotImplementedError
    
    def findall_files(
        self, root: T.Path
    ) -> t.Iterable[t.Tuple[T.Path, T.Time]]:
        raise NotImplementedError
    
    def load(self, file: T.Path) -> t.Any:
        raise NotImplementedError
    
    def make_dirs(self, dirpath: T.Path) -> None:
        raise NotImplementedError
    
    def remove(self, file: T.Path) -> None:
        raise NotImplementedError


class LocalFileSystem(BaseFileSystem):
    def dump(self, data: t.Any, file: T.Path, *, binary: bool = False) -> None:
        fs.dump(data, file, type='binary' if binary else 'auto')
    
    def exist(self, path: T.Path) -> bool:
        return fs.exist(path)
    
    def findall_files(
        self, root: T.Path
    ) -> t.Iterator[t.Tuple[T.Path, T.Time]]:
        for f in fs.findall_files(root):
            yield f.path, fs.filetime(f.path)
    
    def load(self, file: T.Path, *, binary: bool = False) -> t.Any:
        return fs.load(file, type='binary' if binary else 'auto')
    
    def make_dirs(self, dirpath: T.Path) -> None:
        # assert dirpath.startswith(self.root)
        if not fs.exist(dirpath):
            fs.make_dirs(dirpath)
    
    def remove(self, file: T.Path) -> None:
        fs.remove_file(file)


# noinspection PyMethodMayBeStatic
class AirFileSystem(BaseFileSystem):
    """
    # --- android termux ---
    sshd
    # --- pc ---
    ssh 172.20.128.123 -p 8022
    # --- ssh ---
    cd ~/storage/shared/Likianta/work/file-sync-pro
    pip install -r requirements.lock
    #   or: pip install -r http://172.20.128.132:2135/reqlock/airmise.txt
    cd ~/storage/shared
    python -m airmise run-server --port 2160
    """
    
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
        self._fs = air.delegate(LocalFileSystem)
    
    # -------------------------------------------------------------------------
    # overrides
    
    def dump(self, data: t.Any, file: T.Path) -> None:
        self._fs.dump(self._serialize_data(data), file, binary=True)
    
    def exist(self, path: T.Path) -> bool:
        return self._fs.exist(path)
    
    def findall_files(
        self, root: T.Path
    ) -> t.Iterator[t.Tuple[T.Path, T.Time]]:
        yield from self._fs.findall_files(root)
    
    def load(self, file: T.Path, *, binary: bool = False) -> t.Any:
        return self._fs.load(file, binary=binary)
    
    def make_dirs(self, dirpath: T.Path) -> None:
        if not self._fs.exist(dirpath):
            self._fs.make_dirs(dirpath)
    
    def remove(self, file: T.Path) -> None:
        self._fs.remove(file)
    
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


class DufsFileSystem(AirFileSystem):
    """
    in android termux:
        pkg search dufs
        pkg install dufs
        dufs -A -p 2161 ~/storage/shared/Likianta
    """
    
    # noinspection PyMissingConstructor
    def __init__(self, host: str, port: int = 2161) -> None:
        self.url = f'http://{host}:{port}'
    
    def download_file(
        self, file_i: T.Path, file_o: T.Path, mtime: T.Time = None
    ) -> None:
        data = self.load(file_i)
        fs.dump(data, file_o, 'binary')
        if mtime is None:  # TODO
            # print(':v6p', 'please manually pass mtime of {}'.format(file_i))
            return
        os.utime(file_o, (mtime, mtime))
    
    def dump(
        self, data: t.Any, file: T.Path, overwrite: t.Optional[True] = None
    ) -> None:
        requests.put(self._make_url(file), data=self._serialize_data(data))
    
    ...  # TODO
    
    def _make_url(self, path) -> str:
        return '{}/{}'.format(self.url, path.lstrip('/'))


class FtpFileSystem(BaseFileSystem):
    @classmethod
    def create_from_url(cls, url: str) -> t.Tuple['FtpFileSystem', T.Path]:
        a, b, c, d = (url + '/').split('/', 3)
        #   e.g. 'ftp://172.20.128.123:2161/Likianta/test/snapshot.json'
        #       a = 'ftp:'
        #       b = ''
        #       c = '172.20.128.123:2161'
        #       d = 'Likianta/test/snapshot.json'
        assert a == 'ftp:' and b == '' and ':' in c
        e, f = c.split(':')
        return FtpFileSystem(host=e, port=int(f)), '/' + d
    
    def __init__(self, host: str, port: int = 2162) -> None:
        self.url = f'ftp://{host}:{port}'
        self._ftp = ftplib.FTP()
        self._ftp.connect(host, port)
        self._ftp.login()
        self._time_shift = 8 * 3600  # we are living in utc8
        #   TODO: detect current timezone
    
    def download_file(
        self, file_i: T.Path, file_o: T.Path, mtime: T.Time = None
    ) -> None:
        data = self.load(file_i)
        fs.dump(data, file_o, 'binary')
        if mtime is None:  # TODO
            # print(':v6p', 'please manually pass mtime of {}'.format(file_i))
            return
        os.utime(file_o, (mtime, mtime))
    
    def dump(
        self, data: t.Any, file: T.Path, overwrite: t.Optional[True] = None
    ) -> None:
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
        the existing file.
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
    
    def findall_files(
        self, root: T.Path = None
    ) -> t.Iterator[t.Tuple[T.Path, T.Time]]:
        def get_modify_time_of_hidden_file(file: T.Path) -> T.Time:
            with self._temp_rename_file(file) as file_x:
                a, b = fs.split(file_x)
                for name, info in self._ftp.mlsd(a):
                    if name == b:
                        return self._time_str_2_int(
                            info['modify'], shift=self._time_shift
                        )
                else:
                    raise Exception(file)
        
        hidden_files = []
        for file, info in self._findall_files(root):
            if info is None:
                hidden_files.append(file)
            else:
                yield file, self._time_str_2_int(
                    info['modify'], shift=self._time_shift
                )
        for file in hidden_files:
            print(file, ':v6i')
            yield file, get_modify_time_of_hidden_file(file)
    
    def load(self, file: T.Path) -> bytes:
        with io.BytesIO() as f:
            self._ftp.retrbinary(f'RETR {file}', f.write)
            f.seek(0)
            return f.read()
    
    def make_dirs(self, dirpath: T.Path, precheck: bool = True) -> None:
        if not precheck or not self.exist(dirpath):
            self._ftp.mkd(dirpath)
    
    make_dir = make_dirs
    
    def remove(self, file: T.Path) -> None:
        self._ftp.delete(file)
    
    def upload_file(
        self, file_i: T.Path, file_o: T.Path, mtime: T.Time = None
    ) -> None:
        # this method similar to `self.dump`, but keeps origin file's modify -
        # time for target.
        with open(file_i, 'rb') as f:
            self.dump(f.read(), file_o)
        if mtime is None:
            mtime = fs.filetime(file_i)
        self._ftp.sendcmd('MFMT {} {}'.format(
            self._time_int_2_str(mtime, -self._time_shift), file_o
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
    
    def _findall_files(
        self, root: T.Path, _outward_path: T.Path = None
    ) -> t.Iterator[t.Tuple[T.Path, t.Optional[dict]]]:
        """
        yields: ((file, info | None), ...)
            field: absolute path
            info: {'time': str, ...}
                time for example: '20250619064438.504'
                be noticed the time is in utc0 format!
        """
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
                # noinspection PyUnresolvedReferences
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
    
    # @staticmethod
    # def _is_hidden_file(path: T.Path) -> bool:
    #     return path.rsplit('/', 1)[-1][0] == '.'
    #
    # def _is_normal_path(self, path: str) -> bool:
    #     return (
    #         False
    #         if '[' in path or ']' in path or self._is_hidden_file(path) else
    #         True
    #     )
    
    @contextmanager
    def _temp_rename(self, a: T.Path, b: T.Path) -> t.Iterator[T.Path]:
        self._ftp.rename(a, b)
        try:
            yield b
        except Exception as e:
            raise e
        finally:
            self._ftp.rename(b, a)
    
    @contextmanager
    def _temp_rename_dir(
        self, a: T.Path, b: T.Path = None
    ) -> t.Iterator[T.Path]:
        if b is None:
            b = (
                '/Likianta/documents/appdata/file-sync-pro/temp/'
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
                '/Likianta/documents/appdata/file-sync-pro/temp/'
                '_temp_file_{}'.format(uuid1().hex)
            )
        with self._temp_rename(a, b) as x:
            yield x
    
    @staticmethod
    def _time_int_2_str(mtime: T.Time, shift: int) -> str:
        dt = datetime.fromtimestamp(mtime + shift)
        return dt.strftime('%Y%m%d%H%M%S')
    
    @staticmethod
    def _time_str_2_int(mtime: str, shift: int) -> T.Time:
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
        return int(dt.timestamp()) + shift


def send_file_to_remote(file_i: T.Path, file_o: T.Path) -> None:
    fs, file_o = FtpFileSystem.create_from_url(file_o)
    fs.upload_file(file_i, file_o)
