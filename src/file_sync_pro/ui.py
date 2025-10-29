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

_state = sc.get_state(version=18)


def _init_state(remote_ip: str) -> dict:
    air.config(remote_ip, 2160)
    root_i = 'data/snapshots/likianta-rider-r2'
    root_o = 'data/snapshots/likianta-xiaomi-12s-pro'
    snap_left = snapshot.Snapshot(f'{root_i}/file-sync-project.json')
    setattr(snap_left, 'data', None)
    return {
        'records'   : {
            'file-sync-pro': (
                f'{root_i}/file-sync-project.json',
                f'{root_o}/file-sync-project.json',
            ),
            'gitbook'      : (
                f'{root_i}/gitbook-source-docs.json',
                f'{root_o}/gitbook-source-docs.json',
            ),
            'photolens'    : (
                f'{root_i}/photolens.json',
                f'{root_o}/photolens.json',
            ),
            'pictures'     : (
                f'{root_i}/normalized-pictures.json',
                f'{root_o}/normalized-pictures.json',
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
            - 172.20.128.101
            - 192.168.8.101
            - ...
    """
    if not _state:
        _state.update(_init_state(remote_ip))
    
    if st.button('Reconnect to remote'):
        # air.connect(remote_ip, 2160)
        air.default_client.reopen()
    # if not air.default_client.is_opened:
    #     return
    
    records = _state['records']
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
    
    snap_left: snapshot.Snapshot = _state['snap_left']
    if left_path:
        if snap_left.snapshot_file != left_path:
            snap_left.snapshot_file = left_path
            _preload_snap_data(snap_left)
    else:
        return
    
    snap_right: t.Optional[snapshot.Snapshot] = _state['snap_right']
    if right_path.startswith('air://'):
        if snap_right:
            assert right_path.startswith(snap_right.fs.url)
            if snap_right.snapshot_file != (
                x := right_path.removeprefix(snap_right.fs.url)
            ):
                snap_right.snapshot_file = x
                _preload_snap_data(snap_right)
        else:
            snap_right = _state['snap_right'] = snapshot.Snapshot(right_path)
            assert snap_right is not None
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
        
    if _state['snap_right']:
        if st.button('Close right connection'):
            air.default_client.close()
            _state['snap_right'] = None


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
    snap = _state[f'snap_{side}']
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
                # noinspection PyTypeChecker
                with st.spinner('This may take a while, please wait...'):
                    snapshot.create_snapshot(
                        snap.fs.url + snap.snapshot_file, root
                    )
            _preload_snap_data(snap)
        if side == 'right' and snap.data is None:
            if st.button('Clone from left', disabled=root == placeholder):
                snap_left = _state['snap_left']
                snap_right = _state['snap_right']
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
    """
    launch steps:
        enter ssh
            android termux: sshd
            pc:
                ssh <android_ip> -p 8022
                <input ssh password>
        (optional) upgrade file-sync-pro in android:
            pc: dufs . -p <dufs_port>
            ssh: python -m pip install -r <pc_ip>:<dufs_port>/requirements.lock
        run server:
            ssh: python -m file_sync_pro run_air_server
        run ui:
            pc: strun 2163 src/file_sync_pro/ui.py <android_ip>
    """
    st.set_page_config('File Sync Pro')
    cli.run(main)
