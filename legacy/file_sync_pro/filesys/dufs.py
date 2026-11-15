import os
import requests
import typing as t
from lk_utils import fs
from .air import AirFileSystem
from .base import T


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
