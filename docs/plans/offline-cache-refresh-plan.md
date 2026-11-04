# Implementation Plan: Post-Offline Directory Cache Refresh & Folder Picker Force Refresh

## Spec & Global Constraints
- Spec authority: `GLOSSARY.md` (`Offline Confirm Sheet`, `Target Virtual Path`, `Interactive Folder Browser`) and `docs/adr/0001-companion-apk-process-text-offline-download.md`.
- Problem Statement:
  1. When OpenList executes a `115 Open` offline download directly into a 115 storage mount (`TempDir == DstDirPath`), `DownloadTask.Run()` completes without invalidating or refreshing OpenList's in-memory `Cache.dirCache` for `DstDirPath`. Consequently, newly downloaded files/folders do not appear in the OpenList Web UI, WebDAV clients, or the companion folder picker until the cache expires or the user manually clicks Refresh (`POST /api/fs/list` with `"refresh": true`).
  2. In the companion APK's `Interactive Folder Browser`, tapping the `"🔄 刷新"` button previously called `listDirectories` with `"refresh": false`, hitting OpenList's stale directory cache instead of forcing a refresh.
- Solution Architecture (Agreed in Grill Session):
  - **Q1 (C)**: Solve cache staleness for both the OpenList Web UI / WebDAV file list and the Companion APK folder picker by issuing `POST /api/fs/list` with `"refresh": true` on the target virtual path.
  - **Q2 (Option 1 - Dual Refresh on Submit)**: After `add_offline_download` succeeds, trigger an immediate directory cache refresh (`refresh: true`) and a short-delayed follow-up refresh (~1500ms, detached background thread in `ProcessTextActivity`) so both instant 115 cloud offline hits and slightly delayed cloud completions immediately populate OpenList's `Cache.dirCache`.
  - **Q3 (Yes)**: In `Interactive Folder Browser`, normal navigation (`loadDirectoryIntoPicker` on initial open, subfolder drill-down, parent, root) uses `refresh = false` for fast cached browsing, while tapping `"🔄 刷新"` explicitly passes `refresh = true` to force OpenList to bypass and update its directory cache.

## Task 1: Support `refresh` flag in `OfflineHelperCore` directory listing & post-offline cache refresh

### Files Owned
- `companion-apk/src/io/openlist/helper/OfflineHelperCore.java`
- `companion-apk/test/io/openlist/helper/OfflineHelperCoreTest.java`

### Requirements
1. In `companion-apk/src/io/openlist/helper/OfflineHelperCore.java`:
   - Add overload `public static String buildListDirectoryPayload(String path, boolean refresh)` and keep `buildListDirectoryPayload(String path)` delegating to `buildListDirectoryPayload(path, false)`.
   - Add overloads for `listDirectories` with `boolean refresh`:
     - `public static DirListResult listDirectories(String path, OfflineConfig config, boolean refresh, int timeoutMs)`
     - `public static DirListResult listDirectories(String baseUrl, String token, String path, boolean refresh, int timeoutMs)`
     - Keep existing 3-arg and 4-arg `listDirectories` methods delegating with `refresh = false` for backward compatibility.
   - Add `public static boolean refreshDirectoryCache(String path, OfflineConfig config, int timeoutMs)` and `public static boolean refreshDirectoryCache(String baseUrl, String token, String path, int timeoutMs)` which call `listDirectories(..., path, true, timeoutMs)` and return `res.success`.
   - In `submitOfflineDownload(String baseUrl, String token, List<String> urls, String path, String tool, String deletePolicy, int timeoutMs)`:
     - When `res.success` is `true`, immediately invoke `refreshDirectoryCache(baseUrl, sanitizedToken, path, timeoutMs)` (best-effort, never failing or overwriting `res` if the refresh call itself errors) so the initial cache invalidation happens synchronously as part of successful offline task submission.
2. In `companion-apk/test/io/openlist/helper/OfflineHelperCoreTest.java`:
   - Add unit tests following TDD:
     - Verify `buildListDirectoryPayload(path, true)` emits `"refresh":true` and `buildListDirectoryPayload(path, false)` / `buildListDirectoryPayload(path)` emits `"refresh":false`.
     - Verify `listDirectories(..., true, timeoutMs)` and `refreshDirectoryCache(...)` send `"refresh":true` to `/api/fs/list`.
     - Verify `submitOfflineDownload` automatically triggers a `POST /api/fs/list` request with `"refresh":true` for the target path upon successful `add_offline_download`, and still returns `res.success == true` even if `/api/fs/list` is not registered or fails.

## Task 2: Wire delayed follow-up refresh and folder picker force-refresh in `ProcessTextActivity` & update docs

### Files Owned
- `companion-apk/src/io/openlist/helper/ProcessTextActivity.java`
- `GLOSSARY.md`
- `docs/adr/0001-companion-apk-process-text-offline-download.md`
- `README.md`
- `OpenList-Magisk/README.md`

### Requirements
1. In `companion-apk/src/io/openlist/helper/ProcessTextActivity.java`:
   - In `showOfflineConfirmSheet` submit button handler:
     - When `submitOfflineDownload` succeeds (`res.success` is `true`), spawn a detached background thread that sleeps `1500ms` and calls `OfflineHelperCore.refreshDirectoryCache(finalTargetPath, config, 10000)` to catch 115 cloud offline tasks that finish within 1~2 seconds after submission, ensuring Web UI and WebDAV see the new files without manual refresh.
   - In `showDirectoryPickerDialog` / `loadDirectoryIntoPicker`:
     - Add `boolean forceRefresh` parameter to `loadDirectoryIntoPicker(..., boolean forceRefresh)`.
     - Pass `forceRefresh = false` for initial load, `"⬆️ 上级目录"`, `"🏠 根目录 (/)"`, subfolder item clicks, and fallback root button.
     - Pass `forceRefresh = true` when the user clicks `"🔄 刷新"` (`refreshBtn`) or `"🔄 重试"` (`retryBtn`), calling `OfflineHelperCore.listDirectories(normalized, config, forceRefresh, 10000)`.
2. Update `GLOSSARY.md`, `docs/adr/0001-companion-apk-process-text-offline-download.md`, `README.md`, and `OpenList-Magisk/README.md` to document the automatic directory cache refresh (`POST /api/fs/list` with `refresh: true`) after offline download submission and the force-refresh button in the folder picker.
