import typing as t
from collections import defaultdict
from lk_utils import fs as lkfs
from lk_utils import timestamp
from .class_ import Snapshot
from .class_ import T
from ..filesys import AirFileSystem
from ..filesys import FtpFileSystem
from ..filesys import LocalFileSystem


def create_snapshot(snap_file: T.AnyPath, source_root: str = None) -> None:
    snap = Snapshot(snap_file)
    
    fs0 = snap.fs
    # create `fs1`, update `source_root`, create `snap_inside`
    if source_root:
        if source_root.startswith('air://'):
            fs1, x = AirFileSystem.create_from_url(source_root)
            source_root = x
            snap_inside = False
        elif source_root.startswith('ftp://'):
            fs1, x = FtpFileSystem.create_from_url(source_root)
            source_root = x
            assert source_root.startswith('/Likianta')
            snap_inside = snap.snapshot_file.startswith(source_root + '/')
        else:
            fs1 = fs0
            source_root = lkfs.abspath(source_root)
            snap_inside = snap.snapshot_file.startswith(source_root + '/')
    else:
        fs1 = fs0
        source_root = lkfs.parent(snap.snapshot_file)
        snap_inside = True
    
    data = dict(fs1.findall_files(source_root))
    if snap_inside:
        key = lkfs.relpath(snap.snapshot_file, source_root)
        print('pop self from snap data', key, ':v')
        data.pop(key, None)
    
    if isinstance(fs1, (AirFileSystem, FtpFileSystem)):
        assert source_root.startswith('/')
        root = '{}/{}'.format(fs1.url, source_root[1:])
    else:
        root = source_root
    snap.rebuild_snapshot(data, root=root)


def update_snapshot(snap_file: T.AnyPath) -> Snapshot:
    snap = Snapshot(snap_file)
    snap_data = snap.load_snapshot()
    src_root = snap_data['root']
    
    data = dict(snap.fs.findall_files(
        src_root, history=snap_data['base']['data']
    ))
    if snap.is_snapshot_inside:
        key = lkfs.relpath(snap.snapshot_file, src_root)
        if key in data:
            print('pop self from snap data', key, ':v')
            data.pop(key)
    snap.update_snapshot(data)
    return snap


def sync_snapshot(
    snap_file_a: T.AnyPath,
    snap_file_b: T.AnyPath,
    dry_run: bool = False,
    no_doubt: bool = False,
    manual_select_base_side: t.Literal['a', 'b'] = '',
) -> None:
    """
    params:
        dry_run (-d):
        manual_select_base_side (-b):
            if set, suggest setting 'b'. it means that `snap_file_b` is -
            passive side.
    """
    snap_a = Snapshot(snap_file_a)
    snap_b = Snapshot(snap_file_b)
    
    snap_alldata_a = snap_a.load_snapshot()
    snap_alldata_b = snap_b.load_snapshot()
    
    def select_base_side() -> t.Tuple[str, T.SnapshotData]:
        if manual_select_base_side:
            if manual_select_base_side == 'a':
                base = snap_alldata_a['base']
            else:
                base = snap_alldata_b['base']
        else:
            match compare_version(
                snap_alldata_a['base']['version'],
                snap_alldata_b['base']['version'],
            ):
                case 0:
                    print('same base snap', ':v4')
                    base = snap_alldata_a['base']
                case 1:
                    print('use snap_b0 as base')  # use the "old" one.
                    base = snap_alldata_b['base']
                case 2:
                    print('use snap_a0 as base')
                    base = snap_alldata_a['base']
                case _:
                    raise Exception
        # noinspection PyUnboundLocalVariable
        return base['version'], base['data']
    
    def compare_version(ver_a: str, ver_b: str) -> int:
        """
        tip: we'd prefer put newer ver at first argument, the older as `ver_b`.
        """
        hash_a, time_a = ver_a.split('-')
        hash_b, time_b = ver_b.split('-')
        if hash_a == hash_b:
            return 0
        elif time_b <= time_a:  # we prefer assuming b is older than a.
            return 1
        else:
            return 2
    
    snap_ver_base, snap_data_base = select_base_side()
    snap_data_a = snap_alldata_a['current']['data']
    snap_data_b = snap_alldata_b['current']['data']
    
    # -------------------------------------------------------------------------
    
    # noinspection PyTypeChecker
    def compare_new_to_old(
        snap_new: T.SnapshotData,
        snap_old: T.SnapshotData,
    ) -> t.Iterator[T.ComposedAction]:
        """
        note: the yieled movement can only be the following:
            '+>', '=>', '->'.
        """
        for k, time_new in snap_new.items():
            if k in snap_old:
                time_old = snap_old[k]
                # assert time_new >= time_old, k
                # if time_new > time_old:
                #     yield k, '=>', time_new
                if time_new > time_old:
                    yield k, '=>', time_new
                elif time_new < time_old:
                    if not k.endswith('/'):
                        print(':v5i', k, time_new, time_old)
                        # yield k, '<=?', time_old
            else:
                yield k, '+>', time_new
        for k, time_old in snap_old.items():
            if k not in snap_new:
                yield k, '->', time_old
    
    changes_a = {} if compare_version(
        snap_alldata_a['current']['version'], snap_ver_base,
    ) == 0 else {
        k: (m, t_)
        for k, m, t_ in compare_new_to_old(snap_data_a, snap_data_base)
        # if not k.endswith('/')
    }
    changes_b = {} if compare_version(
        snap_alldata_b['current']['version'], snap_ver_base,
    ) == 0 else {
        k: (m, t_)
        for k, m, t_ in compare_new_to_old(snap_data_b, snap_data_base)
        # if not k.endswith('/')
    }
    
    final_changes = _compare_changelists(changes_a, changes_b, no_doubt)
    
    snap_data_new = _apply_changes(
        final_changes,
        snap_data_base,
        snap_data_a,
        snap_data_b,
        t.cast(LocalFileSystem, snap_a.fs),
        t.cast(AirFileSystem, snap_b.fs),
        snap_alldata_a['root'],
        snap_alldata_b['root'],
        dry_run,
    )
    if not dry_run:
        print(':v3', 'lock snapshot')
        assert snap_data_new is not None
        snap_a.rebuild_snapshot(snap_data_new, snap_alldata_a['root'])
        snap_b.rebuild_snapshot(snap_data_new, snap_alldata_b['root'])


def merge_snapshot(
    snap_file_a: T.AnyPath,
    snap_file_b: T.AnyPath,
    dry_run: bool = False,
    no_doubt: bool = False,
) -> None:
    """
    params:
        dry_run (-d):
    """
    snap_a = Snapshot(snap_file_a)
    snap_b = Snapshot(snap_file_b)
    
    snap_alldata_a = snap_a.load_snapshot()
    snap_alldata_b = snap_b.load_snapshot()
    
    # noinspection PyTypeChecker
    changes = _compare_changelists(
        {k: ('+>', t_) for k, t_ in snap_alldata_a['current']['data'].items()},
        {k: ('+>', t_) for k, t_ in snap_alldata_b['current']['data'].items()},
        no_doubt
    )
    
    snap_data_new = _apply_changes(
        changes,
        {},
        snap_alldata_a['current']['data'],
        snap_alldata_b['current']['data'],
        t.cast(LocalFileSystem, snap_a.fs),
        t.cast(AirFileSystem, snap_b.fs),
        snap_alldata_a['root'],
        snap_alldata_b['root'],
        dry_run
    )
    
    if not dry_run:
        print(':v3', 'lock snapshot')
        assert snap_data_new is not None
        snap_a.rebuild_snapshot(snap_data_new, snap_alldata_a['root'])
        snap_b.rebuild_snapshot(snap_data_new, snap_alldata_b['root'])


# noinspection PyTypeChecker
def _compare_changelists(
    changes_a: t.Dict[T.Key, t.Tuple[T.Movement, T.Time]],
    changes_b: t.Dict[T.Key, t.Tuple[T.Movement, T.Time]],
    no_doubt: bool = False,
) -> t.Iterator[T.ComposedAction]:
    for k, (ma, ta) in changes_a.items():
        if k in changes_b:
            mb, tb = changes_b[k]
            if ma == '+>' or ma == '=>':
                if mb == '+>' or mb == '=>':
                    if ta >= tb:
                        # b created/updated -> a created/updated
                        if no_doubt:
                            yield k, '=>', ta
                        else:
                            yield k, '=>?', ta
                    else:  # ta < tb
                        # a created/updated -> b created/updated
                        if no_doubt:
                            yield k, '<=', tb
                        else:
                            yield k, '<=?', tb
                else:
                    # 1. ta > tb:
                    #   b created -> b deleted -> a created/updated
                    # 2. ta < tb:
                    #   a created/updated -> b created -> b deleted
                    # 3. ta < tb:
                    #   b created -> a created/updated -> b deleted
                    # 4. ta == tb:
                    #   a b created/updated at same time -> b deleted
                    yield k, '+>', ta
            else:  # ma == '->'
                if mb == '+>' or mb == '=>':
                    yield k, '<+', tb
        else:
            yield k, ma, ta
    for k, (mb, tb) in changes_b.items():
        if k not in changes_a:
            if mb == '+>':
                yield k, '<+', tb
            elif mb == '=>':
                yield k, '<=', tb
            else:  # mb == '->'
                yield k, '<-', tb


def _apply_changes(
    changes: t.Iterator[T.ComposedAction],
    snap_data_base: T.SnapshotData,
    snap_data_a: T.SnapshotData,
    snap_data_b: T.SnapshotData,
    fs_a: LocalFileSystem,
    fs_b: AirFileSystem,
    root_a: str,
    root_b: str,
    dry_run: bool = False,
) -> t.Optional[T.SnapshotData]:
    print(root_a, root_b, ':l')
    if dry_run:
        i = 0
        table = [('index', 'left', 'action', 'right')]
        action_count = defaultdict(int)
        for k, m, _ in changes:
            if k.endswith('/') and '=' in m:
                continue
            i += 1
            colored_key = '[{}]{}[/]'.format(
                'yellow' if '?' in m else
                'green' if '+' in m else
                'blue' if '=' in m else
                'red',
                k.replace('[', '\\[')
            )
            # table.append((
            #     str(i),
            #     colored_key if m.startswith(('+>', '=>', '<-')) else
            #     '' if m.startswith(('->', '<+')) else
            #     '...',
            #     m.rstrip('?'),
            #     '' if m.startswith(('+>', '<-')) else
            #     '...' if m.startswith(('=>',)) else
            #     colored_key,
            # ))
            m = m.rstrip('?')
            # noinspection PyTypeChecker
            table.append((
                str(i),
                *(
                    # (colored_key, '+>', '') if m == '+>' else
                    # (colored_key, '=>', '...') if m == '=>' else
                    # ('', '->', colored_key) if m == '->' else
                    # ('', '<+', colored_key) if m == '<+' else
                    # ('...', '<=', colored_key) if m == '<=' else
                    # (colored_key, '<-', '')  # '<-'
                    (colored_key, '+>', '[dim]<tocreate>[/]') if m == '+>' else
                    (colored_key, '=>', '[dim]<outdated>[/]') if m == '=>' else
                    ('[dim]<deleted>[/]', '->', colored_key) if m == '->' else
                    ('[dim]<tocreate>[/]', '<+', colored_key) if m == '<+' else
                    ('[dim]<outdated>[/]', '<=', colored_key) if m == '<=' else
                    (colored_key, '<-', '[dim]<deleted>[/]')  # '<-'
                )
            ))
            action_count[m] += 1
        if len(table) > 1:
            print(table, ':r2')
            print(action_count, ':r2')
        else:
            print('no change', ':v4')
        return
    
    # -------------------------------------------------------------------------
    
    _created_dirs_a = set()
    for p in snap_data_a:
        d = root_a
        for x in p.split('/')[:-1]:
            d += '/' + x
            _created_dirs_a.add(d)
    _created_dirs_b = set()
    for p in snap_data_b:
        d = root_b
        for x in p.split('/')[:-1]:
            d += '/' + x
            _created_dirs_b.add(d)
    
    def delete_dir_a(dirpath: T.AbsPath) -> None:
        fs_a.remove_dir(dirpath)
    
    def delete_dir_b(dirpath: T.AbsPath) -> None:
        fs_b.remove_dir(dirpath)
    
    def make_dir_a(dirpath: T.AbsPath) -> None:
        if dirpath not in _created_dirs_a:
            fs_a.make_dir(dirpath)
            _created_dirs_a.add(dirpath)
    
    def make_dir_b(dirpath: T.AbsPath) -> None:
        if dirpath not in _created_dirs_b:
            fs_b.make_dir(dirpath)
            _created_dirs_b.add(dirpath)
    
    def make_dirs_a(filepath: str) -> None:
        i = filepath.rfind('/')
        dirpath = filepath[:i]
        if dirpath not in _created_dirs_a:
            fs_a.make_dirs(dirpath)
            _created_dirs_a.add(dirpath)
    
    def make_dirs_b(filepath: str) -> None:
        i = filepath.rfind('/')
        dirpath = filepath[:i]
        if dirpath not in _created_dirs_b:
            fs_b.make_dirs(dirpath)
            _created_dirs_b.add(dirpath)
    
    _conflicts_dir = 'data/conflicts/{}'.format(timestamp('ymd_hns'))
    lkfs.make_dir(_conflicts_dir)
    
    def backup_conflict_file_a(file: T.Path) -> None:
        file_i = file
        m, n, o = lkfs.split(file_i, 3)
        file_o = '{}/{}.a.{}'.format(_conflicts_dir, n, o)
        lkfs.copy_file(file_i, file_o, reserve_metadata=True)
    
    def backup_conflict_file_b(file: T.Path, mtime: int) -> None:
        file_i = file
        m, n, o = lkfs.split(file_i, 3)
        file_o = '{}/{}.b.{}'.format(_conflicts_dir, n, o)
        fs_b.download_file(file_i, file_o, mtime)
    
    def delete_file_a(file: T.Path) -> None:
        # file_i = file
        # m, n, o = lkfs.split(file_i, 3)
        # file_o = '{}/{}.a.{}'.format(_deleted_dir, n, o)
        # lkfs.move(file_i, file_o)
        fs_a.remove_file(file)
    
    def delete_file_b(file: T.Path) -> None:
        # file_i = file
        # m, n, o = lkfs.split(file_i, 3)
        # file_o = '{}/{}.b.{}'.format(_deleted_dir, n, o)
        # data_i = fs_b.load(file_i)
        # lkfs.dump(data_i, file_o, 'binary')
        fs_b.remove_file(file)
    
    def update_file_a2b(relpath: T.Path) -> None:
        file_i = '{}/{}'.format(root_a, relpath)
        file_o = '{}/{}'.format(root_b, relpath)
        fs_b.upload_file(file_i, file_o)
    
    def update_file_b2a(relpath: T.Path, mtime: int) -> None:
        file_i = '{}/{}'.format(root_b, relpath)
        file_o = '{}/{}'.format(root_a, relpath)
        fs_b.download_file(file_i, file_o, mtime)
    
    # snap_new = snap_data_base.copy()
    snap_new: T.SnapshotData = snap_data_base
    
    for k, m, t in changes:
        # isdir = k.endswith('/')
        # if k.endswith('/') and '=' in m:
        #     continue
        
        # resolve conflict
        if m.endswith('?'):
            assert m in ('=>?', '<=?')
            if not k.endswith('/'):
                if m == '=>?':
                    backup_conflict_file_b('{}/{}'.format(root_b, k), t)
                else:
                    backup_conflict_file_a('{}/{}'.format(root_a, k))
            m = m[:-1]
        # assert '?' not in m
        
        colored_key = '[{}]{}[/]'.format(
            'green' if '+' in m else
            'blue' if '=' in m else
            'red',
            k.replace('[', '\\[')
        )
        # noinspection PyStringFormat
        print(':ir', '{} {} {}'.format(
            *(
                (colored_key, '+>', '[dim]<tocreate>[/]') if m == '+>' else
                (colored_key, '=>', '[dim]<outdated>[/]') if m == '=>' else
                ('[dim]<deleted>[/]', '->', colored_key) if m == '->' else
                ('[dim]<tocreate>[/]', '<+', colored_key) if m == '<+' else
                ('[dim]<outdated>[/]', '<=', colored_key) if m == '<=' else
                (colored_key, '<-', '[dim]<deleted>[/]')  # '<-'
            )
        ))
        
        if k.endswith('/'):
            if m == '+>':
                make_dir_b('{}/{}'.format(root_b, k))
                snap_new[k] = t
            elif m == '->':
                delete_dir_b('{}/{}'.format(root_b, k))
                snap_new.pop(k)
            elif m == '<+':
                make_dir_a('{}/{}'.format(root_a, k))
                snap_new[k] = t
            elif m == '<-':
                delete_dir_a('{}/{}'.format(root_a, k))
                snap_new.pop(k)
            else:
                snap_new[k] = t
                # raise Exception(k, m, t)
        else:
            if m in ('+>', '=>'):
                make_dirs_b('{}/{}'.format(root_b, k))
                update_file_a2b(k)
                snap_new[k] = t
            elif m == '->':
                delete_file_b('{}/{}'.format(root_b, k))
                snap_new.pop(k)
            elif m in ('<+', '<='):
                make_dirs_a('{}/{}'.format(root_a, k))
                update_file_b2a(k, t)
                snap_new[k] = t
            elif m == '<-':
                delete_file_a('{}/{}'.format(root_a, k))
                snap_new.pop(k)
            else:
                raise Exception(k, m, t)
    
    if lkfs.empty(_conflicts_dir):
        lkfs.remove_tree(_conflicts_dir)
    else:
        print('found {} conflicts, see in {}'.format(
            len(lkfs.find_file_names(_conflicts_dir)),
            _conflicts_dir
        ), ':v6')
    
    return snap_new
