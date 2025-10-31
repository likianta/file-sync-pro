if __name__ == '__main__':
    __package__ = 'src.file_sync_pro.ui'

import airmise as air
import streamlit as st
import streamlit_canary as sc
from argsense import cli
from lk_utils import fs
from . import snap_maker
from ..snapshot import api as snap_api

_state = sc.get_state(version=23)


def _init_state(remote_ip: str) -> dict:
    air.config(remote_ip, 2160)
    
    _snap_root_i = 'data/snapshots/likianta-rider-r2'
    _snap_root_o = 'data/snapshots/likianta-xiaomi-12s-pro'
    
    def load_snap_a(name):
        file = f'{_snap_root_i}/{name}'
        root = fs.load(file)['root']
        return file, root
        
    def load_snap_b(name):
        file = f'{_snap_root_o}/{name}'
        root = fs.load(file)['root']
        return file, root
        
    return {
        'records': {
            'Gitbook': (
                load_snap_a('gitbook-source-docs.json'),
                load_snap_b('gitbook-source-docs.json'),
            ),
            'Pictures': (
                load_snap_a('normalized-pictures-2025.json'),
                load_snap_b('normalized-pictures.json'),
            ),
            'New...': (('', ''), ('', ''))
        }
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
    
    key = st.radio('Select working item', _state['records'].keys())
    if key == 'New...':
        with st.container(border=True):
            # TODO: if created, refresh snapshot list.
            snap_maker.main()
        return
    
    ((snap_a, root_a), (snap_b, root_b)) = _state['records'][key]
    st.info('📁 **{}**  \n📁 **{}**'.format(root_a, root_b))
    with st.container(horizontal=True, vertical_alignment='center'):
        if st.button('Update left'):
            snap_api.update_snapshot(snap_a)
        if st.button('Update right'):
            snap_api.update_snapshot(snap_b)
        place1 = st.empty()
        place2 = st.empty()
        kwargs = {}
        with st.popover('More options'):
            kwargs['manual_select_base_side'] = sc.radio(
                'Manual select base side',
                {'': 'None', 'a': 'A', 'b': 'B'},
                horizontal=True
            )
            kwargs['no_doubt'] = st.toggle('No doubt')
        kwargs['dry_run'] = st.toggle('Dry run')
        with place1:
            if st.button('Sync', type='primary'):
                snap_api.sync_snapshot(snap_a, snap_b, **kwargs)
        with place2:
            if st.button('Merge'):
                kwargs.pop('manual_select_base_side', None)
                snap_api.merge_snapshot(snap_a, snap_b, **kwargs)


if __name__ == '__main__':
    """
    launch steps:
        enter ssh
            android termux: sshd
            pc: ssh <android_ip> -p 8022
                <input ssh password>
        (optional) upgrade file-sync-pro in android:
            pc: dufs . -p <dufs_port>
            ssh: python -m pip install -r <pc_ip>:<dufs_port>/requirements.lock
        run server:
            ssh: python -m file_sync_pro run_air_server
        run ui:
            pc: strun 2163 src/file_sync_pro/ui/main.py <android_ip>
    """
    st.set_page_config('File Sync Pro')
    cli.run(main)
