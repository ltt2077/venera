# Venera Glass 1.7.7: backup audit

Compared with upstream `venera-app/venera` master at
`a0eba914f4c2a84ac1bc925adec2baabe920b9be` and this fork's Glass 1.7.6 at
`ca097ae1738d6d2467921a6807286f7911aa0ea5`.

## Findings and fixes

| Data | Glass 1.7.6 manual export / import | Glass 1.7.7 |
| --- | --- | --- |
| Reading history and image favorites | Included in `history.db` | Included; online SQLite snapshot also includes committed WAL pages |
| Local favorites | Included in `local_favorite.db` | Included; validated before replacing live databases |
| Cookies and comic source scripts/data | Included | Included; restore reuses the cookie jar held by existing network clients |
| Liquid glass toggle and all appearance parameters | Included and imported as ordinary settings | Included and imported |
| WebDAV/Alist/Quark profiles, credentials, priority, enabled flags | Exported in `appdata.json`, but silently excluded during import | Restored by manual import |
| Default and active profile, failover and sync mode | Exported, but silently excluded during import | Restored by manual import |
| Automatic sync switch | Missing: stored in `implicitData.json`, outside the original archive | Preserved in optional `venera_glass.json` |
| Downloaded/local comic image files and image cache | Outside the app-data archive | Still outside this archive; back up comic storage separately |

Cloud sync intentionally transfers portable settings, history, favorites,
cookies and source data while keeping the receiving device's cloud connections
and device identity. Cloud provider credentials and automatic-sync flags are
included only in a **manual full export**. Original cookies/source credentials
remain part of the original portable backup behavior.

Manual backups contain credentials and cookies in a ZIP file, without encryption.

## Compatibility

The original entries keep their names and formats: `appdata.json`, `history.db`,
`local_favorite.db`, `cookie.db` and `comic_source/*`. No database schema migration
or enclosing archive wrapper is introduced. The one optional extra entry,
`venera_glass.json`, contains format version 1 and the two automatic-sync flags.

| Direction | Expected behavior from source and fixture checks |
| --- | --- |
| Original 1.6.3 export → Glass 1.7.7 | Original settings and data import; a legacy WebDAV connection is prepared for named-profile migration |
| Glass 1.7.6 full export → Glass 1.7.7 | Cloud settings that were already present can now be restored; missing automatic-sync flags cannot be recovered from the old archive |
| Glass 1.7.7 full export → Glass 1.7.7 | Added appearance/cloud settings and automatic-sync switches round trip |
| Glass 1.7.7 export → original 1.6.3 | Original importer can read the original entries and ignores the optional extension; the original app does not implement Glass/cloud-profile features |
| Glass → original → Glass, with an intervening export in the original app | Basic data retains the original format; the original exporter does not include the extra metadata, so automatic-sync flags are lost |

Automatic filenames remain `{epoch-day}-{numeric-revision}.venera`. Successful
uploads retain the latest file for each of up to ten backup days. This preserves
the original client's single-file-per-day convention and avoids its lexical
ordering of multiple same-day revisions. New uploads finish before any old
backup is removed. Manually named `.venera` files are not pruned.

## Performance and sync changes

- Build each main tab only on its first visit, preserve its state, and mute
  inactive Flutter tickers. Existing page transition and glass appearance stay.
- Debounce automatic sync for two seconds and honor the selected sync mode.
  Settings/source saves no longer unconditionally upload when auto sync is off.
- Apply custom sync exclusions only to cloud imports; a manual full restore
  restores those portable settings as well.
- Pin CI and release workflows to Flutter 3.41.4; the old installer could not
  resolve the `>=3.41.0` SDK constraint as an exact Flutter version.
- Generate the filtered sync JSON on export; stop writing a redundant
  `syncdata.json` on every settings save.
- Sort remote revisions numerically and reuse the remote listing on upload.
- Track unsynced edits. Stop smart sync on divergent local/remote edits instead
  of downloading over local changes or failing over to a different cloud.
- Explicit downloads can restore older/equal revisions; smart downloads do not
  pass through a second version gate that silently skips the chosen archive.
- Keep temporary exports/downloads/imports isolated and clean them up on failure.
- Reject a Quark upload lacking a content upload URL instead of claiming success
  after sending only upload metadata. Quark's provider still uses an unofficial
  API and has not been verified against a live account in this iteration.

## Validation and remaining limits

`tool/check_backup_core.dart` runs 26 standalone checks against the production
format, restore-policy, upload-retention and SQLite snapshot helpers. Checks
include actual SQLite WAL commits, a ZIP layout fixture, failed uploads, cleanup
errors, excluded credentials, old backups, metadata, numeric sorting and sync
conflicts. These checks passed locally using Dart 3.11.1 in AOT mode.

Flutter regression tests additionally cover lazy mounting, retained tab state
and inactive tickers. The GitHub workflow runs `flutter test` and analysis of the
changed libraries. Both passed on the first implementation commit; a final
rerun also covers the manual-restore exclusion fix and workflow version pins. Local full Flutter tooling was blocked when its startup
attempted a cloud metadata lookup unrelated to this repository; that path was
stopped. No Android/iOS/macOS/Windows installable build, on-device frame-rate
measurement, live WebDAV/Alist/Quark transfer, or full original-app UI round trip
has been verified here. Do not describe those checks as passed based solely on
the standalone format tests.

Restore preflight validates JSON and the included databases before replacement.
It does not provide a transaction spanning every database, source script and
settings file; an operating-system or disk failure during replacement can still
leave a partially applied restore.
