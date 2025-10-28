
This folder structure:

```
.
|= <host_name>
   |- <snapshot_file>
   |- ...
|= ...
```

`<host_name>` is computer name in kebab-case form, for example "maria-personal-computer".

`<snapshot_file>` is ".json" file, also named in kebab-case form.

Snapshot file can be created by:

```shell
pox -m file_sync_pro create_snapshot data/snapshots/<host_name>/<snapshot_file> <target_path>

# for example
pox -m file_sync_pro create_snapshot data/snapshots/likianta-rider-r2/gitbook-source-docs.json C:/Likianta/documents/gitbook/source-docs
```
