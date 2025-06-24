if __name__ == '__main__':
    __package__ = 'src.file_sync_pro'

import typing as t
from argsense import cli
from collections import defaultdict
from lk_utils import fs as _fs
from lk_utils import timestamp
from .filesys import FtpFileSystem
from .filesys import LocalFileSystem
from .filesys import T as T0
from .init import clone_project
from .snapshot import Snapshot
from .snapshot import T as T1
from .snapshot import get_snapshot_file_for_target_root


class T:
    Path = T0.Path
    SnapshotData = T1.SnapshotData
    Time = T0.Time
    
    Key = str  # a relpath
    Movement = t.Literal['+>', '=>', '->', '<+', '<=', '<-']
    #   +>  add to right
    #   =>  overwrite to right
    #   ->  delete to right
    #   <+  add to left
    #   <=  overwrite to left
    #   <-  delete to left
    #   ==  no change
    ComposedAction = t.Tuple[Key, Movement, Time]


cli.add_cmd(clone_project)


@cli
def create_snapshot(root: str) -> None:
    update_snapshot(root, rebuild=True)


@cli
def update_snapshot(
    root: str, subfolder: str = None, rebuild: bool = False
) -> None:
    """
    note: ftp work takes more time, depends on network traffic.
    params:
        rebuild (-r):
    """
    snap = Snapshot(root)
    root = snap.fs.root  # a normalized path.
    
    if subfolder:
        assert subfolder.startswith(root) and subfolder != root
    
    data = {}
    for f, t in snap.fs.findall_files(subfolder or root):
        print(':i', _fs.relpath(f, root))
        data[f.removeprefix(root + '/')] = t
    
    if rebuild:
        snap.rebuild_snapshot(data)
    elif subfolder:
        snap.partial_update_snapshot(data, _fs.relpath(subfolder, root))
    else:
        snap.update_snapshot(data)
    
    if isinstance(snap.fs, FtpFileSystem):
        snap.fs.download_file(snap.snapshot_file, 'data/remote_snapshot.json')
    print(':t', 'done')


@cli
def fetch_remote_snapshot(root: str) -> None:
    fs = FtpFileSystem(root)
    fs.download_file(
        get_snapshot_file_for_target_root(root), 'data/remote_snapshot.json'
    )


@cli
def force_sync_snapshot(root_a: str, root_b: str) -> None:
    fs_b = FtpFileSystem(root_b)
    fs_b.upload_file(
        get_snapshot_file_for_target_root(root_a),
        get_snapshot_file_for_target_root(root_b)
    )


@cli
def sync_documents(root_a: str, root_b: str, dry_run: bool = False) -> None:
    """
    params:
        root_a: root path on the left side. usually "master".
        root_b: root path on the right side. usually "slave".
        dry_run (-d):
    """
    assert not root_a.startswith('ftp://') and root_b.startswith('ftp://')
    
    snap_a = Snapshot(root_a)
    snap_b = Snapshot(root_b)
    # fs_a = LocalFileSystem(root_a)
    # fs_b = FtpFileSystem(root_b)
    fs_a: LocalFileSystem = snap_a.fs
    fs_b: FtpFileSystem = snap_b.fs
    
    snap_full_a = Snapshot(fs_a).load_snapshot()
    snap_full_b = Snapshot(fs_b).load_snapshot()
    
    # decide snap_data_base
    snap_base_hash_a0, snap_base_time_a0 = \
        snap_full_a['base']['version'].split('-')
    snap_base_hash_b0, snap_base_time_b0 = \
        snap_full_b['base']['version'].split('-')
    if snap_base_hash_a0 == snap_base_hash_b0:
        print('same base snap', ':v4')
        snap_data_base = snap_full_a['base']['data']
    else:
        # note: we prefer assuming snap_full_b to be the old one.
        if snap_base_time_b0 <= snap_base_time_a0:
            print('use snap_b0 as base')  # use the "old" one.
            snap_data_base = snap_full_b['base']['data']
        else:
            print('use snap_a0 as base')
            snap_data_base = snap_full_a['base']['data']
    
    snap_data_a = snap_full_a['current']['data']
    snap_data_b = snap_full_b['current']['data']
    
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
                    print(':v5i', k, time_new, time_old)
                    # yield k, '<=?', time_old
            else:
                yield k, '+>', time_new
        for k, time_old in snap_old.items():
            if k not in snap_new:
                yield k, '->', time_old
    
    # noinspection PyTypeChecker
    def compare_changelists(
        changes_a: t.Dict[T.Key, t.Tuple[T.Movement, T.Time]],
        changes_b: t.Dict[T.Key, t.Tuple[T.Movement, T.Time]],
    ) -> t.Iterator[T.ComposedAction]:
        for k, (ma, ta) in changes_a.items():
            if k in changes_b:
                mb, tb = changes_b[k]
                if ma == '+>' or ma == '=>':
                    if mb == '+>' or mb == '=>':
                        if ta >= tb:
                            # b created/updated -> a created/updated
                            yield k, '=>?', ta
                        else:  # ta < tb
                            # a created/updated -> b created/updated
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
    
    # PERF: fast compare by version of current against base.
    changes_a = {
        k: (m, t_) for k, m, t_ in
        compare_new_to_old(snap_data_a, snap_data_base)
    }
    changes_b = {
        k: (m, t_) for k, m, t_ in
        compare_new_to_old(snap_data_b, snap_data_base)
    }
    final_changes = compare_changelists(changes_a, changes_b)
    
    # -------------------------------------------------------------------------
    
    if dry_run:
        i = 0
        table = [('index', 'left', 'action', 'right')]
        action_count = defaultdict(int)
        for k, m, _ in final_changes:
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
            action_count[m.rstrip('?')] += 1
        if len(table) > 1:
            print(table, ':r2')
            print(action_count, ':r2')
        else:
            print('no change', ':v3')
        return
    
    def apply_changes(changes: t.Iterator[T.ComposedAction]) -> T.SnapshotData:
        existed_dirs = set()
        for f in snap_data_base:
            d = ''
            for x in f.split('/')[:-1]:
                d += x + '/'
                existed_dirs.add(d)
        
        # snap_new = snap_data_base.copy()
        snap_new: T.SnapshotData = snap_data_base
        
        for k, m, t in changes:
            # resolve conflict
            if m.endswith('?'):  # '=>?', '<=?'
                assert m in ('=>?', '<=?')
                if m == '=>?':
                    _backup_conflict_file_b('{}/{}'.format(fs_b.root, k), t)
                else:
                    _backup_conflict_file_a('{}/{}'.format(fs_a.root, k))
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
            
            # TODO: how to remove empty dirs which have no files inside?
            # FIXME: how to sync modify time in `_update_file_a2b/b2a()`?
            if m in ('+>', '=>'):
                _make_dirs_b('{}/{}'.format(fs_b.root, k))
                _update_file_a2b(k)
                snap_new[k] = t
            elif m == '->':
                _delete_file_b('{}/{}'.format(fs_b.root, k))
                snap_new.pop(k)
            elif m in ('<+', '<='):
                _make_dirs_a('{}/{}'.format(fs_a.root, k))
                _update_file_b2a(k, t)
                snap_new[k] = t
            elif m == '<-':
                _delete_file_a('{}/{}'.format(fs_a.root, k))
                snap_new.pop(k)
            else:
                raise Exception(k, m, t)
        
        return snap_new
    
    _created_dirs_a = set()
    for p in snap_data_a:
        d = fs_a.root
        for x in p.split('/')[:-1]:
            d += '/' + x
            _created_dirs_a.add(d)
    _created_dirs_b = set()
    for p in snap_data_b:
        d = fs_b.root
        for x in p.split('/')[:-1]:
            d += '/' + x
            _created_dirs_b.add(d)
    
    def _make_dirs_a(filepath: str) -> None:
        i = filepath.rfind('/')
        dirpath = filepath[:i]
        if dirpath not in _created_dirs_a:
            fs_a.make_dirs(dirpath)
            _created_dirs_a.add(dirpath)
    
    def _make_dirs_b(filepath: str) -> None:
        i = filepath.rfind('/')
        dirpath = filepath[:i]
        if dirpath not in _created_dirs_b:
            fs_b.make_dirs(dirpath)
            _created_dirs_b.add(dirpath)
    
    _conflicts_dir = 'data/cache/conflicts/{}'.format(x := timestamp('ymd_hns'))
    _deleted_dir = 'data/cache/deleted/{}'.format(x)
    _fs.make_dir(_conflicts_dir)
    _fs.make_dir(_deleted_dir)
    
    def _backup_conflict_file_a(file: T.Path) -> None:
        file_i = file
        m, n, o = _fs.split(file_i, 3)
        file_o = '{}/{}.a.{}'.format(_conflicts_dir, n, o)
        _fs.copy_file(file_i, file_o, reserve_metadata=True)
        
    def _backup_conflict_file_b(file: T.Path, mtime: int) -> None:
        file_i = file
        m, n, o = _fs.split(file_i, 3)
        file_o = '{}/{}.b.{}'.format(_deleted_dir, n, o)
        fs_b.download_file(file_i, file_o, mtime)
    
    def _delete_file_a(file: T.Path) -> None:
        file_i = file
        m, n, o = _fs.split(file_i, 3)
        file_o = '{}/{}.a.{}'.format(_deleted_dir, n, o)
        _fs.move(file_i, file_o)
        # fs_a.remove(file)
    
    def _delete_file_b(file: T.Path) -> None:
        file_i = file
        m, n, o = _fs.split(file_i, 3)
        file_o = '{}/{}.b.{}'.format(_deleted_dir, n, o)
        data_i = fs_b.load(file_i)
        _fs.dump(data_i, file_o, 'binary')
        fs_b.remove(file_i)
    
    def _update_file_a2b(relpath: T.Path) -> None:
        file_i = '{}/{}'.format(fs_a.root, relpath)
        file_o = '{}/{}'.format(fs_b.root, relpath)
        fs_b.upload_file(file_i, file_o)
        
    def _update_file_b2a(relpath: T.Path, mtime: int) -> None:
        file_i = '{}/{}'.format(fs_b.root, relpath)
        file_o = '{}/{}'.format(fs_a.root, relpath)
        fs_b.download_file(file_i, file_o, mtime)
    
    snap_new = apply_changes(final_changes)
    
    if _fs.empty(_conflicts_dir):
        _fs.remove_tree(_conflicts_dir)
    else:
        print('found {} conflicts, see in {}'.format(
            len(_fs.find_file_names(_conflicts_dir)),
            _conflicts_dir
        ), ':v6')
    if _fs.empty(_deleted_dir):
        # _fs.remove_tree(_deleted_dir)
        pass
    else:
        print('deleted {} files, see in {}'.format(
            len(_fs.find_file_names(_deleted_dir)),
            _deleted_dir
        ), ':v8')
    
    print(':v3', 'lock snapshot')
    _delete_file_a(snap_a.snapshot_file)
    _delete_file_b(snap_b.snapshot_file)
    snap_a.rebuild_snapshot(snap_new)
    snap_b.rebuild_snapshot(snap_new)


if __name__ == '__main__':
    # pox src/file_sync_pro/main.py -h
    
    # pox src/file_sync_pro/main.py create_snapshot
    #   C:/Likianta/documents/gitbook/source-docs
    # pox src/file_sync_pro/main.py clone_project
    #   C:/Likianta/documents/gitbook/source-docs
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs
    
    # pox src/file_sync_pro/main.py update_snapshot
    #   C:/Likianta/documents/gitbook/source-docs
    # pox src/file_sync_pro/main.py update_snapshot
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs
    
    # pox src/file_sync_pro/main.py sync_documents
    #   C:/Likianta/documents/gitbook/source-docs
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs -d
    # pox src/file_sync_pro/main.py sync_documents
    #   C:/Likianta/documents/gitbook/source-docs
    #   ftp://172.20.128.123:2024/Likianta/documents/gitbook/source-docs
    cli.run()
