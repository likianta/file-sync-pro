from argsense import cli
from lk_utils import fs as _fs

from . import filesys
from . import snapshot
from .filesys import FtpFileSystem
from .init import clone_project

cli.add_cmd(clone_project)
cli.add_cmd(snapshot.create_snapshot)
# cli.add_cmd(snapshot.update_snapshot)


@cli
def update_snapshot(snap_file: str, subfolder: str = None) -> None:
    snap = snapshot.update_snapshot(snap_file, subfolder)
    if isinstance(snap.fs, FtpFileSystem):  # TEST
        snap.fs.download_file(snap.snapshot_file, 'data/remote_snapshot.json')


cli.add_cmd(snapshot.sync_snapshot)


@cli
def fetch_remote_file(path_i: str, path_o: str = None) -> None:
    fs = FtpFileSystem.create_from_url(path_i)
    path_i = path_i.removeprefix(fs.url)
    if path_o is None:
        path_o = 'data/downloads/{}'.format(_fs.basename(path_i))
    fs.download_file(path_i, path_o)
    print('see "{}"'.format(path_o))


@cli
def fetch_remote_snapshot(target: str) -> None:
    assert target.startswith('ftp://') and target.endswith('.json')
    fetch_remote_file(target, 'data/remote_snapshot.json')


@cli
def force_sync_snapshot(snapshot_file_a: str, snapshot_file_b: str) -> None:
    fs_b = FtpFileSystem.create_from_url(snapshot_file_b)
    snapshot_file_b = snapshot_file_b.removeprefix(fs_b.url)
    fs_b.upload_file(snapshot_file_a, snapshot_file_b)


cli.add_cmd(filesys.send_file_to_remote)


if __name__ == '__main__':
    # pox -m file_sync_pro -h
    
    # pox -m file_sync_pro create_snapshot
    #   C:/Likianta/documents/gitbook/source-docs/snapshot.json
    # pox -m file_sync_pro clone_project
    #   C:/Likianta/documents/gitbook/source-docs
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs
    
    # pox -m file_sync_pro update_snapshot
    #   C:/Likianta/documents/gitbook/source-docs/snapshot.json
    # pox -m file_sync_pro update_snapshot
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs
    #   /snapshot.json
    
    # pox -m file_sync_pro sync_snapshot
    #   C:/Likianta/documents/gitbook/source-docs/snapshot.json
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs
    #   /snapshot.json -d
    # pox -m file_sync_pro sync_snapshot
    #   C:/Likianta/documents/gitbook/source-docs/snapshot.json
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs
    #   /snapshot.json
    cli.run()
