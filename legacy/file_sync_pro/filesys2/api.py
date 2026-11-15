from . import local
from . import specific


def create_fs_handlers(root):
    """
    fs0: local file system.
    fs1: local file system (same as fs0) or
        remote file system (same interfaces as fs0)
    fs2: an instance with specialized methods for this project.
    """
    fs0 = local.fs
    fs1 = fs0
    fs2 = specific.FileSystem(root)
    if fs2.is_remote:
        fs1 = fs2.core
    return fs0, fs1, fs2
