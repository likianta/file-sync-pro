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
    
    notice: in dry-run mode, if you find red colored items, it means they are -
    content changed files. you need to make their content same manually before -
    disabling dry-run mode.
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
    
    rows = [('index', 'key', 'mtime_a', '..', 'mtime_b')]
    rowx = 0
    for key in keys_a & keys_b:
        if dry_run:
            print(':iv', key)
        
        mtime_a = snap_data_a[key]
        mtime_b = snap_data_b[key]
        if mtime_a == mtime_b:
            continue
        
        is_a_newer = mtime_a >= mtime_b
        file_a = '{}/{}'.format(root_a, key)
        file_b = '{}/{}'.format(root_b, key)
        same = True if key.endswith('/') else is_same_content(file_a, file_b)
        
        if dry_run:
            rowx += 1
            primary_color = (
                'blue' if same and key.endswith('/')
                else 'magenta' if same
                else 'yellow' if no_doubt
                else 'red'
            )
            rows.append((
                str(rowx),
                key.replace('[', '\\['),
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
        else:
            if same or no_doubt:
                print(':i2v1', '{}: A {} B'.format(
                    key, '<-' if is_a_newer else '->',
                ))
                if is_a_newer:
                    snap_a.fs.modify_mtime(file_a, mtime_b)
                else:
                    snap_b.fs.modify_mtime(file_b, mtime_a)
            else:
                raise Exception(
                    'you need to sync the content of {} first'.format(key)
                )
            
    if dry_run:
        if rowx:
            print(':r2', rows)
            print(
                'there are {} dirs and {} files encountered missmatched-mtime '
                'issues'.format(
                    (x := len(tuple(
                        y for y in rows[1:] if y[1].endswith('/')
                    ))),
                    len(rows) - x
                ),
                ':v1'
            )
        else:
            print(':v4', 'no missmatched-mtime issues')
    else:
        print(
            'if mtimes are fixed, you need to refresh or rebuild the snapshot '
            'file.', ':t'
        )


if __name__ == '__main__':
    # pox -m file_sync_pro.doctor -h
    cli.run(fix_mtime)
