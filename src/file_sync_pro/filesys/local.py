import os
import typing as t
from lk_utils import fs
from .base import BaseFileSystem
from .base import T


class LocalFileSystem(BaseFileSystem):
    def dump(self, data: t.Any, file: T.Path, *, binary: bool = False) -> None:
        fs.dump(data, file, type='binary' if binary else 'auto')
    
    def exist(self, path: T.Path) -> bool:
        return fs.exist(path)
    
    def findall_files(
        self, root: T.Path, history: T.Tree = None, ignores: T.Ignores = None
    ) -> t.Iterator[t.Tuple[T.RelPath, T.Time]]:
        total_count = 0
        reuse_count = 0
        
        if history:
            history_dir_2_files = {'./': []}
            #   {reldir: [(filename, filemtime), ...], ...}
            for k, v in history.items():
                if k.endswith('/'):
                    history_dir_2_files[k] = []
                else:
                    if '/' in k:
                        a, b = k.rsplit('/', 1)
                    else:
                        a, b = '.', k
                    history_dir_2_files[a + '/'].append((b, v))
        else:
            history_dir_2_files = None
        
        def submit_files(dirpath: T.Path) -> t.Iterator[
            t.Tuple[T.RelPath, T.Time]
        ]:
            nonlocal total_count
            for f in fs.find_files(dirpath):
                key = fs.relpath(f.path, root)
                print(key, ':pi3')
                yield key, f.mtime
                total_count += 1
        
        # yield from submit_files(root)
        for f in fs.find_files(root):
            key = f.relpath
            yield key, f.mtime
            total_count += 1
            if history and key in history and f.mtime == history[key]:
                reuse_count += 1
            else:
                print(':i3', key)
        for d in fs.findall_dirs(root):
            key = d.relpath + '/'
            yield key, d.mtime
            total_count += 1
            if history and key in history and d.mtime == history[key]:
                reuse_count += 1
                for name, time in history_dir_2_files[key]:
                    fkey = key + name
                    yield fkey, time
                    total_count += 1
                    reuse_count += 1
                # print(':i3v', 'skip printing {} reused files'.format(
                #     len(history_dir_2_files[key])
                # ))
                continue
            else:
                print(':i3', key)
            yield from submit_files(d.path)
        
        if history:
            print(':v2p', 'reuse {} of {} files ({:.2%})'.format(
                reuse_count, total_count, reuse_count / total_count
            ))
    
    def load(self, file: T.Path, *, binary: bool = False) -> t.Any:
        return fs.load(file, type='binary' if binary else 'auto')
    
    def make_dir(self, dirpath: T.Path) -> None:
        if not fs.exist(dirpath):
            fs.make_dir(dirpath)
    
    def make_dirs(self, dirpath: T.Path) -> None:
        # assert dirpath.startswith(self.root)
        if not fs.exist(dirpath):
            fs.make_dirs(dirpath)
    
    # noinspection PyMethodMayBeStatic
    def modify_mtime(self, path: T.Path, mtime: int) -> None:
        atime = os.path.getatime(path)
        os.utime(path, (atime, mtime))
    
    def remove_dir(self, dir: T.Path) -> None:
        if fs.exist(dir):
            fs.remove_tree(dir)
    
    def remove_file(self, file: T.Path) -> None:
        fs.remove_file(file)
