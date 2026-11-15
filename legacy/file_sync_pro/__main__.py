import os
import typing as tp

import airmise as air
import lk_utils
from argsense import cli
from lk_utils import fs

from . import filesys
from . import snapshot
from .filesys import FtpFileSystem
from .init import clone_project

cli.add_cmd(clone_project)
cli.add_cmd(snapshot.create_snapshot)
cli.add_cmd(snapshot.update_snapshot)
cli.add_cmd(snapshot.sync_snapshot)
cli.add_cmd(snapshot.merge_snapshot)
cli.add_cmd(snapshot.rebuild_snapshot)


@cli
def fetch_remote_file(path_i: str, path_o: str = '') -> None:
    fs, path_i = filesys.AirFileSystem.create_from_url(path_i)
    if not path_o:
        path_o = 'data/downloads/{}'.format(lk_utils.fs.basename(path_i))
    fs.download_file(path_i, path_o)
    print('see "{}"'.format(path_o))


@cli
def fetch_remote_snapshot(target: str) -> None:
    assert target.startswith('ftp://') and target.endswith('.json')
    fetch_remote_file(target, 'data/remote_snapshot.json')


@cli
def force_sync_snapshot(snapshot_file_a: str, snapshot_file_b: str) -> None:
    fs_b, snapshot_file_b = FtpFileSystem.create_from_url(snapshot_file_b)
    fs_b.upload_file(snapshot_file_a, snapshot_file_b)


@cli
def run_air_server() -> None:
    air.register(filesys.LocalFileSystem)

    def _find_files(dir: str) -> tp.Iterator[tuple]:
        for f in fs.find_files(dir):
            yield f.path, f.relpath, f.mtime

    def _findall_dirs(dir: str) -> tp.Iterator[tuple]:
        for f in fs.findall_dirs(dir):
            yield f.path, f.relpath, f.mtime

    def _findall_files(dir: str) -> tp.Iterator[tuple]:
        for f in fs.findall_files(dir):
            yield f.path, f.relpath, f.mtime

    air.run_server(
        {
            'find_files': _find_files,
            'findall_dirs': _findall_dirs,
            'findall_files': _findall_files,
            'fs': fs,
            'os': os,
        },
        port=2160,
        # verbose=True,
    )


if __name__ == '__main__':
    """
    # get help
    pox -m file_sync_pro -h
    
    # create snapshot in local disk
    mkdir data/snapshots/likianta-rider-r2  # optional
    pox -m file_sync_pro create_snapshot \
        data/snapshots/likianta-rider-r2/gitbook-source-docs.json \
        C:/Likianta/documents/gitbook/source-docs
    
    # create snapshot in remote side
    # --- android termux
    sshd
    # --- pc terminal
    ssh 172.20.128.101 -p 8022
    <input ssh passphrase>
    # --- ssh
    pox -m file_sync_pro run_air_server
    # --- pc terminal
    mkdir data/snapshots/likianta-xiaomi-12s-pro  # optional
    pox -m file_sync_pro create_snapshot \
        data/snapshots/likianta-xiaomi-12s-pro/gitbook-source-docs.json \
        air://172.20.128.101:2160/storage/emulated/0/Likianta/documents \
        /gitbook/source-docs
    
    # update snapshot
    pox -m file_sync_pro update_snapshot \
        data/snapshots/likianta-rider-r2/gitbook-source-docs.json
    pox -m file_sync_pro update_snapshot \
        data/snapshots/likianta-xiaomi-12s-pro/gitbook-source-docs.json
    
    # sync snapshot
    pox -m file_sync_pro sync_snapshot -h
    # dry run
    pox -m file_sync_pro sync_snapshot \
        data/snapshots/likianta-rider-r2/gitbook-source-docs.json \
        data/snapshots/likianta-xiaomi-12s-pro/gitbook-source-docs.json -d
    ...
    """
    cli.run()
