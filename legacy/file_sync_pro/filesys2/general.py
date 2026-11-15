from . import local
from . import remote


def get_general_fs(root):
    if remote.is_remote_path(root):
        return remote.create_fs_from_url(root)[0]
    else:
        return local.fs
