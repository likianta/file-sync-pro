from collections import defaultdict
from typing import Dict
from typing import Iterator
from typing import Tuple
from . import local
from . import remote


class T:
    DirPath = str
    RelPath = str
    Time = int
    Tree = Dict[RelPath, Time]


class FileSystem:
    
    def __init__(self, root):
        self._fs0 = local.fs
        self.is_remote = remote.is_remote_path(root)
        if self.is_remote:
            self._fs1, self.root = remote.create_fs_from_url(root)
        else:
            self._fs1, self.root = local.fs, local.fs.abspath(root)
    
    @property
    def core(self):
        return self._fs1
    
    @property
    def url(self):
        if self.is_remote:
            assert self.root.startswith('/')
            return '{}/{}'.format(self._fs1.url, self.root[1:])  # noqa
        else:
            return self.root
    
    def findall_dirs(
        self, root: T.DirPath
    ) -> Iterator[Tuple[T.RelPath, T.Time]]:
        for d in self._fs1.findall_dirs(root):
            yield d.relpath, d.mtime
    
    def findall_files(
        self, root: T.DirPath, history: Tuple[T.Tree, T.Time] = None
    ) -> Iterator[Tuple[T.RelPath, T.Time]]:
        file_2_mtime = {}
        dir_2_mtime = {}
        dir_2_files = defaultdict(list)
        if history:
            file_2_mtime = history[0]
            dir_2_mtime = history[1]
            for k, v in file_2_mtime.items():
                d = k.rsplit('/', 1)[0] if '/' in k else '.'
                dir_2_files[d].append((k, v))
        
        total_count = 0
        reuse_count = 0
        
        def submit_files(dirpath):
            nonlocal total_count, reuse_count
            for f in self._fs1.find_files(dirpath):
                key = self._fs0.relpath(f.path, root)
                yield key, f.mtime
                total_count += 1
                if f.mtime == file_2_mtime.get(key):
                    reuse_count += 1
                else:
                    print(':i3p', key)
        
        yield from submit_files(root)
        for d in self._fs1.findall_dirs(root):
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
    
    def findall_nodes(
        self, root: T.DirPath, history: Tuple[T.Tree, T.Time] = None
    ) -> Tuple[T.Tree, T.Time]:
        f2t0 = {}  # file-to-mtime-old
        d2t0 = {}  # dir-to-mtime-old
        d2f0 = defaultdict(list)  # dir-to-files-old
        f2t1 = {}  # file-to-mtime-new
        d2t1 = {}  # dir-to-mtime-new
        
        if history:
            f2t0 = history[0]
            d2t0 = history[1]
            for f, t in f2t0.items():
                d = f.rsplit('/', 1)[0] if '/' in f else '.'
                d2f0[d].append((f, t))
        
        total_count = 0
        reuse_count = 0
        
        def submit_files(dirpath) -> Iterator[Tuple[T.RelPath, T.Time]]:
            nonlocal total_count, reuse_count
            for f in self._fs1.find_files(dirpath):
                key = self._fs0.relpath(f.path, root)
                yield key, f.mtime
                total_count += 1
                if f.mtime == f2t0.get(key):
                    reuse_count += 1
                else:
                    print(':i3p', key)
        
        f2t1.update(submit_files(root))
        for d in self._fs1.findall_dirs(root):
            key = d.relpath
            d2t1[key] = d.mtime
            if d.mtime == d2t0.get(key):
                f2t1.update(d2f0[key])
                total_count += len(d2f0[key])
                reuse_count += len(d2f0[key])
            else:
                f2t1.update(submit_files(d.path))
        
        if history:
            print(':v2p', 'reuse {} of {} files ({:.2%})'.format(
                reuse_count, total_count, reuse_count / total_count
            ))

        return f2t1, d2t1  # noqa
