### &nbsp;&nbsp;&nbsp;🚀 Features

- **drivers/139**:
  - Support uploading large files up to 500 GB &nbsp;-&nbsp; by @glsname and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3115 [<samp>(3d3d1)</samp>](https://github.com/OpenListTeam/OpenList/commit/3d3d10a1)
  - Make the API client type configurable &nbsp;-&nbsp; by @PIKACHUIM in https://github.com/OpenListTeam/OpenList/issues/3196 [<samp>(3b282)</samp>](https://github.com/OpenListTeam/OpenList/commit/3b28270a)
- **drivers/guangyapan**:
  - Add md5-based instant upload support &nbsp;-&nbsp; by @PIKACHUIM and **PIKACHUIM** in https://github.com/OpenListTeam/OpenList/issues/3034 [<samp>(6ad44)</samp>](https://github.com/OpenListTeam/OpenList/commit/6ad44605)
- **drivers/pikpak**:
  - Auto re-login with username/password when tokens expire &nbsp;-&nbsp; by @wray-lee in https://github.com/OpenListTeam/OpenList/issues/3001 [<samp>(e73a8)</samp>](https://github.com/OpenListTeam/OpenList/commit/e73a80c7)
- **local**:
  - Add PDF thumbnails on macOS &nbsp;-&nbsp; by @flyingrtx2333, **Codex** and @ILoveScratch2 in https://github.com/OpenListTeam/OpenList/issues/3017 [<samp>(f18b4)</samp>](https://github.com/OpenListTeam/OpenList/commit/f18b4acc)
- **server/s3**:
  - Support multipart upload &nbsp;-&nbsp; by @xrgzs in https://github.com/OpenListTeam/OpenList/issues/2813 [<samp>(6247c)</samp>](https://github.com/OpenListTeam/OpenList/commit/6247cf7b)
- **task**:
  - Persist task timestamps across restarts &nbsp;-&nbsp; by @fryeggs and **OpenAI Codex** in https://github.com/OpenListTeam/OpenList/issues/2914 [<samp>(d6109)</samp>](https://github.com/OpenListTeam/OpenList/commit/d6109a79)

### &nbsp;&nbsp;&nbsp;🐞 Bug Fixes

- Harden request handling for files, search, proxy and SSO &nbsp;-&nbsp; by @ILoveScratch2 and **PIKACHUIM** [<samp>(ea106)</samp>](https://github.com/OpenListTeam/OpenList/commit/ea10624f)
- **115_open**:
  - Refresh expired OSS credentials during upload &nbsp;-&nbsp; by @xqmmcqs and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3063 [<samp>(d894a)</samp>](https://github.com/OpenListTeam/OpenList/commit/d894a398)
- **alist_v3**:
  - Set child paths so nested directories resolve &nbsp;-&nbsp; by @Elity and **Claude** in https://github.com/OpenListTeam/OpenList/issues/3019 [<samp>(4580c)</samp>](https://github.com/OpenListTeam/OpenList/commit/4580c4db)
- **aliyundrive**:
  - Limit callback concurrency &nbsp;-&nbsp; by @nostalume and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3071 [<samp>(89345)</samp>](https://github.com/OpenListTeam/OpenList/commit/893457cd)
- **build**:
  - Update cgo-actions version to v1.3.0 and fallback FreeBSD version to 14.4 &nbsp;-&nbsp; by @elysia-best in https://github.com/OpenListTeam/OpenList/issues/3130 [<samp>(c1670)</samp>](https://github.com/OpenListTeam/OpenList/commit/c16701b9)
- **deps**:
  - Update module github.com/rclone/rclone to v1.75.1 &nbsp;-&nbsp; in https://github.com/OpenListTeam/OpenList/issues/3035 [<samp>(eee91)</samp>](https://github.com/OpenListTeam/OpenList/commit/eee910ba)
- **drivers/139**:
  - Improve mail login credential renewal &nbsp;-&nbsp; by @UcnacDx2 in https://github.com/OpenListTeam/OpenList/issues/3029 [<samp>(d90d8)</samp>](https://github.com/OpenListTeam/OpenList/commit/d90d8490)
- **drivers/189**:
  - Decode JSON strings before parsing timestamps &nbsp;-&nbsp; by @jyxjjj and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3033 [<samp>(c3d3d)</samp>](https://github.com/OpenListTeam/OpenList/commit/c3d3da92)
- **drivers/189pc**:
  - Align login with the official PC client &nbsp;-&nbsp; by @naiyQAQ and **Claude Opus 5 (1M context)** in https://github.com/OpenListTeam/OpenList/issues/3105 [<samp>(4c39b)</samp>](https://github.com/OpenListTeam/OpenList/commit/4c39bbe9)
  - Preserve file extension during family transfer &nbsp;-&nbsp; by @qcnhy and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3083 [<samp>(61e53)</samp>](https://github.com/OpenListTeam/OpenList/commit/61e535c9)
- **drivers/lanzou**:
  - Support new /fn download page structure &nbsp;-&nbsp; by @rzsgsfm, **rzsgsfm** and **GLM (ZCode CLI)** in https://github.com/OpenListTeam/OpenList/issues/3157 [<samp>(e1d88)</samp>](https://github.com/OpenListTeam/OpenList/commit/e1d88b07)
- **drivers/s3**:
  - Sign content-type for direct uploads &nbsp;-&nbsp; by @mumingluan and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3152 [<samp>(6bb4c)</samp>](https://github.com/OpenListTeam/OpenList/commit/6bb4c880)
- **fs**:
  - Return FOLDER type for directories in fs/get responses &nbsp;-&nbsp; by @ZRHann in https://github.com/OpenListTeam/OpenList/issues/3114 [<samp>(6c600)</samp>](https://github.com/OpenListTeam/OpenList/commit/6c600910)
  - Only list parent dir for related objs when file is video &nbsp;-&nbsp; by @ZRHann in https://github.com/OpenListTeam/OpenList/issues/3113 [<samp>(9de3f)</samp>](https://github.com/OpenListTeam/OpenList/commit/9de3f69b)
- **ftp**:
  - Handle EOF and detect content type from read bytes &nbsp;-&nbsp; by @awaae001 in https://github.com/OpenListTeam/OpenList/issues/3125 [<samp>(40f4f)</samp>](https://github.com/OpenListTeam/OpenList/commit/40f4f654)
- **internal/db/searchnode**:
  - Fix index update path &nbsp;-&nbsp; by @ILoveScratch2 in https://github.com/OpenListTeam/OpenList/issues/3128 [<samp>(54ae9)</samp>](https://github.com/OpenListTeam/OpenList/commit/54ae9d74)
- **net**:
  - Preserve cancellation errors during partitioned downloads &nbsp;-&nbsp; by @nostalume in https://github.com/OpenListTeam/OpenList/issues/3090 [<samp>(1462d)</samp>](https://github.com/OpenListTeam/OpenList/commit/1462d63a)
  - Handle gzip reader error on error response decoding &nbsp;-&nbsp; by @awaae001 in https://github.com/OpenListTeam/OpenList/issues/3179 [<samp>(48246)</samp>](https://github.com/OpenListTeam/OpenList/commit/482464c2)
- **op**:
  - Enforce link cache lifecycle policy &nbsp;-&nbsp; by @nostalume, **nostalume** and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3101 [<samp>(56064)</samp>](https://github.com/OpenListTeam/OpenList/commit/56064d19)
- **release**:
  - Fetch frontend assets from edge &nbsp;-&nbsp; by @jyxjjj and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3052 [<samp>(55530)</samp>](https://github.com/OpenListTeam/OpenList/commit/55530ff1)
- **s3**:
  - Default upload content types and return partial content &nbsp;-&nbsp; by @jyxjjj and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3053 [<samp>(d9d8a)</samp>](https://github.com/OpenListTeam/OpenList/commit/d9d8aa24)
  - Encode multipart fixture paths &nbsp;-&nbsp; by @nostalume, **nostalume** and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3074 [<samp>(5447e)</samp>](https://github.com/OpenListTeam/OpenList/commit/5447ecb0)
  - Close ranged response bodies &nbsp;-&nbsp; by @nostalume in https://github.com/OpenListTeam/OpenList/issues/3095 [<samp>(b51d1)</samp>](https://github.com/OpenListTeam/OpenList/commit/b51d1c82)
  - End common prefixes with a slash &nbsp;-&nbsp; by @zeroornull, **zeroornull** and @cursoragent in https://github.com/OpenListTeam/OpenList/issues/3174 [<samp>(f2774)</samp>](https://github.com/OpenListTeam/OpenList/commit/f27748d9)
- **teldrive**:
  - Use a valid root path for listings &nbsp;-&nbsp; by @spark-328 in https://github.com/OpenListTeam/OpenList/issues/3108 [<samp>(cadbf)</samp>](https://github.com/OpenListTeam/OpenList/commit/cadbf872)
- **webdav**:
  - Honor conditional PUT requests &nbsp;-&nbsp; by @jyxjjj and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3066 [<samp>(8cfe9)</samp>](https://github.com/OpenListTeam/OpenList/commit/8cfe906e)

##### &nbsp;&nbsp;&nbsp;&nbsp;[View changes on GitHub](https://github.com/OpenListTeam/OpenList/compare/v4.2.6...v4.2.7)
