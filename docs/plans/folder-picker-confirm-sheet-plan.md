# Implementation Plan: Interactive Folder Picker in Offline Confirm Sheet

## Spec & Global Constraints
- Spec authority: `GLOSSARY.md` (`Offline Confirm Sheet`, `Target Virtual Path`) and `docs/adr/0001-companion-apk-process-text-offline-download.md`.
- OpenList Directory Listing API:
  - Endpoint: `POST http://<host>:<port>/api/fs/list`
  - Headers: `Content-Type: application/json; charset=utf-8`, `Authorization: <sanitizedToken>`
  - Request JSON: `{"path":"<dirPath>","password":"","page":1,"per_page":0,"refresh":false}`
  - Response JSON: `{"code":200,"message":"success","data":{"content":[{"name":"影视","is_dir":true,...},{"name":"file.mp4","is_dir":false,...}]}}`
- Auto-heal requirement: just like `submitOfflineDownload`, if `listDirectories` receives `code != 200` and `isStorageError()` is true (e.g. `storage not init`), it must automatically call `reloadAllStorage(baseUrl, sanitizedToken, timeoutMs)`, wait 800ms, and retry `executeListDirectories` once.
- Path normalization rules:
  - `normalizeVirtualPath(String path)`: null/empty -> `"/"`; ensures leading `"/"`; collapses duplicate slashes (`"//" -> "/"`); ensures trailing `"/"` (e.g. `"/115/影视"` -> `"/115/影视/"`, `"/"` -> `"/"`).
  - `parentVirtualPath(String path)`: returns normalized parent directory path (e.g. `"/115/影视/"` -> `"/115/"`, `"/115/"` -> `"/"`, `"/"` -> `"/"`).
  - `joinVirtualPath(String parentPath, String dirName)`: joins `parentPath` and `dirName` into a normalized directory path ending with `"/"` (e.g. `("/115/", "影视")` -> `"/115/影视/"`).
- Zero third-party library dependencies: `OfflineHelperCore.java` must use only pure Java standard library (`java.net.*`, `java.util.*`, `java.io.*`) so it runs in both JVM tests and Android DEX. `ProcessTextActivity.java` must use only standard Android framework UI (`android.app.*`, `android.widget.*`, `android.view.*`).

## Task 1: Add OpenList directory listing API, JSON parser, path helpers, and unit tests in OfflineHelperCore

### Files Owned
- `companion-apk/src/io/openlist/helper/OfflineHelperCore.java`
- `companion-apk/test/io/openlist/helper/OfflineHelperCoreTest.java`

### Requirements
1. In `companion-apk/src/io/openlist/helper/OfflineHelperCore.java`:
   - Add path helper methods:
     - `public static String normalizeVirtualPath(String path)`
     - `public static String parentVirtualPath(String path)`
     - `public static String joinVirtualPath(String parentPath, String childDirName)`
   - Add `public static String buildListDirectoryPayload(String path)`:
     - Normalizes `path` (for `/api/fs/list`, root is `"/"`, non-root strips trailing slash or keeps clean path as OpenList accepts both, e.g. `"/115"` or `"/115/影视"`), returns `{"path":"...","password":"","page":1,"per_page":0,"refresh":false}`.
   - Add `public static class DirListResult`:
     - Fields: `public final boolean success`, `public final int code`, `public final String message`, `public final String currentPath`, `public final List<String> directories`, `public final String rawBody`.
     - Helper `public boolean isStorageError()` (checks `!success` and `message`/`rawBody` case-insensitively containing `"storage"`, `"not init"`, or `"disabled"`).
   - Add `public static List<String> parseDirectoryNamesFromListJson(String jsonBody)`:
     - Extracts all object blocks inside `"content":[ ... ]` (or across the JSON response) where `"is_dir"\s*:\s*true` and extracts their `"name"\s*:\s*"((?:\\.|[^"\\])*)"` value (unescaped via `unescapeJson`), returning a sorted or order-preserved deduplicated `List<String>` of folder names, excluding files where `"is_dir":false`.
   - Add `public static DirListResult listDirectories(String path, OfflineConfig config, int timeoutMs)` and `public static DirListResult listDirectories(String baseUrl, String token, String path, int timeoutMs)`:
     - Calls `POST <baseUrl>/api/fs/list` with `Authorization: <sanitizedToken>` and `buildListDirectoryPayload(path)`.
     - If `!res.success && res.isStorageError()`, calls `reloadAllStorage(baseUrl, sanitizedToken, timeoutMs)`, sleeps 800ms, and retries once.
     - Parses HTTP status, JSON `code`, `message`, and directory names via `parseDirectoryNamesFromListJson(responseBody)`.
2. In `companion-apk/test/io/openlist/helper/OfflineHelperCoreTest.java`:
   - Add unit tests following TDD:
     - `testVirtualPathHelpers`: verifies `normalizeVirtualPath`, `parentVirtualPath`, and `joinVirtualPath` across `"/"`, `"/115"`, `"/115/影视/"`, `"115/动漫"`.
     - `testParseDirectoryNamesFromListJson`: verifies parsing a real OpenList `/api/fs/list` JSON response containing both directories (`"is_dir":true`) and files (`"is_dir":false`), including Chinese names (`"云下载"`, `"影视"`) and escaped characters.
     - `testListDirectoriesMockHttpAndAutoHeal`: verifies `listDirectories` against a local `HttpServer` (including initial `storage not init` error triggering `/api/admin/storage/load_all` and succeeding on retry).
3. Run `javac` + `java` on `OfflineHelperCoreTest` to verify all tests pass with pristine output.

## Task 2: Add interactive folder browser & preset path chips to ProcessTextActivity and update docs

### Files Owned
- `companion-apk/src/io/openlist/helper/ProcessTextActivity.java`
- `GLOSSARY.md`
- `docs/adr/0001-companion-apk-process-text-offline-download.md`
- `README.md`
- `OpenList-Magisk/README.md`

### Requirements
1. In `companion-apk/src/io/openlist/helper/ProcessTextActivity.java`:
   - In the target virtual path section of `showOfflineConfirmSheet`:
     - Place `pathEditText` and a `"📁 选择目录"` (`Button`) side-by-side in a horizontal `LinearLayout` so the user can either edit text or tap `"📁 选择目录"` to browse folders interactively.
     - Below that row, render a `HorizontalScrollView` containing clickable quick-select path chips from `config.presetPaths` (plus any recently selected path) so common folders like `/115/影视/` and `/115/` can be selected with a single tap.
   - Implement `private void showDirectoryPickerDialog(String initialPath, OfflineHelperCore.OfflineConfig config, EditText targetPathEditText)`:
     - Opens a clean bottom-sheet `Dialog` (or modal dialog) titled `"选择保存文件夹"`:
       - Displays the current browsing path (`TextView`, e.g. `当前路径: /115/影视/`).
       - Action bar row with `"⬆️ 上级目录"` button (navigates to `OfflineHelperCore.parentVirtualPath(currentBrowsePath)`) and `"🏠 根目录 (/)"` button (navigates to `"/"`).
       - A scrollable list (`LinearLayout` inside `ScrollView`) of subdirectories fetched asynchronously on a background thread via `OfflineHelperCore.listDirectories(currentBrowsePath, config, 10000)`.
       - While loading, shows `"⏳ 正在读取目录..."`; if an error occurs, shows `"❌ 读取失败: <message>"` with a `"🔄 重试"` button; if the folder has no subfolders, shows `"（当前目录下无子文件夹，可直接点击下方按钮选择此目录）"`.
       - Each subfolder item is rendered as a clickable row `"📁 <dirName>"` that drills down into `OfflineHelperCore.joinVirtualPath(currentBrowsePath, dirName)` and loads its subdirectories.
       - Bottom button row: `"取消"` and `"✅ 选择当前目录"` (which sets `targetPathEditText.setText(OfflineHelperCore.normalizeVirtualPath(currentBrowsePath))`, adds it to `config.presetPaths` if not already present, and dismisses the picker dialog).
   - Ensure any active picker dialog is also dismissed cleanly in `onDestroy()` to prevent window leaks.
2. Update `GLOSSARY.md`, `docs/adr/0001-companion-apk-process-text-offline-download.md`, `README.md`, and `OpenList-Magisk/README.md` to document the interactive folder browser (`POST /api/fs/list`) and quick preset path selection in the `Offline Confirm Sheet`.
3. Run `bash companion-apk/build-apk.sh` and `bash tests/test_module_scripts.sh` to verify the APK compiles, signs, and all tests pass.
