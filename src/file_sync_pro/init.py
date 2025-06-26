from lk_utils import fs
from .snapshot import Snapshot


def clone_project(
    snapshot_file_i: str, snapshot_file_o: str, root_o: str = None
) -> None:
    """
    note:
        1. make sure `<root_i>/snapshot.json` exists. if not, use -
            `.main.create_snapshot()` to create one.
        2. make sure `fs.parent(snapshot_file_o)` does not exist.
    """
    snap_i = Snapshot(snapshot_file_i)
    snap_o = Snapshot(snapshot_file_o)
    
    snap_full_i = snap_i.load_snapshot()
    root_i = snap_full_i['root']
    root_o = root_o or fs.parent(snap_o.snapshot_file)
    print('{} -> {}'.format(root_i, root_o))
    
    # make empty dirs
    # tobe_created_dirs = set()
    tobe_created_dirs = {root_o}
    snap_data_i = snap_full_i['current']['data']
    for relpath in snap_data_i:
        if '/' in relpath:
            d = root_o
            for x in relpath.split('/')[:-1]:
                d += '/' + x
                tobe_created_dirs.add(d)
    for d in sorted(tobe_created_dirs):
        snap_o.fs.make_dir(d, precheck=False)
    
    # copy files
    for relpath, mtime in snap_data_i.items():
        print(':i', relpath)
        file_i = f'{root_i}/{relpath}'
        file_o = f'{root_o}/{relpath}'
        snap_o.fs.upload_file(file_i, file_o, mtime)
    
    snap_o.rebuild_snapshot(snap_data_i, root_o)
