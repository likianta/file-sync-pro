import os
import typing as t
from collections import defaultdict
from lk_utils import fs as fs0
from .base import BaseFileSystem
from .base import T
from . import air2

fs1 = fs0


class GeneralFileSystem(BaseFileSystem):
    _remote_source_root = ''
    
    def is_remote(self, path):
        if path.startswith('air://'):
            return True
        elif self._remote_source_root:
            return path.startswith(self._remote_source_root)
        elif path.startswith('/'):
            raise Exception
        else:
            return False
    
    def resolve_remote_source_root(self, path):
        assert path.startswith('air://')
        global fs1
        fs1, root = air2.create_fs_from_url(path)
        self._remote_source_root = root
        return root
    
    # -------------------------------------------------------------------------
    
    def dump(self, data: t.Any, file: T.Path, *, binary: bool = False) -> None:
        fs1.dump(data, file, type='binary' if binary else 'auto')
    
    def exist(self, path: T.Path) -> bool:
        return fs1.exist(path)
    
    def findall_dirs(self, root):
        for d in fs1.findall_dirs(root):
            yield d.relpath, d.mtime
    
    def findall_files(
        self, root: T.Path, history: T.Tree = None, ignores: T.Ignores = None
    ) -> t.Iterator[t.Tuple[T.RelPath, T.Time]]:
        total_count = 0
        reuse_count = 0
        
        dir_2_mtime = get_dirnodes_cache(root) or {}
        dir_2_files = defaultdict(list)
        if history:
            for k, v in history.items():
                d = k.rsplit('/', 1)[0] if '/' in k else '.'
                dir_2_files[d].append((k, v))
        
        def submit_files(dirpath):
            nonlocal total_count, reuse_count
            for f in fs1.find_files(dirpath):
                key = fs0.relpath(f.path, root)
                yield key, f.mtime
                total_count += 1
                if history and f.mtime == history.get(key):
                    reuse_count += 1
                else:
                    print(':i3p', key)
        
        yield from submit_files(root)
        for d in fs1.findall_dirs(root):
            key = d.relpath
            if d.mtime == dir_2_mtime.get(key):
                yield from (xlist := dir_2_files[key])
                total_count += len(xlist)
                reuse_count += len(xlist)
            else:
                yield from submit_files(d.path)
        
        if history:
            print(':v2p', 'reuse {} of {} files ({:.2%})'.format(
                reuse_count, total_count, reuse_count / total_count
            ))
    
    def load(self, file: T.Path, *, binary: bool = False) -> t.Any:
        return fs1.load(file, type='binary' if binary else 'auto')
    
    def make_dir(self, dirpath: T.Path) -> None:
        if not fs1.exist(dirpath):
            fs1.make_dir(dirpath)
    
    def make_dirs(self, dirpath: T.Path) -> None:
        # assert dirpath.startswith(self.root)
        if not fs1.exist(dirpath):
            fs1.make_dirs(dirpath)
    
    # noinspection PyMethodMayBeStatic
    def modify_mtime(self, path: T.Path, mtime: int) -> None:
        atime = os.path.getatime(path)
        os.utime(path, (atime, mtime))
    
    def remove_dir(self, dir: T.Path) -> None:
        if fs1.exist(dir):
            fs1.remove_tree(dir)
    
    def remove_file(self, file: T.Path) -> None:
        fs1.remove_file(file)
