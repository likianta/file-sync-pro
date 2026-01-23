import airmise as air
import os
import typing as t
from collections import namedtuple
from functools import partial


def is_local_path(path):
    return not is_remote_path(path)


def is_remote_path(path: str):
    if path.startswith('air://'):
        return True
    elif path.startswith('/'):
        if os.name == 'nt':
            return True
        else:
            raise Exception
    else:
        return False


def create_fs_from_url(url: str) -> t.Tuple['FileSystem', str]:
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
    client = air.Client(host=e, port=int(f))
    client.open()
    return FileSystem(client), '/' + d
    
    
class FileSystem:
    # _client = None
    #
    # @property
    # def available(self) -> bool:
    #     return self._client is not None
    
    # noinspection PyAttributeOutsideInit
    def __init__(self, client: air.Client):
        self.client = client
        self.dump = partial(self._fast_call, 'dump')
        self.exist = partial(self._fast_call, 'exist')
        self.load = partial(self._fast_call, 'load')
        self.make_dir = partial(self._fast_call, 'make_dir')
        self.make_dirs = partial(self._fast_call, 'make_dirs')
        self.relpath = partial(self._fast_call, 'relpath')
        self.remove_file = partial(self._fast_call, 'remove_file')
        self.remove_tree = partial(self._fast_call, 'remove_tree')
    
    @property
    def url(self):
        return 'air://{}:{}'.format(self.client.host, self.client.port)
    
    def find_files(self, root):
        Path = namedtuple('Path', 'path relpath mtime')
        for tuple_ in self.client.exec(
            '''
            def foo():
                for f in fs.find_files(root):
                    yield f.path, f.relpath, f.mtime
            return foo()
            ''',
            root=root
        ):
            yield Path(*tuple_)
    
    def findall_dirs(self, root):
        Path = namedtuple('Path', 'path relpath mtime')
        for tuple_ in self.client.exec(
            '''
            def foo():
                for d in fs.findall_dirs(root):
                    yield d.path, d.relpath, d.mtime
            return foo()
            ''',
            root=root
        ):
            yield Path(*tuple_)
    
    def findall_files(self, root):
        Path = namedtuple('Path', 'path relpath mtime')
        for tuple_ in self.client.exec(
            '''
            def bar():
                for f in fs.findall_files(root):
                    yield f.path, f.relpath, f.mtime
            return bar()
            ''',
            root=root
        ):
            yield Path(*tuple_)
    
    def _fast_call(self, func_name, *args0, **args1):
        return self.client.exec(
            'fs.{}(*args0, **args1)'.format(func_name),
            args0=args0, args1=args1
        )
