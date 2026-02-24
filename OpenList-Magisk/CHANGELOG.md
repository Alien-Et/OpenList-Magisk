### &nbsp;&nbsp;&nbsp;🚀 Features

- **123pan**:
  - Add offline download &nbsp;-&nbsp; by @mcxiedidi in https://github.com/OpenListTeam/OpenList/issues/1911 [<samp>(642ac)</samp>](https://github.com/OpenListTeam/OpenList/commit/642acf8b)
- **drivers**:
  - Support getting disk usage of some drivers &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1905 [<samp>(744db)</samp>](https://github.com/OpenListTeam/OpenList/commit/744dbd5e)
  - Add autoindex driver &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1978 [<samp>(f0578)</samp>](https://github.com/OpenListTeam/OpenList/commit/f057846e)
- **drivers/cloudreve**:
  - Implement GetDetails &nbsp;-&nbsp; by @xrgzs in https://github.com/OpenListTeam/OpenList/issues/1960 [<samp>(fca99)</samp>](https://github.com/OpenListTeam/OpenList/commit/fca993a8)
- **drivers/cloudreve_v4**:
  - Implement Getter interface &nbsp;-&nbsp; by @xrgzs in https://github.com/OpenListTeam/OpenList/issues/1937 [<samp>(5c82f)</samp>](https://github.com/OpenListTeam/OpenList/commit/5c82f552)
- **drivers/mega**:
  - Support getting disk usage &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1903 [<samp>(1f9a7)</samp>](https://github.com/OpenListTeam/OpenList/commit/1f9a7e3a)
  - Support permanently deleting files &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1913 [<samp>(74799)</samp>](https://github.com/OpenListTeam/OpenList/commit/747993e2)
- **drivers/webdav**:
  - Add support for 302 redirects &nbsp;-&nbsp; by @xrgzs in https://github.com/OpenListTeam/OpenList/issues/1952 [<samp>(c6bd4)</samp>](https://github.com/OpenListTeam/OpenList/commit/c6bd4372)

### &nbsp;&nbsp;&nbsp;🐞 Bug Fixes

- **api/remove**:
  - Add validation for empty items in delete file list &nbsp;-&nbsp; by @datao2001 in https://github.com/OpenListTeam/OpenList/issues/1617 [<samp>(d685b)</samp>](https://github.com/OpenListTeam/OpenList/commit/d685bbfa)
- **ci**:
  - Change unchecked regex &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1993 [<samp>(27fdd)</samp>](https://github.com/OpenListTeam/OpenList/commit/27fdd03e)
- **cloudreve**:
  - Manually set path to avoid empty path &nbsp;-&nbsp; by @TwoOnefour in https://github.com/OpenListTeam/OpenList/issues/1933 [<samp>(0d99e)</samp>](https://github.com/OpenListTeam/OpenList/commit/0d99e16b)
- **driver/quark_uc**:
  - Fix display of non-compliant filenames &nbsp;-&nbsp; by @Cp0204 in https://github.com/OpenListTeam/OpenList/issues/2000 [<samp>(02aec)</samp>](https://github.com/OpenListTeam/OpenList/commit/02aec713)
- **drivers/alias**:
  - Default sort & substitute link &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1917 [<samp>(f0e53)</samp>](https://github.com/OpenListTeam/OpenList/commit/f0e53d18)
- **drivers/alist_v3**:
  - Failed to unmarshal MeResp &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1931 [<samp>(e1921)</samp>](https://github.com/OpenListTeam/OpenList/commit/e1921494)
- **drivers/cloudreve_v4**:
  - Add IsFolder attribute to Getter response &nbsp;-&nbsp; by @xrgzs in https://github.com/OpenListTeam/OpenList/issues/2035 [<samp>(29fcf)</samp>](https://github.com/OpenListTeam/OpenList/commit/29fcf590)
- **drivers/ftp**:
  - Failed to get objs &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1948 [<samp>(b553d)</samp>](https://github.com/OpenListTeam/OpenList/commit/b553dc35)
- **drivers/github**:
  - Failed to get objs &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1915 [<samp>(378e3)</samp>](https://github.com/OpenListTeam/OpenList/commit/378e37b0)
- **drivers/quark**:
  - Apply html escaping in quark &nbsp;-&nbsp; by @mkitsdts in https://github.com/OpenListTeam/OpenList/issues/2046 [<samp>(27732)</samp>](https://github.com/OpenListTeam/OpenList/commit/27732ccc)
- **drivers/seafile**:
  - Object not found when RootFolderPath != / &nbsp;-&nbsp; by @Khoray in https://github.com/OpenListTeam/OpenList/issues/2010 [<samp>(a2573)</samp>](https://github.com/OpenListTeam/OpenList/commit/a2573fb2)
- **drivers/strm**:
  - Delete extra local directories in sync mode &nbsp;-&nbsp; by @sevxn007 in https://github.com/OpenListTeam/OpenList/issues/1980 [<samp>(ea4b5)</samp>](https://github.com/OpenListTeam/OpenList/commit/ea4b5e32)
- **fs**:
  - Panic when failed to get storage details &nbsp;-&nbsp; by @KirCute in https://github.com/OpenListTeam/OpenList/issues/1964 [<samp>(85c69)</samp>](https://github.com/OpenListTeam/OpenList/commit/85c69d85)
  - Handle non-existent destination directory in file transfer &nbsp;-&nbsp; by @Ironboxplus in https://github.com/OpenListTeam/OpenList/issues/1898 [<samp>(a79d8)</samp>](https://github.com/OpenListTeam/OpenList/commit/a79d8347)
- **webdav/move**:
  - Fix source file still exist after moving file by webdav &nbsp;-&nbsp; by @mkitsdts in https://github.com/OpenListTeam/OpenList/issues/1979 [<samp>(d8417)</samp>](https://github.com/OpenListTeam/OpenList/commit/d8417e05)

### &nbsp;&nbsp;&nbsp;🏎 Performance

- **baidu_netdisk**: Reduce the number of file listing requests &nbsp;-&nbsp; by @hcrgm in https://github.com/OpenListTeam/OpenList/issues/2016 [<samp>(031b7)</samp>](https://github.com/OpenListTeam/OpenList/commit/031b719b)

##### &nbsp;&nbsp;&nbsp;&nbsp;[View changes on GitHub](https://github.com/OpenListTeam/OpenList/compare/v4.1.9...v4.1.10)
