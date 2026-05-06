if __name__ == '__main__':
    __package__ = 'src.file_sync_pro.ui_st'

import airmise as air
import streamlit as st
import streamlit_canary as sc
import typing as tp
from argsense import cli
from lk_utils import fs
from . import snap_maker
from ..snapshot import api as snap_api

_state = sc.init_state(
    lambda: {
        'default_index': -1,
        'devices': {
            # 'likianta-home-pc': {
            #     'name': 'Likianta Home PC',
            #     'ip': '192.168.1.100',
            #     # 'dir': 'data/snapshots/likianta-home-pc',
            #     'files': tuple(
            #         (f.name, f.path)
            #         for f in fs.find_files(
            #             'data/snapshots/likianta-home-pc', '.json'
            #         )
            #     ),
            # },
            'likianta-oneplus-11': {
                'name': 'Likianta Oneplus 11',
                'ip': '172.20.128.106',
                # 'dir': 'data/snapshots/likianta-oneplus-11',
                'files': tuple(
                    (f.name, f.path)
                    for f in fs.find_files(
                        'data/snapshots/likianta-oneplus-11', '.json'
                    )
                ),
            },
            'likianta-rider-r2': {
                'name': 'Likianta Rider R2',
                'ip': '172.20.128.100',
                # 'dir': 'data/snapshots/likianta-rider-r2',
                'files': tuple(
                    (f.name, f.path)
                    for f in fs.find_files(
                        'data/snapshots/likianta-rider-r2', '.json'
                    )
                ),
            },
            'likianta-xiaomi-12s-pro': {
                'name': 'Likianta Xiaomi 12s Pro',
                'ip': '172.20.128.101',
                # 'dir': 'data/snapshots/likianta-xiaomi-12s-pro',
                'files': tuple(
                    (f.name, f.path)
                    for f in fs.find_files(
                        'data/snapshots/likianta-xiaomi-12s-pro', '.json'
                    )
                ),
            },
        },
        'local_ips': ('', 'localhost', air.get_local_ip_address()),
        # 'snapshot_names': {},
        # 'source_names': (),
    },
    version=32,
)


@cli
def main(host_name: str = 'likianta-rider-r2') -> None:
    if _state['default_index'] == -1:
        _state['default_index'] = tuple(_state['devices'].keys()).index(
            host_name
        )

    # if not _state['source_names']:
    #     dirnames = fs.find_dir_names('data/snapshots')
    #     assert host_name in dirnames
    #     dirnames.remove(host_name)
    #     _state['source_names'] = tuple(dirnames)

    cols = st.columns(2)
    with cols[0]:
        l_key = st.selectbox(
            'Left source',
            _state['devices'].keys(),
            format_func=lambda x: _state['devices'][x]['name'],
            index=_state['default_index'],
        )
        l_addr = st.text_input(
            'Left address', '{}:2160'.format(_state['devices'][l_key]['ip'])
        )
        if l_addr.split(':')[0] in _state['local_ips']:
            l_addr = ''
        l_snap_file = st.selectbox(
            'Left snapshot',
            _state['devices'][l_key]['files'],
            format_func=lambda x: x[0],
        )[1]

    with cols[1]:
        r_key = st.selectbox(
            'Right source',
            _state['devices'].keys(),
            format_func=lambda x: _state['devices'][x]['name'],
        )
        r_addr = st.text_input(
            'Right address', '{}:2160'.format(_state['devices'][r_key]['ip'])
        )
        if r_addr.split(':')[0] in _state['local_ips']:
            r_addr = ''
        r_snap_file = st.selectbox(
            'Right snapshot',
            _state['devices'][r_key]['files'],
            format_func=lambda x: x[0],
        )[1]

    l_path = fs.load(l_snap_file)['root']
    r_path = fs.load(r_snap_file)['root']
    st.info(
        """
        - :{}[{} **{}** ({})]
        - :{}[{} **{}** ({})]
        """.format(
            *(
                l_addr == ''
                and ('gray', ':material/desktop_windows:', l_path, 'local')
                or ('red', ':material/desktop_cloud:', l_path, 'remote')
            ),
            *(
                r_addr == ''
                and ('gray', ':material/desktop_windows:', r_path, 'local')
                or ('red', ':material/desktop_cloud:', r_path, 'remote')
            ),
        )
    )

    place1 = st.container(horizontal=True, vertical_alignment='center')
    place2 = st.empty()

    with place1:
        if st.button('Update left'):
            snap_api.update_snapshot(l_snap_file, l_addr)
            st.toast(':green[Left snapshot updated.]')
        if st.button('Update right'):
            snap_api.update_snapshot(r_snap_file, r_addr)
            st.toast(':green[Right snapshot updated.]')
        do_sync = st.button('Sync', type='primary')
        do_merge = st.button('Merge')
        kwargs = {}
        with st.popover('More options'):
            kwargs['manual_select_base_side'] = sc.radio(
                'Manual select base side',
                {'': 'Auto', 'a': 'A', 'b': 'B'},
                horizontal=True,
            )
            kwargs['no_doubt'] = st.toggle('No doubt')
            kwargs['consider_moving'] = st.toggle('Consider moving')
        kwargs['dry_run'] = st.toggle('Dry run')
        if do_sync:
            with place2:
                if kwargs['dry_run']:
                    snap_api.sync_snapshot(
                        l_snap_file,
                        l_addr,
                        r_snap_file,
                        r_addr,
                        _preview=_preview_changes,
                        **kwargs,
                    )
                else:
                    with sc.progress('Syncing...') as prog:
                        snap_api.sync_snapshot(
                            l_snap_file,
                            l_addr,
                            r_snap_file,
                            r_addr,
                            _progress=prog,
                            **kwargs,
                        )
        if do_merge:
            kwargs.pop('manual_select_base_side')
            kwargs.pop('consider_moving')
            snap_api.merge_snapshot(
                l_snap_file, l_addr, r_snap_file, r_addr, **kwargs
            )


def _preview_changes(changes: tp.Iterable[snap_api.T.ComposedAction]) -> None:
    i = 0
    table = [('Index', 'Left', 'Action', 'Right')]
    for k, m, _ in changes:
        i += 1
        colored_key = ':{}[{}]'.format(
            'yellow'
            if '?' in m
            else 'green'
            if '+' in m
            else 'blue'
            if '=' in m
            else 'green dim'
            if '~' in m
            else 'red',  # '-' in m
            (isinstance(k, str) and k or k[0]).replace('[', '\\['),
        )
        m = m.rstrip('?')
        table.append(
            (
                str(i),
                *(
                    (colored_key, '+>', '...')
                    if m == '+>'
                    else (colored_key, '=>', '...')
                    if m == '=>'
                    else (colored_key, '~>', '...')
                    if m == '~>'
                    else ('...', '->', colored_key)
                    if m == '->'
                    else ('...', '<+', colored_key)
                    if m == '<+'
                    else ('...', '<=', colored_key)
                    if m == '<='
                    else ('...', '<~', colored_key)
                    if m == '<~'
                    else (colored_key, '<-', '...')  # m == '<-'
                ),
            )
        )
    st.table(table)


if __name__ == '__main__':
    """
    1. android termux:
        python -m file_sync_pro run_air_server
    2. pc:
        strun 2163 src/file_sync_pro/ui_st/app.py
    """
    st.set_page_config('File Sync Pro')
    cli.run(main)
