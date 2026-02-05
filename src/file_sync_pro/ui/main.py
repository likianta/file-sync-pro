if __name__ == '__main__':
    __package__ = 'src.file_sync_pro.ui'

import airmise as air
import streamlit as st
import streamlit_canary as sc
from argsense import cli
from lk_utils import fs
from . import snap_maker
from ..snapshot import api as snap_api


_state = sc.get_state(lambda: {
    'air_connected': False,
    'snapshot_names': {},
    'sources': tuple(fs.find_dir_names('data/snapshots')),
}, version=25)


@cli
def main(remote_ip: str = '172.20.128.101') -> None:
    """
    params:
        remote_ip:  # FIXME: optionally required?
            - 172.20.128.101
            - 192.168.8.101
            - ...
    """
    # if not _state['air_connected']:
    #     air.connect(remote_ip, 2160)
    #     _state['air_connected'] = True
    
    cols = st.columns(2)
    with cols[0]:
        src0 = st.selectbox(
            'Left source',
            _state['sources'],
            index=1,  # index=1 indicates to "likianta-rider-r2"
            disabled=True,  # make this widget "read-only"
        )
        if src0 not in _state['snapshot_names']:
            _state['snapshot_names'][src0] = tuple(
                x.removesuffix('.json') for x in 
                fs.find_file_names('data/snapshots/{}'.format(src0))
            )
    with cols[1]:
        src1 = st.selectbox(
            'Right source',
            _state['sources'],
        )
    if src1 == src0:
        st.warning('Cannot select the same source in both sides.')
        return
    else:
        if src1 not in _state['snapshot_names']:
            _state['snapshot_names'][src1] = tuple(
                x.removesuffix('.json') for x in
                fs.find_file_names('data/snapshots/{}'.format(src1))
            )
    
    common_snapshot_names = tuple(
        x for x in _state['snapshot_names'][src0]
        if x in _state['snapshot_names'][src1]
    ) + ('new...',)
    
    key = st.radio('Select working item', common_snapshot_names)
    if key == 'new...':
        with st.container(border=True):
            # TODO: if created, refresh snapshot list.
            snap_maker.main()
        return
    
    snap_a, root_a = (
        'data/snapshots/{}/{}.json'.format(src0, key),
        fs.load('data/snapshots/{}/{}.json'.format(src0, key))['root']
    )
    snap_b, root_b = (
        'data/snapshots/{}/{}.json'.format(src1, key),
        fs.load('data/snapshots/{}/{}.json'.format(src1, key))['root']
    )
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
    1. android termux:
        python -m file_sync_pro run_air_server
    2. pc:
        strun 2163 src/file_sync_pro/ui/main.py <android_ip>
    """
    st.set_page_config('File Sync Pro')
    cli.run(main)
