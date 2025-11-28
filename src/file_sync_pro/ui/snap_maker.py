if __name__ == '__main__':
    __package__ = 'src.file_sync_pro.ui'

import streamlit as st
import streamlit_canary as sc
from lk_utils import fs
from .. import snapshot


def main():
    root_type = st.radio(
        'Root type', ('Local', 'Remote'), horizontal=True
    )
    if root_type == 'Local':
        root = sc.path_input('Local directory')
    else:
        root = ''
        cols = iter(st.columns((3, 7)))
        with next(cols):
            addr = st.text_input('Address', '172.20.128.101:2160')
        with next(cols):
            root = sc.path_input(
                'Remote directory',
                placeholder='/storage/emulated/0/Likianta/...'
            )
    if not root: return
    
    snap_name = st.text_input('Snapshot filename', fs.basename(root))
    snap_file = 'data/snapshots/{}/{}.json'.format(
        'likianta-rider-r2' if root_type == 'Local' else
        'likianta-xiaomi-12s-pro',
        snap_name
    )
    st.markdown('File will be {} at "{}".'.format(
        ':red[overwritten]' if fs.exist(snap_file) else ':blue[created]',
        snap_file
    ))
    if st.button('Continue', use_container_width=True):
        with st.spinner('Working...'):
            snapshot.create_snapshot(
                snap_file,
                root if root_type == 'Local' else
                'air://{}/{}'.format(addr, root[1:])
            )
        st.toast(':green[Successfully created snapshot file.]')


if __name__ == '__main__':
    main()
