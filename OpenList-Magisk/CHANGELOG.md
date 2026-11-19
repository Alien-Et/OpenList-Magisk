### &nbsp;&nbsp;&nbsp;🚀 Features

- **drivers**: Add CtFile OpenAPI driver &nbsp;-&nbsp; by @SenkjM, **Grok Bot**, **Claude Opus 5.5**, @Suyunmeng and **LunelleEverdawn** in https://github.com/OpenListTeam/OpenList/issues/3214 [<samp>(f33a2)</samp>](https://github.com/OpenListTeam/OpenList/commit/f33a2c78)
- **drivers/onedrive_app**: Support mounting SharePoint site document library &nbsp;-&nbsp; by @AkashiCoin and **Claude** in https://github.com/OpenListTeam/OpenList/issues/3252 [<samp>(4780b)</samp>](https://github.com/OpenListTeam/OpenList/commit/4780b1cf)
- **media**: Scan every folder level, save incrementally, TV tags, seed task progress &nbsp;-&nbsp; by @PIKACHUIM and **Claude Opus 5.5** in https://github.com/OpenListTeam/OpenList/issues/3263 [<samp>(ef5d8)</samp>](https://github.com/OpenListTeam/OpenList/commit/ef5d8c8d)
- **sso**: Add Feishu login support &nbsp;-&nbsp; by @makotowu in https://github.com/OpenListTeam/OpenList/issues/3202 [<samp>(de1cd)</samp>](https://github.com/OpenListTeam/OpenList/commit/de1cdb3a)

### &nbsp;&nbsp;&nbsp;🐞 Bug Fixes

- **auth**:
  - Match SQLite username constraint errors &nbsp;-&nbsp; by @Suyunmeng and **LunelleEverdawn** in https://github.com/OpenListTeam/OpenList/issues/3295 [<samp>(e7b6f)</samp>](https://github.com/OpenListTeam/OpenList/commit/e7b6fac8)
- **deps**:
  - Update module gorm.io/driver/postgres to v1.6.3 &nbsp;-&nbsp; in https://github.com/OpenListTeam/OpenList/issues/3269 [<samp>(beb3b)</samp>](https://github.com/OpenListTeam/OpenList/commit/beb3bbaf)
  - Update module github.com/rclone/rclone to v1.75.2 &nbsp;-&nbsp; in https://github.com/OpenListTeam/OpenList/issues/3287 [<samp>(ac8e9)</samp>](https://github.com/OpenListTeam/OpenList/commit/ac8e9bff)
- **drivers/115**:
  - Retry upload init after decrypt failures &nbsp;-&nbsp; by @Suyunmeng and **LunelleEverdawn** in https://github.com/OpenListTeam/OpenList/issues/3268 [<samp>(6aeaf)</samp>](https://github.com/OpenListTeam/OpenList/commit/6aeaf1da)
  - Handle multipart upload failures safely &nbsp;-&nbsp; by @Suyunmeng and **LunelleEverdawn** in https://github.com/OpenListTeam/OpenList/issues/3312 [<samp>(05d3f)</samp>](https://github.com/OpenListTeam/OpenList/commit/05d3fea0)
- **drivers/guangyapan**:
  - Return list errors instead of an empty folder &nbsp;-&nbsp; by @DIYgod and **Claude Opus 5.5** in https://github.com/OpenListTeam/OpenList/issues/3326 [<samp>(db581)</samp>](https://github.com/OpenListTeam/OpenList/commit/db581fc6)
- **drivers/local**:
  - Handle cross-device recycle bin deletes &nbsp;-&nbsp; by @Suyunmeng and **LunelleEverdawn** in https://github.com/OpenListTeam/OpenList/issues/3304 [<samp>(25da9)</samp>](https://github.com/OpenListTeam/OpenList/commit/25da9901)
- **drivers/onedrive**:
  - Refresh token on drive quota query and retry only once &nbsp;-&nbsp; by @Vurliy, **Vurliy** and **Claude Opus 5.5** in https://github.com/OpenListTeam/OpenList/issues/3335 [<samp>(d09af)</samp>](https://github.com/OpenListTeam/OpenList/commit/d09af74a)
- **drivers/quark_open**:
  - Stop treating content_hash as SHA1 &nbsp;-&nbsp; by @sevxn007 and **Codex** in https://github.com/OpenListTeam/OpenList/issues/3340 [<samp>(9f170)</samp>](https://github.com/OpenListTeam/OpenList/commit/9f170a9a)
- **fs**:
  - Restore the provider field in fs list responses &nbsp;-&nbsp; by @somaz94, **Claude** and @Suyunmeng in https://github.com/OpenListTeam/OpenList/issues/3209 [<samp>(74320)</samp>](https://github.com/OpenListTeam/OpenList/commit/74320ca6)
- **local**:
  - Normalize the storage root of the directory size map to prevent upload stall &nbsp;-&nbsp; by @one-squared in https://github.com/OpenListTeam/OpenList/issues/3310 [<samp>(8d8c0)</samp>](https://github.com/OpenListTeam/OpenList/commit/8d8c0269)
- **op**:
  - Do not report a failed listing as a missing object &nbsp;-&nbsp; by @jayhemnani9910 in https://github.com/OpenListTeam/OpenList/issues/3339 [<samp>(845f9)</samp>](https://github.com/OpenListTeam/OpenList/commit/845f9b1d)
- **seed**:
  - Make 189 CAS rapid upload carry the right file, hashes and slice size &nbsp;-&nbsp; by @PIKACHUIM in https://github.com/OpenListTeam/OpenList/issues/3341 [<samp>(b8ab7)</samp>](https://github.com/OpenListTeam/OpenList/commit/b8ab7609)
- **sharing**:
  - Count share access atomically per client IP &nbsp;-&nbsp; by @awaae001 in https://github.com/OpenListTeam/OpenList/issues/3294 [<samp>(78c5d)</samp>](https://github.com/OpenListTeam/OpenList/commit/78c5d9b6)
  - Hide physical paths in download errors &nbsp;-&nbsp; by @Suyunmeng and **LunelleEverdawn** in https://github.com/OpenListTeam/OpenList/issues/3322 [<samp>(e7282)</samp>](https://github.com/OpenListTeam/OpenList/commit/e72822f5)
- **storage**:
  - Persist rotated tokens reliably and enable sqlite WAL &nbsp;-&nbsp; by @PIKACHUIM in https://github.com/OpenListTeam/OpenList/issues/3344 [<samp>(f2dcf)</samp>](https://github.com/OpenListTeam/OpenList/commit/f2dcf4a8)
- **stream**:
  - Automatically resume interrupted source streams &nbsp;-&nbsp; by @awaae001 in https://github.com/OpenListTeam/OpenList/issues/3324 [<samp>(e9839)</samp>](https://github.com/OpenListTeam/OpenList/commit/e9839e16)
- **webdav**:
  - Return the request URL as the LOCK lockroot &nbsp;-&nbsp; by @jayhemnani9910 in https://github.com/OpenListTeam/OpenList/issues/3288 [<samp>(564e3)</samp>](https://github.com/OpenListTeam/OpenList/commit/564e30e7)

##### &nbsp;&nbsp;&nbsp;&nbsp;[View changes on GitHub](https://github.com/OpenListTeam/OpenList/compare/v4.2.9...v4.2.10)
