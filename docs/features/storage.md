# Storage

Settings → Storage shows how much space the app uses and lets the person browse, copy, import and delete files in the
app's own sandbox folders. Nothing here reaches outside the sandbox.

## The one rule

**The live library database is read-only.** SwiftData keeps `default.store` (+ `-wal`, `-shm`) open; a deleted, renamed or
half-copied store loses the whole library. `StoragePolicy` decides what is live and every change in `StorageBrowser` asks it
first. The policy is pure (no file access) and unit-tested; the browser is tested on a real temporary folder.

Live data is: SwiftData / SQLite store files (`*.store*`, `*.sqlite*`, `*.db*`), Core Data support folders
(`.<name>_SUPPORT`, `default_ckassets`) and anything inside them. Live data can be listed, sized and copied *out* (the copy
is an ordinary file); it can never be deleted, renamed, replaced or have files added next to it. The roots themselves cannot
be deleted. For a consistent backup the person uses Export in Settings (a copied `.store` may miss what is still in the `-wal`).

## Layout

```
Features/Storage/
  StoragePolicy.swift       StorageRoot (4 sandbox roots) + StoragePolicy (protection, names, unique names, containment)
  StorageBrowser.swift      list / totalSize / delete / createFolder / rename / copy / importFile, StorageItem, StorageError
  StorageModel.swift        StorageFolderModel (@Observable, work off the main thread), StorageClipboard, StorageOverview
  StorageView.swift         usage per root + links into the roots
  StorageFolderView.swift   one folder: rows, context menu (Copy, Share, Rename, Delete), toolbar (Paste, New Folder, Import)
```

## Path safety

`StorageBrowser` resolves symlinks on its root and on every path it is given, then requires the path to stay inside the
root (`StoragePolicy.components(of:below:)`; a sibling that shares a prefix is outside). `..` and symlinks cannot escape. A
folder cannot be copied into itself. Names must be one plain path component (no `/`, `..`, control characters; ≤ 255 bytes).

## Behavior

- Copy keeps the original and picks a free name (`a 2.txt`, `a 3.txt`); the clipboard is shared by every folder screen so a
  copy can be pasted into another folder. Import brings a picked document into the current folder (security-scoped).
- A copy of a database dropped into a normal folder (a backup) is allowed; dropping one at the top of a root, beside the
  real store, is not.
- Sizes of folders are totals, measured off the main thread.

## Tests

`StoragePolicyTests` (names, protection, unique names, containment) and `StorageBrowserTests` (listing, protection of the
store and its `-wal`, symlink escape, copy/rename/delete/import, copy into itself). `LocalizationTests` covers the Arabic
strings, including every `StorageError.message`.
