from lk_utils import fs
from .filesys import FtpFileSystem
from .filesys import LocalFileSystem


def clone_project(root_i: str, root_o: str) -> None:
    """
    note:
        1. make sure `<root_i>/snapshot.json` exists. if not, use -
            `.main.create_snapshot()` to create one.
        2. FIXME: make sure root_o preexists. i.e. you may need to manually -
            create an empty folder first.
    """
    assert not root_i.startswith('ftp://') and root_o.startswith('ftp://')
    assert fs.exist(f'{root_i}/snapshot.json')
    
    fs_i = LocalFileSystem(root_i)
    fs_o = FtpFileSystem(root_o)
    
    # make empty dirs
    snap_i = fs_i.load_snapshot()['current']['data']
    tobe_created_dirs = set()
    for relpath in snap_i:
        if '/' in relpath:
            d = fs_o.root
            for x in relpath.split('/')[:-1]:
                d += '/' + x
                tobe_created_dirs.add(d)
    for d in sorted(tobe_created_dirs):
        fs_o.make_dir(d, precheck=False)
    
    # copy files
    for relpath, mtime in snap_i.items():
        print(':i', relpath)
        file_i = f'{fs_i.root}/{relpath}'
        file_o = f'{fs_o.root}/{relpath}'
        fs_o.upload_file(file_i, file_o, mtime)
    fs_o.upload_file(fs_i.snapshot_file, fs_o.snapshot_file)
