from argsense import cli
from hashlib import md5
from lk_utils import fs
from lk_utils.time_utils.time import seconds_to_hms
from .snapshot import Snapshot


@cli
def fix_mtime(
    snap_file_a: str,
    snap_file_b: str,
) -> None:
    snap_a = Snapshot(snap_file_a)
    snap_b = Snapshot(snap_file_b)
    
    snap_fulldata_a = snap_a.load_snapshot()
    snap_fulldata_b = snap_b.load_snapshot()
    
    root_a = snap_fulldata_a['root']
    root_b = snap_fulldata_b['root']
    
    snap_data_a = snap_fulldata_a['current']['data']
    snap_data_b = snap_fulldata_b['current']['data']
    
    keys_a = frozenset(snap_data_a.keys())
    keys_b = frozenset(snap_data_b.keys())
    
    for key in keys_a & keys_b:
        mtime1 = snap_data_a[key]
        mtime2 = snap_data_b[key]
        if mtime1 != mtime2:
            is_a_newer = mtime1 >= mtime2
            if _is_same_content(
                '{}/{}'.format(root_a, key),
                '{}/{}'.format(root_b, key),
            ):
                print(
                    ':iv2',
                    'suggest roll back {}\' mtime from {} to {} at {}'.format(
                        'LEFT' if is_a_newer else 'RIGHT',
                        seconds_to_hms(mtime1 if is_a_newer else mtime2),
                        seconds_to_hms(mtime2 if is_a_newer else mtime1),
                        key,
                    )
                )
            else:
                print(
                    ':iv6',
                    'you need to sync the content of {} first'.format(key)
                )


def _is_same_content(file1, file2) -> bool:
    data1 = fs.load(file1, 'binary')
    data2 = fs.load(file2, 'binary')
    if data1 == data2:
        if md5(data1).hexdigest() == md5(data2).hexdigest():
            return True
    return False


if __name__ == '__main__':
    # android termux runs:
    #   python -m file_sync_pro run-air-server
    # pox -m file_sync_pro.doctor -h
    cli.run(fix_mtime)
