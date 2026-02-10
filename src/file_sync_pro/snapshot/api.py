import hashlib
import json
import os
import typing as t
from collections import defaultdict
from lk_utils import fs as fs0
from lk_utils import timestamp
from time import time
from ..filesys2 import FileSystem
from ..filesys2 import is_local_path
from ..filesys2.remote import FileSystem as RemoteFileSystem


class T:
    AbsPath = AnyPath = Path = str
    #   AbsPath: be noted this can be a local path, or remote path.
    #       for examples:
    #           C:/Likianta/documents/gitbook
    #           /storage/emulated/0/Likianta/documents/gitbook
    #       the remote abspath must start with '/'.
    #   AnyPath: abspaths, relpaths, regular slash separators (/), back
    #   slashes (\\), 'air://...' paths, 'ftp://...' paths... they are all
    #   allowed.
    Key = str  # a relpath
    Movement = t.Literal['+>', '=>', '->', '~>', '<+', '<=', '<-', '<~', '==']
    #   +>  add to right
    #   =>  overwrite to right
    #   ->  delete to right
    #   ~>  move to right
    #   <+  add to left
    #   <=  overwrite to left
    #   <-  delete to left
    #   <~  move to left
    #   ==  no change
    Time = int
    
    ComposedAction = t.Union[
        t.Tuple[Key, Movement, Time],
        t.Tuple[t.Tuple[Key, Key], t.Literal['~>', '<~'], Time],
    ]
    Nodes = t.Dict[Path, int]  # {relpath: modified_time, ...}
    
    SnapshotItem = t.TypedDict('SnapshotItem', {
        'version': str,  # `<hash>-<time>`
        'files'  : Nodes,
    })
    
    SnapshotFull = t.TypedDict('SnapshotFull', {
        'root'   : Path,
        'ignores': t.Union[t.List[Path], t.FrozenSet[Path]],
        #   the list type is for saving to ".json" file. frozenset is for
        #   speeding runtime.
        'base'   : SnapshotItem,
        'current': SnapshotItem,
    })


def create_snapshot(snap_file: T.AnyPath, source_root: str) -> None:
    """
    params:
        snap_file: can be inexistent file. if exists, will be overwritten.
            usually saved in `data/snapshots/<host>/<name>.json`.
    """
    assert is_local_path(snap_file)
    fs1 = FileSystem(source_root)
    root = fs1.root
    del source_root
    
    files = fs1.findall_nodes(root)
    full_data = {'root': fs1.url, 'ignores': []}  # noqa
    full_data['current'] = full_data['base'] = {
        'version': _make_version(files),
        'files'  : files,
    }
    fs0.dump(full_data, snap_file)

    
def rebuild_snapshot(snap_file: T.AnyPath):
    # assert fs0.exist(snap_file)
    create_snapshot(snap_file, fs0.load(snap_file)['root'])


def update_snapshot(snap_file: T.AnyPath):
    full_data = fs0.load(snap_file)
    fs1 = FileSystem(full_data['root'])
    root = fs1.root
    
    changed_files = fs1.findall_nodes(root)
    full_data['current'] = {
        'version': _make_version(changed_files),
        'files'  : changed_files,
    }
    fs0.dump(full_data, snap_file)


def sync_snapshot(
    snap_file_a: T.AnyPath,
    snap_file_b: T.AnyPath,
    dry_run: bool = False,
    no_doubt: bool = False,
    consider_moving: bool = False,
    manual_select_base_side: t.Literal['a', 'b'] = '',
) -> None:
    """
    params:
        dry_run (-d):
        consider_moving (-m):
        manual_select_base_side (-b):
            if set, suggest setting 'b'. it means that `snap_file_b` is -
            passive side.
    """
    snap_alldata_a = fs0.load(snap_file_a)
    snap_alldata_b = fs0.load(snap_file_b)
    
    def select_base_side() -> t.Tuple[str, T.Nodes]:
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
        return base['version'], base['files']
    
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
    snap_data_a = snap_alldata_a['current']['files']
    snap_data_b = snap_alldata_b['current']['files']
    
    # -------------------------------------------------------------------------
    
    # noinspection PyTypeChecker
    def compare_new_to_old(
        snap_new: T.Nodes, snap_old: T.Nodes
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
    }
    changes_b = {} if compare_version(
        snap_alldata_b['current']['version'], snap_ver_base,
    ) == 0 else {
        k: (m, t_)
        for k, m, t_ in compare_new_to_old(snap_data_b, snap_data_base)
    }
    
    final_changes = _compare_changelists(
        changes_a, changes_b, no_doubt, consider_moving
    )
    
    if dry_run:
        _preview_changes(final_changes)
    else:
        fs_a = FileSystem(snap_alldata_a['root'])
        fs_b = FileSystem(snap_alldata_b['root'])
        snap_data_new = _apply_changes(
            final_changes,
            snap_data_base,
            snap_data_a,
            snap_data_b,
            fs_a.core,
            fs_b.core,
            fs_a.root,
            fs_b.root,
        )
        print(':v3', 'lock snapshot')
        _lock_snapshot(snap_alldata_a, snap_data_new, snap_file_a)
        _lock_snapshot(snap_alldata_b, snap_data_new, snap_file_b)


def merge_snapshot(
    snap_file_a: T.AnyPath,
    snap_file_b: T.AnyPath,
    dry_run: bool = False,
    no_doubt: bool = False,
):
    """
    params:
        dry_run (-d):
    """
    snap_alldata_a = fs0.load(snap_file_a)
    snap_alldata_b = fs0.load(snap_file_b)
    
    files_a = frozenset(snap_alldata_a['current']['files'].keys())
    files_b = frozenset(snap_alldata_b['current']['files'].keys())
    changes_a = {
        k: ('+>', snap_alldata_a['current']['files'][k])
        for k in (files_a - files_b)
    }
    changes_b = {
        k: ('+>', snap_alldata_b['current']['files'][k])
        for k in (files_b - files_a)
    }
    # noinspection PyTypeChecker
    final_changes = _compare_changelists(changes_a, changes_b, no_doubt)
    
    if dry_run:
        _preview_changes(final_changes)
    else:
        fs_a = FileSystem(snap_alldata_a['root'])
        fs_b = FileSystem(snap_alldata_b['root'])
        snap_data_new = _apply_changes(
            final_changes,
            {},
            snap_alldata_a['current']['files'],
            snap_alldata_b['current']['files'],
            fs_a.core,
            fs_b.core,
            fs_a.root,
            fs_b.root,
        )
        print(':v3', 'lock snapshot')
        _lock_snapshot(snap_alldata_a, snap_data_new, snap_file_a)
        _lock_snapshot(snap_alldata_b, snap_data_new, snap_file_b)


# noinspection PyTypeChecker
def _compare_changelists(
    changes_a: t.Dict[T.Key, t.Tuple[T.Movement, T.Time]],
    changes_b: t.Dict[T.Key, t.Tuple[T.Movement, T.Time]],
    no_doubt: bool = False,
    consider_moving: bool = False,
) -> t.Iterator[T.ComposedAction]:
    
    if consider_moving:
        moved_keys = []
        
        def check_moving(changes_p: dict):
            minus_arrowed_items = defaultdict(list)
            #   {(name, time): [relpath, ...], ...}
            for k, (m, t) in changes_p.items():
                if m == '->':
                    minus_arrowed_items[(k.rsplit('/', 1)[-1], t)].append(k)
            if not minus_arrowed_items:
                print('no moved items')
                return
            
            # # preview
            # for i, (k, v) in enumerate(minus_arrowed_items.items()):
            #     if i > 10: break
            #     print(':v', 'x -> ...', i, k, v)
            # for k, (m, t) in changes_p.items():
            #     if m == '+>':
            #         print(':vi', k, m, t)
            #         if k.endswith('260203-171319-7854a0.jpg'):
            #             print(
            #                 ':v1',
            #                 minus_arrowed_items[
            #                     ('260203-171319-7854a0.jpg', 1770109999)
            #                 ],
            #                 (k, m, t)
            #             )
            #             assert (k.rsplit('/', 1)[-1], t) in minus_arrowed_items
            #             break
            # else:
            #     raise Exception('test failed: key not in "+>" list')
            
            for k, (m, t) in changes_p.items():
                if m == '+>':
                    if (x := (k.rsplit('/', 1)[-1], t)) in minus_arrowed_items:
                        y = minus_arrowed_items[x]
                        if len(y) == 1:
                            z = y[0]
                            moved_keys.append(k)
                            moved_keys.append(z)
                            yield (k, z), '~>', t
            
        yield from check_moving(changes_a)
        yield from ((x[0], '<~', x[2]) for x in check_moving(changes_b))
        resolved_moved_keys = frozenset(moved_keys)
    else:
        resolved_moved_keys = None
        
    for k, (ma, ta) in changes_a.items():
        if consider_moving and k in resolved_moved_keys:
            continue
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
        if consider_moving and k in resolved_moved_keys:
            continue
        if k not in changes_a:
            if mb == '+>':
                yield k, '<+', tb
            elif mb == '=>':
                yield k, '<=', tb
            else:  # mb == '->'
                yield k, '<-', tb


def _preview_changes(changes: t.Iterator[T.ComposedAction]) -> None:
    i = 0
    table = [('index', 'left', 'action', 'right')]
    action_count = defaultdict(int)
    for k, m, _ in changes:
        i += 1
        colored_key = '[{}]{}[/]'.format(
            'yellow' if '?' in m else
            'green' if '+' in m else
            'blue' if '=' in m else
            'green dim' if '~' in m else
            'red',  # '-' in m
            (k[0] if '~' in m else k).replace('[', '\\[')
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
                (colored_key, '+>', '[dim]<tocreate>[/]') if m == '+>' else
                (colored_key, '=>', '[dim]<outdated>[/]') if m == '=>' else
                (colored_key, '~>', '[dim]<movedto>[/]') if m == '~>' else
                ('[dim]<deleted>[/]', '->', colored_key) if m == '->' else
                ('[dim]<tocreate>[/]', '<+', colored_key) if m == '<+' else
                ('[dim]<outdated>[/]', '<=', colored_key) if m == '<=' else
                ('[dim]<movedto>[/]', '<~', colored_key) if m == '<~' else
                (colored_key, '<-', '[dim]<deleted>[/]')  # m == '<-'
            )
        ))
        action_count[m] += 1
    if len(table) > 1:
        print(table, ':r2')
        print(action_count, ':r2')
    else:
        print('no change', ':v4')


# noinspection PyTypeChecker
def _apply_changes(
    changes: t.Iterator[T.ComposedAction],
    snap_data_base: T.Nodes,
    snap_data_a: T.Nodes,
    snap_data_b: T.Nodes,
    fs_a: 'fs0',  # noqa
    fs_b: RemoteFileSystem,
    root_a: str,
    root_b: str,
) -> T.Nodes:
    print(root_a, root_b, ':li0')
    
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
    
    # def delete_dir_a(dirpath: T.AbsPath) -> None:
    #     if fs_a.exist(dirpath):
    #         fs_a.remove_tree(dirpath)
    #
    # def delete_dir_b(dirpath: T.AbsPath) -> None:
    #     if fs_b.exist(dirpath):
    #         fs_b.remove_tree(dirpath)
    #
    # def make_dir_a(dirpath: T.AbsPath) -> None:
    #     if dirpath not in _created_dirs_a:
    #         if not fs_a.exist(dirpath):
    #             fs_a.make_dir(dirpath)
    #         _created_dirs_a.add(dirpath)
    #
    # def make_dir_b(dirpath: T.AbsPath) -> None:
    #     if dirpath not in _created_dirs_b:
    #         if not fs_b.exist(dirpath):
    #             fs_b.make_dir(dirpath)
    #         _created_dirs_b.add(dirpath)
    
    def make_dirs_a(filepath: str) -> None:
        i = filepath.rfind('/')
        dirpath = filepath[:i]
        if dirpath not in _created_dirs_a:
            if not fs_a.exist(dirpath):
                fs_a.make_dirs(dirpath)
            _created_dirs_a.add(dirpath)
    
    def make_dirs_b(filepath: str) -> None:
        i = filepath.rfind('/')
        dirpath = filepath[:i]
        if dirpath not in _created_dirs_b:
            if not fs_b.exist(dirpath):
                fs_b.make_dirs(dirpath)
            _created_dirs_b.add(dirpath)
    
    _conflicts_dir = 'data/conflicts/{}'.format(timestamp('ymd_hns'))
    fs0.make_dir(_conflicts_dir)
    
    def backup_conflict_file_a(file: T.Path) -> None:
        file_i = file
        m, n, o = fs0.split(file_i, 3)
        file_o = '{}/{}.a.{}'.format(_conflicts_dir, n, o)
        fs0.copy_file(file_i, file_o, reserve_metadata=True)
    
    def backup_conflict_file_b(file: T.Path, mtime: int) -> None:
        file_i = file
        m, n, o = fs0.split(file_i, 3)
        file_o = '{}/{}.b.{}'.format(_conflicts_dir, n, o)
        _download_file(file_i, file_o, mtime)
    
    def delete_file_a(file: T.Path) -> None:
        if fs_a.exist(file):
            fs_a.remove_file(file)
    
    def delete_file_b(file: T.Path) -> None:
        if fs_b.exist(file):
            fs_b.remove_file(file)
    
    def move_file_a(relsrc: T.Path, reldst: T.Path) -> None:
        file_i = '{}/{}'.format(root_a, relsrc)
        file_o = '{}/{}'.format(root_a, reldst)
        fs_a.move_file(file_i, file_o)
    
    def move_file_b(relsrc: T.Path, reldst: T.Path) -> None:
        file_i = '{}/{}'.format(root_b, relsrc)
        file_o = '{}/{}'.format(root_b, reldst)
        fs_b.move_file(file_i, file_o)
    
    def update_file_a2b(relpath: T.Path) -> None:
        file_i = '{}/{}'.format(root_a, relpath)
        file_o = '{}/{}'.format(root_b, relpath)
        _upload_file(file_i, file_o, fs0.filetime(file_i))
    
    def update_file_b2a(relpath: T.Path, mtime: int) -> None:
        file_i = '{}/{}'.format(root_b, relpath)
        file_o = '{}/{}'.format(root_a, relpath)
        _download_file(file_i, file_o, mtime)
    
    def _download_file(file_i: T.Path, file_o: T.Path, mtime: T.Time):
        data = fs_b.load(file_i, 'binary')
        fs_a.dump(data, file_o, 'binary')
        os.utime(file_o, (mtime, mtime))
    
    def _upload_file(
        file_i: T.Path, file_o: T.Path, mtime: T.Time
    ) -> None:
        data = fs_a.load(file_i, 'binary')
        fs_b.dump(data, file_o, 'binary')
        fs_b.client.exec(
            'os.utime(file, (mtime, mtime))', file=file_o, mtime=mtime
        )
    
    # snap_new = snap_data_base.copy()
    snap_new: T.Nodes = snap_data_base
    
    for k, m, t in changes:
        # resolve conflict
        if m.endswith('?'):
            assert m in ('=>?', '<=?')
            if m == '=>?':
                backup_conflict_file_b('{}/{}'.format(root_b, k), t)
            else:
                backup_conflict_file_a('{}/{}'.format(root_a, k))
            m = m[:-1]
        # assert '?' not in m
        
        colored_key = '[{}]{}[/]'.format(
            'green' if '+' in m else
            'blue' if '=' in m else
            'green dim' if '~' in m else
            'red',  # '-' in m
            (k[0] if '~' in m else k).replace('[', '\\[')
        )
        # noinspection PyStringFormat
        print(':ir', '{} {} {}'.format(
            *(
                (colored_key, '+>', '[dim]<tocreate>[/]') if m == '+>' else
                (colored_key, '=>', '[dim]<outdated>[/]') if m == '=>' else
                (colored_key, '~>', '[dim]<movedto>[/]') if m == '~>' else
                ('[dim]<deleted>[/]', '->', colored_key) if m == '->' else
                ('[dim]<tocreate>[/]', '<+', colored_key) if m == '<+' else
                ('[dim]<outdated>[/]', '<=', colored_key) if m == '<=' else
                ('[dim]<movedto>[/]', '<~', colored_key) if m == '<~' else
                (colored_key, '<-', '[dim]<deleted>[/]')  # m == '<-'
            )
        ))
        
        if m in ('+>', '=>'):
            make_dirs_b('{}/{}'.format(root_b, k))
            update_file_a2b(k)
            snap_new[k] = t
        elif m == '->':
            delete_file_b('{}/{}'.format(root_b, k))
            snap_new.pop(k)
        elif m == '~>':
            ka, kb = k
            make_dirs_b('{}/{}'.format(root_b, ka))
            move_file_b(kb, ka)
            snap_new[ka] = t
        elif m in ('<+', '<='):
            make_dirs_a('{}/{}'.format(root_a, k))
            update_file_b2a(k, t)
            snap_new[k] = t
        elif m == '<-':
            delete_file_a('{}/{}'.format(root_a, k))
            snap_new.pop(k)
        elif m == '<~':
            kb, ka = k
            make_dirs_a('{}/{}'.format(root_a, kb))
            move_file_a(ka, kb)
            snap_new[kb] = t
        else:
            raise Exception(k, m, t)
    
    if fs0.empty(_conflicts_dir):
        fs0.remove_tree(_conflicts_dir)
    else:
        print('found {} conflicts, see in {}'.format(
            len(fs0.find_file_names(_conflicts_dir)),
            _conflicts_dir
        ), ':v6')
    
    return snap_new


def _hash_data(data):
    return hashlib.md5(
        json.dumps(data, sort_keys=True).encode()
        #                ~~~~~~~~~~~~~~ recursively sort.
    ).hexdigest()


def _make_version(files_data):
    return '{}-{}'.format(_hash_data(files_data), int(time()))


def _lock_snapshot(full_data, files_data, output_file):
    full_data['base'] = full_data['current'] = {
        'version': _make_version(files_data),
        'files': files_data,
    }
    fs0.dump(full_data, output_file)
