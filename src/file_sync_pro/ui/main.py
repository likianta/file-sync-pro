if __name__ == '__main__':
    __package__ = 'src.file_sync_pro.ui'

import streamlit as st
import streamlit_canary as sc
from argsense import cli
from lk_utils import fs
from . import snap_maker
from ..snapshot import api as snap_api


_state = sc.init_state(lambda: {
    'snapshot_names': {},
    'source_names': (),
}, version=28)


@cli
def main(host_name: str = 'likianta-rider-r2') -> None:
    if not _state['source_names']:
        dirnames = fs.find_dir_names('data/snapshots')
        assert host_name in dirnames
        dirnames.remove(host_name)
        _state['source_names'] = tuple(dirnames)
    
    cols = st.columns(2)
    with cols[0]:
        src0 = st.selectbox(
            'Left source',
            (host_name,),
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
            _state['source_names'],
        )
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
            st.toast(':green[Left snapshot updated.]')
        if st.button('Update right'):
            snap_api.update_snapshot(snap_b)
            st.toast(':green[Right snapshot updated.]')
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
        kwargs['consider_moving'] = st.toggle('Consider moving')
        with place1:
            if st.button('Sync', type='primary'):
                snap_api.sync_snapshot(snap_a, snap_b, **kwargs)
        with place2:
            if st.button('Merge'):
                kwargs.pop('manual_select_base_side')
                kwargs.pop('consider_moving')
                snap_api.merge_snapshot(snap_a, snap_b, **kwargs)


if __name__ == '__main__':
    """
    1. android termux:
        python -m file_sync_pro run_air_server
    2. pc:
        strun 2163 src/file_sync_pro/ui/main.py
    """
    st.set_page_config('File Sync Pro')
    cli.run(main)
