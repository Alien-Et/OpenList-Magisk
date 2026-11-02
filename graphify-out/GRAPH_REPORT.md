# Graph Report - openlist  (2026-11-02)

## Corpus Check
- 21 files · ~52,793 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 8 file(s) not represented in the graph (top: (none) 4, .prop 1, .apk 1)

## Summary
- 182 nodes · 289 edges · 13 communities (9 shown, 4 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 10 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- ProcessText UI & Dialog Flow
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

## God Nodes (most connected - your core abstractions)
1. `OfflineHelperCoreTest` - 17 edges
2. `OfflineHelperCore` - 13 edges
3. `ProcessTextActivity` - 12 edges
4. `OfflineConfig` - 10 edges
5. `main()` - 7 edges
6. `log()` - 6 edges
7. `main()` - 6 edges
8. `log()` - 6 edges
9. `Companion APK (OpenListHelper)` - 6 edges
10. `make_selection()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `Step: Build OpenListHelper Companion APK` --implements--> `Companion APK (OpenListHelper)`  [INFERRED]
  .github/workflows/1.yml → GLOSSARY.md
- `Native PROCESS_TEXT Interception Architecture` --rationale_for--> `Companion APK (OpenListHelper)`  [INFERRED]
  docs/adr/0001-companion-apk-process-text-offline-download.md → GLOSSARY.md
- `Step: Sync OpenList ARM and ARM64 Binaries` --references--> `OpenList Daemon`  [INFERRED]
  .github/workflows/1.yml → GLOSSARY.md
- `OpenList Magisk v4.2.9 Changelog` --cites--> `OpenList Daemon`  [INFERRED]
  OpenList-Magisk/CHANGELOG.md → GLOSSARY.md
- `OpenList Root Project Documentation` --references--> `OpenList-Magisk Module Documentation`  [INFERRED]
  README.md → OpenList-Magisk/README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Browser Text Selection to 115 Cloud Offline Download Flow** — glossary_text_selection_menu, glossary_offline_confirm_sheet, glossary_companion_apk, glossary_openlist_daemon, glossary_offline_engine [EXTRACTED 1.00]
- **Root Daemon to Sandbox Config and Token Synchronization** — glossary_openlist_daemon, glossary_offline_config, docs_adr_0001_companion_apk_process_text_offline_download_sandbox_token_bridge, openlist_magisk_readme_offline_config_specification [EXTRACTED 1.00]
- **Automated Magisk Module Build and Release Pipeline** — github_workflows_1_build_magisk_module, github_workflows_1_step_build_companion_apk, github_workflows_1_step_sync_binaries, github_workflows_1_step_unit_tests [EXTRACTED 1.00]

## Communities (13 total, 4 thin omitted)

### Community 2 - "Domain Concepts & CI Pipeline"
Cohesion: 0.10
Nodes (20): ADR 0001: Companion APK PROCESS_TEXT Offline Download, Workflow: Build OpenList Magisk Module, Step: Build OpenListHelper Companion APK, Step: Sync OpenList ARM and ARM64 Binaries, Step: Run Module Scripts Unit Tests, Companion APK (OpenListHelper), Offline Config (offline.conf), Offline Confirm Sheet (+12 more)

### Community 4 - "Magnet Parsing & Config Core"
Cohesion: 0.16
Nodes (4): ApiResult, MatchCandidate, OfflineHelperCore, TextSpan

### Community 5 - "Daemon Service & Token Bridge"
Cohesion: 0.49
Nodes (9): extract_openlist_token(), get_lan_ip(), get_port(), log(), main(), service.sh script, sync_companion_apk_and_config(), toast_find_busybox() (+1 more)

### Community 6 - "Module Full Uninstallation"
Cohesion: 0.61
Nodes (7): clean_binaries(), clean_companion(), clean_data(), log(), main(), uninstall.sh script, stop_service()

### Community 7 - "Module Script Test Suite"
Cohesion: 0.32
Nodes (7): assert_eq(), assert_file_contains(), BRIDGE_TMP_CONF, DATA_DIR, HELPER_DATA_DIR, LOG_FILE, test_module_scripts.sh script

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
Cohesion: 0.70
Nodes (4): check_openlist_status(), find_busybox(), action.sh script, update_module_prop_stopped()

## Knowledge Gaps
- **11 isolated node(s):** `DATA_DIR`, `LOG_FILE`, `BRIDGE_TMP_CONF`, `HELPER_DATA_DIR`, `Step: Run Module Scripts Unit Tests` (+6 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 53 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `OfflineHelperCoreTest` connect `Offline Helper Core Unit Tests` to `HTTP Networking & Data Models`?**
  _High betweenness centrality (0.072) - this node is a cross-community bridge._
- **What connects `DATA_DIR`, `LOG_FILE`, `BRIDGE_TMP_CONF` to the rest of the system?**
  _11 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `ProcessText UI & Dialog Flow` be split into smaller, more focused modules?**
  _Cohesion score 0.06620209059233449 - nodes in this community are weakly interconnected._
- **Why does `OfflineHelperCore` connect `Magnet Parsing & Config Core` to `ProcessText UI & Dialog Flow`, `HTTP Networking & Data Models`, `Offline Helper Core Unit Tests`?**
  _High betweenness centrality (0.071) - this node is a cross-community bridge._
- **Should `HTTP Networking & Data Models` be split into smaller, more focused modules?**
  _Cohesion score 0.09116809116809117 - nodes in this community are weakly interconnected._
- **Should `Domain Concepts & CI Pipeline` be split into smaller, more focused modules?**
  _Cohesion score 0.1038961038961039 - nodes in this community are weakly interconnected._