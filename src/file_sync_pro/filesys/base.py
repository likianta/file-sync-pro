import typing as t


class T:
    Path = str
    RelPath = str
    Time = int
    Ignores = t.FrozenSet[Path]
    Tree = t.Dict[RelPath, Time]


class BaseFileSystem:
    def dump(self, data: t.Any, file: T.Path) -> None:
        raise NotImplementedError
    
    def exist(self, path: T.Path) -> bool:
        raise NotImplementedError
    
    # def find_changed_files(
    #     self, root: T.Path, old_tree
    # ) -> t.Iterable[t.Tuple[T.Path, T.Time]]:
    #     raise NotImplementedError
    
    def findall_files(
        self, root: T.Path, ignores: T.Ignores = None,
    ) -> t.Iterable[t.Tuple[T.Path, T.Time]]:
        raise NotImplementedError
    
    def load(self, file: T.Path) -> t.Any:
        raise NotImplementedError
    
    def make_dir(self, dirpath: T.Path) -> None:
        raise NotImplementedError
    
    def make_dirs(self, dirpath: T.Path) -> None:
        raise NotImplementedError
    
    def remove_dir(self, dir: T.Path) -> None:
        raise NotImplementedError
    
    def remove_file(self, file: T.Path) -> None:
        raise NotImplementedError
