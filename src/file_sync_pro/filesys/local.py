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
    
    # def find_changed_files(
    #     self, root: T.Path, old_tree: T.Tree
    # ) -> t.Iterable[t.Tuple[T.RelPath, T.Time]]:
    #     def recurse(dirpath: T.Path) -> t.Iterable[t.Tuple[T.RelPath, T.Time]]:
    #         for d in fs.find_dirs(dirpath):
    #             key = fs.relpath(d.path, root) + '/'
    #             if key in old_tree:
    #                 if d.mtime == old_tree[key]:
    #                     # yield from recurse(d.path)
    #                     continue
    #             yield key, d.mtime
    #
    #             for f in fs.find_files(d.path):
    #                 key = fs.relpath(f.path, root)
    #                 if key in old_tree:
    #                     if f.mtime == old_tree[key]:
    #                         continue
    #                 yield key, f.mtime
    #
    #             yield from recurse(d.path)
    #
    #     yield from recurse(root)
    
    def findall_files(
        self, root: T.Path, history: T.Tree = None, ignores: T.Ignores = None
    ) -> t.Iterator[t.Tuple[T.RelPath, T.Time]]:
        def recurse(dirpath):
            for f in fs.find_files(dirpath):
                key = fs.relpath(f.path, root)
                yield key, f.mtime
            for d in fs.find_dirs(dirpath):
                key = fs.relpath(d.path, root) + '/'
                if history and key in history:
                    if d.mtime == history[key]:
                        yield from (
                            (a, b)
                            for a, b in history.items()
                            if a.startswith(key)
                        )
                        continue
                yield key, d.mtime
                yield from recurse(d.path)
        
        yield from recurse(root)
    
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
