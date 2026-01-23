from .filesys import LocalFileSystem
from .snapshot import Snapshot


def clone_project(
    snapshot_file_i: str, snapshot_file_o: str, root_o: str = None
) -> None:
    """
    note:
        1. make sure `snapshot_file_i` is latest, if not, use
            `./__main__.py:update_snapshot` to update.
        2. make sure `snapshot_file_o` exists, if not, use
            `./__main__.py:create_snapshot` to create one.
        3. make sure `snapshot_file_o:root:parent` exists, if not, you need to
            manually create it in its device.
        FIXME: `root_o` is not available at the moment.
    """
    snap_i = Snapshot(snapshot_file_i)
    snap_o = Snapshot(snapshot_file_o)
    assert not isinstance(snap_o.fs, LocalFileSystem)
    
    snap_full_i = snap_i.load_snapshot()
    root_i = snap_full_i['root']
    root_o = root_o or snap_o.source_root
    print('{} -> {}'.format(root_i, root_o))
    
    # make empty dirs
    # tobe_created_dirs = set()
    tobe_created_dirs = {root_o}
    snap_data_i = snap_full_i['current']['files']
    for relpath in snap_data_i:
        if '/' in relpath:
            d = root_o
            for x in relpath.split('/')[:-1]:
                d += '/' + x
                tobe_created_dirs.add(d)
    for d in sorted(tobe_created_dirs):
        print(':i2', 'make dir', d.removeprefix(root_o))
        snap_o.fs.make_dir(d)
    
    # copy files
    for relpath, mtime in snap_data_i.items():
        print(':i2', 'copy file', relpath)
        file_i = f'{root_i}/{relpath}'
        file_o = f'{root_o}/{relpath}'
        snap_o.fs.upload_file(file_i, file_o, mtime)
    
    snap_o.rebuild_snapshot(snap_data_i, root_o)
