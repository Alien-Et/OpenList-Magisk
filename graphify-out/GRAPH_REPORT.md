# Graph Report - openlist  (2026-11-06)

## Corpus Check
- 23 files · ~22,756 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 8 file(s) not represented in the graph (top: (none) 4, .prop 1, .apk 1)

## Summary
- 291 nodes · 513 edges · 19 communities (15 shown, 4 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 28 edges (avg confidence: 0.91)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `34f1ebeb`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Implementation Plan: 115 Storage Menu Visibility Gate & Revert SQLite WAL Patch from Upstream PR
- HTTP Networking & Data Models
- Domain Concepts & CI Pipeline
- Offline Helper Core Unit Tests
- Magnet Parsing & Config Core
- Daemon Service & Token Bridge
- Module Full Uninstallation
- Module Script Test Suite
- Interactive Volume Key Installer
- User Data Uninstallation
- Companion APK Build Pipeline
- Action Toggle Service Controller
- CLAUDE.md
- steps
- .main
- Implementation Plan: Interactive Folder Picker in Offline Confirm Sheet
- ProcessTextActivity

## God Nodes (most connected - your core abstractions)
1. `OfflineHelperCoreTest` - 27 edges
2. `OfflineHelperCore` - 25 edges
3. `ProcessTextActivity` - 18 edges
4. `OfflineConfig` - 15 edges
5. `log()` - 9 edges
6. `main()` - 8 edges
7. `steps` - 7 edges
8. `sync_companion_apk_and_config()` - 7 edges
9. `main()` - 7 edges
10. `main()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Spec & Global Constraints` --references--> `ProcessTextActivity`  [INFERRED]
  docs/plans/companion-menu-visibility-plan.md → companion-apk/src/io/openlist/helper/ProcessTextActivity.java
- `Requirements` --references--> `OfflineHelperCoreTest`  [INFERRED]
  docs/plans/companion-menu-visibility-plan.md → companion-apk/test/io/openlist/helper/OfflineHelperCoreTest.java
- `Step: Build OpenListHelper Companion APK` --implements--> `Companion APK (OpenListHelper)`  [INFERRED]
  .github/workflows/1.yml → GLOSSARY.md
- `Spec & Global Constraints` --references--> `ProcessTextActivity`  [INFERRED]
  docs/plans/offline-cache-refresh-plan.md → companion-apk/src/io/openlist/helper/ProcessTextActivity.java
- `Task 2: Wire delayed follow-up refresh and folder picker force-refresh in `ProcessTextActivity` & update docs` --references--> `ProcessTextActivity`  [INFERRED]
  docs/plans/offline-cache-refresh-plan.md → companion-apk/src/io/openlist/helper/ProcessTextActivity.java

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Browser Text Selection to 115 Cloud Offline Download Flow** — glossary_text_selection_menu, glossary_offline_confirm_sheet, glossary_companion_apk, glossary_openlist_daemon, glossary_offline_engine [EXTRACTED 1.00]
- **Automated Magisk Module Build and Release Pipeline** — github_workflows_1_build_magisk_module, github_workflows_1_step_build_companion_apk, github_workflows_1_step_sync_binaries, github_workflows_1_step_unit_tests [EXTRACTED 1.00]
- **Root Daemon to Sandbox Config and Token Synchronization** — glossary_openlist_daemon, glossary_offline_config, docs_adr_0001_companion_apk_process_text_offline_download_sandbox_token_bridge, openlist_magisk_readme_offline_config_specification [EXTRACTED 1.00]

## Communities (19 total, 4 thin omitted)

### Community 0 - "Implementation Plan: 115 Storage Menu Visibility Gate & Revert SQLite WAL Patch from Upstream PR"
Cohesion: 0.22
Nodes (8): Files Owned, Files Owned, Implementation Plan: 115 Storage Menu Visibility Gate & Revert SQLite WAL Patch from Upstream PR, Requirements, Requirements, Spec & Global Constraints, Task 1: Gate Companion Menu Visibility on Added & Enabled 115 Storage, Task 2: Revert SQLite WAL Concurrency Self-Healing & Log Tuning (ADR 0002) from Upstream PR Branch

### Community 2 - "Domain Concepts & CI Pipeline"
Cohesion: 0.10
Nodes (20): ADR 0001: Companion APK PROCESS_TEXT Offline Download, Workflow: Build OpenList Magisk Module, Step: Build OpenListHelper Companion APK, Step: Sync OpenList ARM and ARM64 Binaries, Step: Run Module Scripts Unit Tests, Companion APK (OpenListHelper), Offline Config (offline.conf), Offline Confirm Sheet (+12 more)

### Community 3 - "Offline Helper Core Unit Tests"
Cohesion: 0.16
Nodes (4): MatchCandidate, TextSpan, OfflineHelperCoreTest, Requirements

### Community 4 - "Magnet Parsing & Config Core"
Cohesion: 0.17
Nodes (3): ApiResult, DirListResult, OfflineHelperCore

### Community 5 - "Daemon Service & Token Bridge"
Cohesion: 0.40
Nodes (14): extract_openlist_token(), get_lan_ip(), get_port(), has_enabled_115_storage(), install_boot_companion_sync_guard(), log(), main(), reload_openlist_storages() (+6 more)

### Community 6 - "Module Full Uninstallation"
Cohesion: 0.61
Nodes (7): clean_binaries(), clean_companion(), clean_data(), log(), main(), uninstall.sh script, stop_service()

### Community 7 - "Module Script Test Suite"
Cohesion: 0.14
Nodes (16): assert_eq(), assert_file_contains(), assert_file_not_contains(), BRIDGE_TMP_CONF, DATA_DIR, ENABLE_DISABLE_WATCHER, HELPER_DATA_DIR, LOG_FILE (+8 more)

### Community 8 - "Interactive Volume Key Installer"
Cohesion: 0.48
Nodes (5): make_selection(), customize.sh script, show_binary_menu(), show_data_menu(), show_password_menu()

### Community 9 - "User Data Uninstallation"
Cohesion: 0.67
Nodes (6): clean_binaries(), clean_data(), log(), main(), uninstall-user.sh script, stop_service()

### Community 10 - "Companion APK Build Pipeline"
Cohesion: 0.70
Nodes (4): find_tool(), run_apksigner(), run_d8(), build-apk.sh script

### Community 11 - "Action Toggle Service Controller"
Cohesion: 0.60
Nodes (5): check_openlist_status(), find_busybox(), set_companion_menu_enabled(), action.sh script, update_module_prop_stopped()

### Community 14 - "steps"
Cohesion: 0.08
Nodes (23): runs-on, steps, API_URL, GITHUB_TOKEN, jobs, build, name, on (+15 more)

### Community 15 - ".main"
Cohesion: 0.15
Nodes (9): TestCase, Files Owned, Files Owned, Implementation Plan: Companion Menu Visibility Lifecycle Sync, Requirements, Requirements, Spec & Global Constraints, Task 1: Default-disable ProcessTextActivity in Companion APK Manifest and add unit tests (+1 more)

### Community 16 - "Implementation Plan: Interactive Folder Picker in Offline Confirm Sheet"
Cohesion: 0.25
Nodes (7): Files Owned, Files Owned, Implementation Plan: Interactive Folder Picker in Offline Confirm Sheet, Requirements, Spec & Global Constraints, Task 1: Add OpenList directory listing API, JSON parser, path helpers, and unit tests in OfflineHelperCore, Task 2: Add interactive folder browser & preset path chips to ProcessTextActivity and update docs

### Community 17 - "ProcessTextActivity"
Cohesion: 0.14
Nodes (10): OfflineConfig, ProcessTextActivity, Files Owned, Files Owned, Implementation Plan: Post-Offline Directory Cache Refresh & Folder Picker Force Refresh, Requirements, Requirements, Spec & Global Constraints (+2 more)

## Knowledge Gaps
- **19 isolated node(s):** `DATA_DIR`, `LOG_FILE`, `BRIDGE_TMP_CONF`, `HELPER_DATA_DIR`, `PATH` (+14 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 92 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `OfflineHelperCoreTest` connect `Offline Helper Core Unit Tests` to `HTTP Networking & Data Models`, `Magnet Parsing & Config Core`, `.main`?**
  _High betweenness centrality (0.080) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `OfflineHelperCoreTest` (e.g. with `Requirements` and `Requirements`) actually correct?**
  _`OfflineHelperCoreTest` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `DATA_DIR`, `LOG_FILE`, `BRIDGE_TMP_CONF` to the rest of the system?**
  _19 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HTTP Networking & Data Models` be split into smaller, more focused modules?**
  _Cohesion score 0.07741935483870968 - nodes in this community are weakly interconnected._
- **Why does `ProcessTextActivity` connect `ProcessTextActivity` to `ProcessTextActivity.java`, `.main`?**
  _High betweenness centrality (0.068) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ProcessTextActivity` (e.g. with `Spec & Global Constraints` and `Spec & Global Constraints`) actually correct?**
  _`ProcessTextActivity` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Should `Domain Concepts & CI Pipeline` be split into smaller, more focused modules?**
  _Cohesion score 0.1038961038961039 - nodes in this community are weakly interconnected._