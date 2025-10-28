from argsense import cli
from hashlib import md5
from lk_utils import timestamp
from .snapshot import Snapshot


@cli
def fix_mtime(
    snap_file_a: str,
    snap_file_b: str,
    dry_run: bool = False,
    no_doubt: bool = False,
) -> None:
    """
    params:
        dry_run (-d):
        no_doubt (-n):
    """
    snap_a = Snapshot(snap_file_a)
    snap_b = Snapshot(snap_file_b)
    
    snap_fulldata_a = snap_a.load_snapshot()
    snap_fulldata_b = snap_b.load_snapshot()
    
    root_a = snap_a.source_root
    root_b = snap_b.source_root
    
    snap_data_a = snap_fulldata_a['current']['data']
    snap_data_b = snap_fulldata_b['current']['data']
    
    keys_a = frozenset(snap_data_a.keys())
    keys_b = frozenset(snap_data_b.keys())
    
    def is_same_content(file_a, file_b) -> bool:
        data_a: bytes = snap_a.fs.load(file_a, binary=True)
        data_b: bytes = snap_b.fs.load(file_b, binary=True)
        return md5(data_a).hexdigest() == md5(data_b).hexdigest()
    
    def report():
        print(':r2', rows)
    
    rows = [('index', 'key', 'mtime_a', '..', 'mtime_b')]
    rowx = 0
    for key in keys_a & keys_b:
        print(':i', key)
        if key.endswith('/'):
            continue
        
        mtime_a = snap_data_a[key]
        mtime_b = snap_data_b[key]
        if mtime_a == mtime_b:
            continue
        
        is_a_newer = mtime_a >= mtime_b
        file_a = '{}/{}'.format(root_a, key)
        file_b = '{}/{}'.format(root_b, key)
        same = is_same_content(file_a, file_b)
        
        rowx += 1
        primary_color = 'magenta' if same else 'yellow' if no_doubt else 'red'
        rows.append((
            str(rowx),
            key,
            '[{}]{}[/]'.format(
                'dim' if is_a_newer else primary_color,
                timestamp(time_sec=mtime_a),
            ),
            '<-' if is_a_newer else '->',
            '[{}]{}[/]'.format(
                primary_color if is_a_newer else 'dim',
                timestamp(time_sec=mtime_b),
            ),
        ))
        
        if not dry_run:
            if same or no_doubt:
                if is_a_newer:
                    snap_a.fs.modify_mtime(file_a, mtime_b)
                else:
                    snap_b.fs.modify_mtime(file_b, mtime_a)
            else:
                report()
                raise Exception(
                    'you need to sync the content of {} first'.format(key)
                )
    else:
        report()
    print(
        'if mtimes are fixed, you need to refresh or rebuild the snapshot '
        'file.', ':t'
    )


if __name__ == '__main__':
    # pox -m file_sync_pro.doctor -h
    cli.run(fix_mtime)
