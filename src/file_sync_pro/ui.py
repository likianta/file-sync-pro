if __name__ == '__main__':
    __package__ = 'src.file_sync_pro'

import airmise as air
import streamlit as st
import streamlit_canary as sc
import typing as t
from argsense import cli
from lk_utils import fs
from . import filesys
from . import snapshot
from .init import clone_project

_data = {}


def _init_session(remote_ip: str):
    snap_left = snapshot.Snapshot('data/snapshots/file_sync_pro.json')
    setattr(snap_left, 'data', None)
    return {
        'records'   : {
            'file-sync-pro': (
                'C:/Likianta/workspace/dev.master.likianta/file-sync-pro/data'
                '/snapshots/file_sync_pro.json',
                'air://{}:2160/storage/emulated/0/Likianta/work'
                '/file-sync-pro/data/snapshots/file_sync_pro_(android).json'
                .format(remote_ip)
            ),
            'gitbook'      : (
                'C:/Likianta/documents/gitbook/source-docs/snapshot.json',
                'air://{}:2160/storage/emulated/0/Likianta/work'
                '/file-sync-pro/data/snapshots/gitbook_(android).json'
                .format(remote_ip)
            ),
            'photolens'    : (
                'C:/Likianta/workspace/dev.master.likianta/file-sync-pro/data'
                '/snapshots/photolens.json',
                'air://{}:2160/storage/emulated/0/Likianta/work'
                '/file-sync-pro/data/snapshots/photolens.json'
                .format(remote_ip)
            ),
            'pictures'     : (
                'C:/Likianta/workspace/dev.master.likianta/file-sync-pro/data'
                '/snapshots/pictures_(pc).json',
                'air://{}:2160/storage/emulated/0/Likianta/work'
                '/file-sync-pro/data/snapshots/pictures_(android).json'
                .format(remote_ip)
            ),
            'new...'       : ()
        },
        'snap_left' : snap_left,
        'snap_right': None,
    }


@cli
def main(remote_ip: str) -> None:
    """
    params:
        remote_ip:
            - 192.168.8.31
            - 172.20.128.123
            - 10.236.7.32
            - ...
    """
    if not (x := sc.session.get_data(version=15)):
        x.update(_init_session(remote_ip))
    global _data
    _data = x
    
    records = _data['records']
    key = sc.radio('Host and remote paths', records.keys(), horizontal=False)
    if key == 'new...':
        left_path, right_path = '', ''
    else:
        left_path, right_path = records[key]
    
    # cols = iter(st.columns(2))
    # with next(cols):
    #     left_path = st.text_input('Left', left_path)
    # with next(cols):
    #     right_path = st.text_input(
    #         'Right',
    #         right_path or left_path and _guess_right_path(left_path)
    #     )
    left_path = _input_left_path(left_path)
    right_path = _input_right_path(right_path, left_path)
    
    snap_left: snapshot.Snapshot = _data['snap_left']
    if left_path:
        if snap_left.snapshot_file != left_path:
            snap_left.snapshot_file = left_path
            _preload_snap_data(snap_left)
    else:
        return
    
    snap_right: t.Optional[snapshot.Snapshot] = _data['snap_right']
    if right_path.startswith('air://'):
        if snap_right:
            assert right_path.startswith(snap_right.fs.url)
            if snap_right.snapshot_file != (
                x := right_path.removeprefix(snap_right.fs.url)
            ):
                snap_right.snapshot_file = x
                _preload_snap_data(snap_right)
        else:
            snap_right = _data['snap_right'] = snapshot.Snapshot(right_path)
            _preload_snap_data(snap_right)
        # right_path = snap_right.snapshot_file
    
    _create_snapshot('left')
    
    # noinspection PyUnresolvedReferences
    if st.button('Update left', disabled=snap_left.data is None):
        snapshot.update_snapshot(left_path)
    
    _create_snapshot('right')
    
    # noinspection PyUnresolvedReferences
    if st.button('Update right', disabled=snap_right.data is None):
        snapshot.update_snapshot(right_path)
    
    dry_run = st.toggle('Dry run')
    no_doubt = st.checkbox('No doubt')
    if st.button('Sync'):
        snapshot.sync_snapshot(left_path, right_path, dry_run, no_doubt)
    if st.button('Merge'):
        snapshot.merge_snapshot(left_path, right_path, dry_run, no_doubt)
        
    if _data['snap_right']:
        if st.button('Close right connection'):
            air.default_client.close()
            _data['snap_right'] = None


# -------------------------------------------------------------------------
    
    # cols = iter(st.columns(4))
    # with next(cols):
    #     if sc.long_button(
    #         'Add record',
    #         disabled=not left_path or (left_path, right_path) in records
    #     ):
    #         records.append((left_path, right_path))
    #         if len(records) > 20:
    #             records.pop(0)
    #         st.rerun()
    # with next(cols):
    #     if fs.exist(left_path):
    #         if sc.long_button('Update left'):
    #             snapshot.update_snapshot(left_path)
    #     else:
    #         with st.popover(
    #             'Create left',
    #             use_container_width=True,
    #         ):
    #             x = st.text_input(
    #                 'Source root',
    #                 placeholder=(p := fs.parent(left_path))
    #             ) or p
    #             if st.button('Create'):
    #                 snapshot.create_snapshot(left_path, x)
    # with next(cols):
    #     if sc.long_button('Update right'):
    #         snapshot.update_snapshot(right_path)
    # with next(cols):
    #     if sc.long_button('Sync left and right'):
    #         snapshot.sync_snapshot(left_path, right_path)
    
    
def _create_snapshot(side: t.Literal['left', 'right']):
    snap = _data[f'snap_{side}']
    with st.popover(
        f'Create {side}',
        # use_container_width=True,
        # disabled=fs.exist(left_path),
        # key=f'create_{side}_popover'
    ):
        # noinspection PyUnresolvedReferences
        if snap.data is not None:
            st.write(
                ':red[The snapshot has already been created, '
                'but you can recreate it.]'
            )
        # noinspection PyUnresolvedReferences
        root = st.text_input(
            'Source root',
            placeholder=(
                placeholder :=
                snap.data['root'] if snap.data else
                fs.parent(snap.snapshot_file)
            ),
            key=f'source_root_{side}'
        ) or placeholder
        if st.button('Create', key=f'create_{side}'):
            assert snap.fs.exist(root)
            if isinstance(snap.fs, filesys.LocalFileSystem):
                snapshot.create_snapshot(snap.snapshot_file, root)
            else:
                with st.spinner('This may take a while, please wait...'):
                    snapshot.create_snapshot(
                        snap.fs.url + snap.snapshot_file, root
                    )
            _preload_snap_data(snap)
        if side == 'right' and snap.data is None:
            if st.button('Clone from left', disabled=root == placeholder):
                snap_left = _data['snap_left']
                snap_right = _data['snap_right']
                clone_project(
                    snap_left.snapshot_file,
                    snap_right.fs.url + snap_right.snapshot_file,
                    root
                )


def _guess_right_path(left_path: str):
    left_path = left_path.replace('\\', '/').rstrip('/')
    if '/' in left_path:
        idx = left_path.index('/')
        return 'air://172.20.128.123:2160/storage/emulated/0/{}'.format(
            left_path[idx + 1:]
        )
    return ''


def _input_left_path(default):
    if x := st.text_input('Left', default):
        return fs.abspath(x)
    return ''


def _input_right_path(default, left_path):
    placeholder = left_path and _guess_right_path(left_path)
    x = st.text_input(
        'Right',
        default,
        placeholder=placeholder,
    )
    return x or placeholder
    
    
def _preload_snap_data(snap: snapshot.Snapshot) -> None:
    if snap.fs.exist(snap.snapshot_file):
        snap.data = snap.load_snapshot()
    else:
        snap.data = None


if __name__ == '__main__':
    # ssh:
    #   ssh 192.168.8.31 -p 8022
    #   <input ssh_password>
    #   python -m file_sync_pro run_air_server
    # strun 2163 src/file_sync_pro/ui.py 192.168.8.31
    st.set_page_config('File Sync Pro')
    cli.run(main)
