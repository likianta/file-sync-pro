import streamlit as st
import streamlit_canary as sc
from lk_utils import fs

from ..snapshot import api


def dialog() -> None:
    st.dialog('Create Snapshot', width='small')(main_panel)()


def main_panel() -> None:
    with sc.row():
        dev_name = st.text_input(
            'Device name', '', help='Suggest kebab-cased name.'
        )
        file_name = st.text_input(
            'Thread', '', help='Suggest kebab-cased name.'
        )
    with sc.columns((6.5, 3.5)) as cols:
        host = cols[0].text_input('Host', '')
        port = cols[1].number_input('Port', 2160)
    path = st.text_input(
        'Path',
        help='Android path for example: `/storage/emulated/0/DCIM/Camera`.',
    )

    ready = all((dev_name, file_name, host, port, path))
    if st.button(
        'Create snapshot', type='primary', disabled=not ready, width='stretch'
    ):
        fs.make_dir('data/snapshots/{}'.format(dev_name))
        api.create_snapshot(
            'data/snapshots/{}/{}'.format(dev_name, file_name),
            'air://{}:{}/{}'.format(host, port, path.lstrip('/')),
        )
