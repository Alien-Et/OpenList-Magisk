/* OpenList 模块 WebUI
 * 仅做界面与参数校验，所有实际操作交给 control.sh
 */
(function () {
  'use strict';

  // 模块目录：优先从 WebUI 自身地址推导
  // KernelSU / APatch 打开的是 file:///data/adb/modules/<id>/webroot/index.html，
  // 写死 id 的话，改了 module.prop 的 id 就会失配
  var MODDIR = (function () {
    try {
      var m = (location.pathname || '').match(/^(.*)\/webroot\/index\.html?$/);
      if (m && m[1]) return decodeURIComponent(m[1]);
    } catch (e) {}
    return '/data/adb/modules/openlist';
  })();
  var CONTROL = MODDIR + '/control.sh';
  var PROGRESS = '/data/local/tmp/openlist_update.progress';
  var hasKsu = typeof window.ksu !== 'undefined';

  /* ---------- 主题：自动 / 浅色 / 深色 ---------- */
  var THEME_KEY = 'openlist.theme';
  var themeMode = 'auto';
  try { themeMode = localStorage.getItem(THEME_KEY) || 'auto'; } catch (e) {}
  var mql = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  function effectiveDark() {
    if (themeMode === 'dark') return true;
    if (themeMode === 'light') return false;
    return !!(mql && mql.matches);
  }

  function applyTheme() {
    document.documentElement.setAttribute('data-theme', effectiveDark() ? 'dark' : 'light');
    var btn = document.getElementById('themeBtn');
    if (btn) {
      btn.textContent = themeMode === 'auto' ? '自动' : (themeMode === 'light' ? '浅色' : '深色');
      btn.title = '主题：' + btn.textContent + '（点击切换）';
    }
  }

  function cycleTheme() {
    themeMode = themeMode === 'auto' ? 'light' : (themeMode === 'light' ? 'dark' : 'auto');
    try { localStorage.setItem(THEME_KEY, themeMode); } catch (e) {}
    applyTheme();
  }

  if (mql) {
    var onSchemeChange = function () { if (themeMode === 'auto') applyTheme(); };
    if (mql.addEventListener) mql.addEventListener('change', onSchemeChange);
    else if (mql.addListener) mql.addListener(onSchemeChange);
  }
  applyTheme();

  var $ = function (id) { return document.getElementById(id); };
  var state = { running: '0', port: '5244', ip: '127.0.0.1', pid: '-', version: '-' };
  var progTimer = null;

  /* ---------- 基础 ---------- */
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function toast(msg, isErr) {
    var t = $('toast');
    t.textContent = msg;
    t.className = 'toast show' + (isErr ? ' err' : '');
    clearTimeout(t._tm);
    t._tm = setTimeout(function () { t.className = 'toast'; }, 2600);
  }

  function b64utf8(s) {
    return btoa(unescape(encodeURIComponent(s)));
  }

  /* ---------- 演示模式（浏览器直接打开 index.html?demo=1 时用假数据预览界面） ---------- */
  var DEMO = /[?&]demo=1/.test(location.search || '') || /preview\.html?$/i.test(location.pathname || '');
  var DEMO_VERSIONS = [
    'v4.2.10|2026-11-19', 'v4.2.9|2025-11-11', 'v4.2.8|2026-10-25', 'v4.2.7|2026-10-24',
    'v4.2.6|2026-03-25', 'v4.2.5|2026-10-15', 'v4.2.4|2026-09-01', 'v4.2.3|2026-08-07',
    'v4.2.2|2026-07-23', 'v4.2.1|2026-07-01', 'v4.2.0|2026-05-25', 'v4.1.10|2026-04-09'
  ];

  function demoCtl(args) {
    var a = String(args || '');
    var kv = { result: 'ok' };
    var out = [];
    if (a.indexOf('status') === 0) {
      kv = {
        running: '1', pid: '21874', port: '5244', ip: '192.168.1.100', version: 'v4.2.10',
        data_dir: '/data/adb/openlist', bin: '/data/adb/openlist/bin/openlist',
        module_dir: '/data/adb/modules/openlist', abi: 'arm64-v8a', result: 'ok'
      };
    } else if (a.indexOf('versions') === 0) {
      out = DEMO_VERSIONS.slice();
    } else if (a.indexOf('config-get') === 0) {
      kv = {
        PORT: '5244', TOKEN: 'openlist-demo', PATH: '/115/影视/',
        TOOL: '115 Open', DELETE_POLICY: 'delete_on_upload_succeed',
        PRESET_PATHS: '/115/影视/,/115/', result: 'ok'
      };
    } else if (a.indexOf('logs') === 0) {
      out = [
        '[2026-11-23 06:20:01] 启动 OpenList: /data/adb/openlist/bin/openlist server --data /data/adb/openlist',
        '[2026-11-23 06:20:02] OpenList 服务启动成功 (PID: 21874)',
        '[2026-11-23 06:20:03] 成功获取 Openlist 端口: 5244',
        '[2026-11-23 06:20:04] 成功获取 IP: ip_address=192.168.1.100'
      ];
    } else if (a.indexOf('scan') === 0) {
      out = [
        'item=bin|/data/adb/openlist/bin/openlist|172961944|1',
        'item=bin|/data/adb/modules/openlist/bin/openlist|172961944|0',
        'item=data|/data/adb/openlist|12|2026-11-23 07:20|1',
        'item=data|/sdcard/Android/openlist|15|2026-11-20 18:41|0'
      ];
      kv = { current_bin: '/data/adb/openlist/bin/openlist', current_data: '/data/adb/openlist', result: 'ok' };
    } else if (a.indexOf('check') === 0) {
      kv = { current: 'v4.2.10', latest: 'v4.2.10', asset: 'openlist-android-arm64.tar.gz',
             abi: 'arm64-v8a', up_to_date: '1', result: 'ok' };
    }
    out.push('result=' + (kv.result || 'ok'));
    return { raw: { errno: 0, stdout: out.join('\n'), stderr: '' }, kv: kv };
  }

  function demoSh(cmd) {
    var c = String(cmd || '');
    if (c.indexOf('/api/admin/storage/list') > 0) {
      return { errno: 0, stdout: '{"code":200,"data":[{"id":1,"mount_path":"/115","driver":"115 Open","status":"work"}]}', stderr: '' };
    }
    if (c.indexOf('/api/admin/task/offline_download/undone') > 0) {
      return { errno: 0, stdout: '{"code":200,"data":[]}', stderr: '' };
    }
    if (c.indexOf(' api ') > 0) {
      return { errno: 0, stdout: '{"code":200,"data":{}}', stderr: '' };
    }
    return { errno: 0, stdout: '', stderr: '' };
  }

  /* ---------- KernelSU / APatch 兼容层 ---------- */
  var cbSeq = 0;
  function sh(cmd, timeout) {
    if (DEMO) return Promise.resolve(demoSh(cmd));
    timeout = timeout || 30000;
    return new Promise(function (resolve) {
      if (!hasKsu) return resolve({ errno: -1, stdout: '', stderr: 'NO_KSU' });
      var name = '__cb_' + Date.now() + '_' + (cbSeq++);
      var done = false;
      function finish(r) {
        if (done) return;
        done = true;
        try { delete window[name]; } catch (e) {}
        resolve(r);
      }
      window[name] = function (errno, stdout, stderr) {
        finish({ errno: errno == null ? 0 : errno, stdout: stdout || '', stderr: stderr || '' });
      };
      try {
        var r = window.ksu.exec(cmd, '{}', name);
        if (typeof r === 'string') finish({ errno: 0, stdout: r, stderr: '' });
      } catch (e) {
        try {
          var r2 = window.ksu.exec(cmd);
          if (typeof r2 === 'string') finish({ errno: 0, stdout: r2, stderr: '' });
          else finish({ errno: -1, stdout: '', stderr: String(e) });
        } catch (e2) {
          finish({ errno: -1, stdout: '', stderr: String(e2) });
        }
      }
      setTimeout(function () { finish({ errno: -1, stdout: '', stderr: 'TIMEOUT' }); }, timeout);
    });
  }

  function ctl(args, timeout) {
    if (DEMO) return Promise.resolve(demoCtl(args));
    return sh("sh '" + CONTROL + "' " + args, timeout || 30000).then(function (r) {
      var kv = {};
      (r.stdout || '').split('\n').forEach(function (line) {
        var i = line.indexOf('=');
        if (i > 0) kv[line.slice(0, i)] = line.slice(i + 1);
      });
      return { raw: r, kv: kv };
    });
  }

  /* 调 OpenList 管理 API，返回解析后的 JSON */
  function api(method, path, body) {
    var args = 'api ' + method + " '" + path + "'";
    if (body !== undefined) args += " '" + b64utf8(JSON.stringify(body)) + "'";
    return sh("sh '" + CONTROL + "' " + args, 30000).then(function (r) {
      try {
        return JSON.parse(r.stdout);
      } catch (e) {
        return { code: -1, message: (r.stderr || r.stdout || '响应解析失败').slice(0, 200) };
      }
    });
  }

  /* ---------- 路径显示与复制 ---------- */
  function copyText(t) {
    try {
      var ta = document.createElement('textarea');
      ta.value = t;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      var ok = document.execCommand('copy');
      document.body.removeChild(ta);
      toast(ok ? '已复制' : '复制失败', !ok);
    } catch (e) {
      toast('复制失败', true);
    }
  }

  function setPath(id, val) {
    var el = $(id);
    if (!el) return;
    el.textContent = val || '-';
    el.dataset.path = val || '';
    el.onclick = function () {
      if (el.dataset.path) copyText(el.dataset.path);
    };
  }

  /* 迁移页只显示「非当前」的候选路径；只剩一个时自动选中 */
  function filterChips(boxId, cur) {
    var box = $(boxId);
    if (!box) return;
    var visible = [];
    box.querySelectorAll('button[data-path]').forEach(function (b) {
      var hide = (b.dataset.path === cur);
      b.style.display = hide ? 'none' : '';
      if (!hide) visible.push(b);
    });
    if (visible.length === 1) {
      box.dataset.value = visible[0].dataset.path;
      box.querySelectorAll('.chip-btn').forEach(function (x) { x.classList.remove('active'); });
      visible[0].classList.add('active');
    } else if (!visible.some(function (b) { return b.classList.contains('active'); })) {
      box.dataset.value = '';
    }
  }

  /* 把 admin API 的失败原因翻译成人话 */
  function apiHint(res) {
    var msg = (res && res.message) || '';
    if (/record not found/i.test(msg)) {
      return '还没有管理员账号：请先在浏览器打开 OpenList 网页完成初始化（首次访问会引导设置账号密码），完成后刷新本页';
    }
    if (/token is invalidated|Guest user is disabled|not admin/i.test(msg)) {
      return '管理员 token 失效：重启服务后重试';
    }
    return msg || '读取失败（服务未运行？）';
  }

  /* ---------- 渲染 ---------- */
  function renderStatus(kv) {
    state.running = kv.running || '0';
    state.port = kv.port || '5244';
    state.ip = kv.ip || '127.0.0.1';
    state.pid = kv.pid || '-';
    state.version = kv.version || '-';

    $('verChip').textContent = state.version;
    $('stateDot').className = 'dot ' + (state.running === '1' ? 'on' : 'off');
    $('stateText').textContent = state.running === '1' ? '运行中' : '已停止';
    $('pidText').textContent = 'PID ' + state.pid;
    $('addrText').textContent = state.running === '1' ? ('http://' + state.ip + ':' + state.port) : '未运行';
    setPath('dataDirText', kv.data_dir);
    setPath('modDirText', kv.module_dir || MODDIR);
    setPath('binText', kv.bin);
    $('curVer').textContent = state.version;
    if (kv.abi) $('abiText').textContent = kv.abi;

    var b = $('toggleBtn');
    b.textContent = state.running === '1' ? '停止服务' : '启动服务';
    b.className = state.running === '1' ? 'danger' : '';
    b.disabled = !hasKsu;
    $('restartBtn').disabled = !hasKsu;

    filterChips('dataDirChips', kv.data_dir);
    filterChips('binChips', kv.bin);
    // 版本列表可能是先从缓存渲染的，那时还不知道哪个是当前版本，补渲染一次
    if (verRows) renderVersions(verRows);
  }

  function renderConfig(kv) {
    $('cfgPort').value = kv.PORT || '5244';
    $('cfgToken').value = kv.TOKEN || '';
    $('cfgPath').value = kv.PATH || '/115/影视/';
    setSelect('toolSelect', kv.TOOL || '115 Open');
    setSelect('policySelect', kv.DELETE_POLICY || 'delete_on_upload_succeed');
    $('cfgPresets').value = kv.PRESET_PATHS || '/115/影视/,/115/';
  }

  /* 自定义下拉 */
  function setSelect(id, value) {
    var sel = $(id);
    if (!sel) return;
    var btn = sel.querySelector('.select-btn');
    var menu = sel.querySelector('.select-menu');
    var found = null;
    menu.querySelectorAll('button').forEach(function (b) {
      var hit = b.dataset.value === value;
      b.classList.toggle('active', hit);
      if (hit) found = b;
    });
    if (found) {
      sel.dataset.value = value;
      btn.textContent = found.textContent;
    }
  }

  function initSelects() {
    document.querySelectorAll('.select').forEach(function (sel) {
      var btn = sel.querySelector('.select-btn');
      var menu = sel.querySelector('.select-menu');
      btn.onclick = function (e) {
        e.stopPropagation();
        document.querySelectorAll('.select-menu').forEach(function (m) {
          if (m !== menu) m.hidden = true;
        });
        menu.hidden = !menu.hidden;
      };
      menu.querySelectorAll('button').forEach(function (opt) {
        opt.onclick = function (e) {
          e.stopPropagation();
          sel.dataset.value = opt.dataset.value;
          btn.textContent = opt.textContent;
          menu.querySelectorAll('button').forEach(function (b) { b.classList.remove('active'); });
          opt.classList.add('active');
          menu.hidden = true;
        };
      });
    });
    document.addEventListener('click', function () {
      document.querySelectorAll('.select-menu').forEach(function (m) { m.hidden = true; });
    });
  }

  /* 迁移预设路径 */
  function initPresets() {
    document.querySelectorAll('.chips').forEach(function (box) {
      var target = box.dataset.target ? document.getElementById(box.dataset.target) : null;
      box.querySelectorAll('.chip-btn').forEach(function (b) {
        b.onclick = function () {
          box.dataset.value = b.dataset.path;
          box.querySelectorAll('.chip-btn').forEach(function (x) { x.classList.remove('active'); });
          b.classList.add('active');
          if (target) target.value = b.dataset.path;
        };
      });
      if (target) {
        target.addEventListener('input', function () {
          box.querySelectorAll('.chip-btn').forEach(function (x) {
            x.classList.toggle('active', x.dataset.path === target.value);
          });
        });
      }
    });
  }

  /* ---------- 状态 ---------- */
  function refresh() {
    return ctl('status', 20000).then(function (r) {
      if (r.kv.result === 'ok') renderStatus(r.kv);
      else toast(r.kv.error || '读取状态失败', true);
    }).catch(function (e) { toast('读取失败: ' + e, true); });
  }

  /* 迁移/清理这类会改变磁盘布局的动作完成后，一次性刷新整页：
     状态与路径胶囊（refresh）+ 路径体检（loadScan）+ 日志（loadLog） */
  function refreshAll() {
    return refresh()
      .then(function () { return loadScan(true); })
      .then(function () { return loadLog(); })
      .catch(function () {});
  }

  function waitRunning(expect, tries) {
    var n = 0;
    return new Promise(function (resolve) {
      (function loop() {
        if (n++ >= (tries || 15)) return resolve(false);
        ctl('status', 10000).then(function (r) {
          renderStatus(r.kv);
          if ((r.kv.running === '1') === expect) return resolve(true);
          setTimeout(loop, 900);
        });
      })();
    });
  }

  function toggleService() {
    var running = state.running === '1';
    var b = $('toggleBtn');
    b.disabled = true;
    b.textContent = running ? '正在停止…' : '正在启动…';
    ctl(running ? 'stop' : 'start', 90000).then(function (r) {
      if (r.kv.result !== 'ok') toast(r.kv.error || '操作失败', true);
      return waitRunning(!running, 18);
    }).then(function (ok) {
      toast(ok ? (running ? '已停止' : '已启动') : '状态未变化，查看日志', !ok);
      return refresh();
    }).finally(function () { b.disabled = !hasKsu; });
  }

  function restart() {
    var b = $('restartBtn');
    b.disabled = true;
    ctl('restart', 90000).then(function () { return waitRunning(true, 18); })
      .then(function (ok) { toast(ok ? '已重启' : '重启失败', !ok); return refresh(); })
      .finally(function () { b.disabled = !hasKsu; });
  }

  /* ---------- 更新 ---------- */
  function checkUpdate(silent) {
    var b = $('checkBtn');
    if (!silent) {
      b.disabled = true;
      $('updateHint').textContent = '正在查询 GitHub…';
    }
    return ctl('check', 60000).then(function (r) {
      var kv = r.kv;
      if (kv.result !== 'ok') {
        $('updateHint').textContent = '检查更新失败';
        if (!silent) toast(kv.error || '检查失败', true);
        return;
      }
      $('latestVer').textContent = kv.latest || '-';
      $('assetText').textContent = kv.asset || '-';
      if (kv.abi) $('abiText').textContent = kv.abi;
      var up = kv.up_to_date === '1';
      $('updateBtn').disabled = !hasKsu || up;
      $('updateBtn').textContent = up ? '已是最新' : '立即更新';
      $('updateHint').textContent = up ? '当前已是最新版本。' : '发现新版本，可直接更新。';
    }).catch(function (e) {
      if (!silent) toast('检查失败: ' + e, true);
    }).finally(function () { b.disabled = !hasKsu; });
  }

  function stageName(s) {
    return {
      resolve: '获取版本信息',
      download: '下载二进制',
      extract: '解压',
      stop: '停止服务',
      replace: '替换二进制',
      start: '启动服务',
      copy: '复制数据'
    }[s] || s;
  }

  function startProgress() {
    $('updateProgress').className = 'progress show';
    stopProgress();
    progTimer = setInterval(function () {
      sh('cat ' + PROGRESS + ' 2>/dev/null', 5000).then(function (r) {
        var m = (r.stdout || '').match(/stage=(\S+)/);
        var d = (r.stdout || '').match(/detail=(.*)/);
        if (m) $('updateHint').textContent = '正在' + stageName(m[1]) + (d ? '：' + d[1] : '') + '…';
      });
    }, 1200);
  }
  function stopProgress() {
    if (progTimer) { clearInterval(progTimer); progTimer = null; }
    $('updateProgress').className = 'progress';
  }

  function doUpdate() {
    var b = $('updateBtn');
    if (b.dataset.confirm !== '1') {
      b.dataset.confirm = '1';
      b.textContent = '再点一次确认';
      setTimeout(function () {
        if (b.dataset.confirm === '1') { b.dataset.confirm = '0'; b.textContent = '立即更新'; }
      }, 4000);
      return;
    }
    b.dataset.confirm = '0';
    b.disabled = true;
    b.textContent = '更新中…';
    startProgress();
    ctl('update --force', 1800000).then(function (r) {
      var kv = r.kv;
      stopProgress();
      if (kv.result === 'ok') {
        toast('已更新到 ' + (kv.current || ''));
        $('updateWarn').style.display = 'none';
      } else {
        toast(kv.error || '更新失败', true);
        $('updateWarn').textContent = kv.error || '更新失败';
        $('updateWarn').style.display = 'block';
      }
      return refresh().then(function () {
        $('updateBtn').disabled = !hasKsu;
        $('updateBtn').textContent = '立即更新';
      });
    }).catch(function (e) {
      stopProgress();
      toast('更新失败: ' + e, true);
      b.disabled = false;
      b.textContent = '立即更新';
    });
  }

  /* ---------- 路径体检 ---------- */
  function fmtSize(n) {
    n = Number(n) || 0;
    if (n >= 1048576) return (n / 1048576).toFixed(1) + ' MB';
    if (n >= 1024) return (n / 1024).toFixed(0) + ' KB';
    return n + ' B';
  }

  // 路径体检要 find 整个数据目录，文件多的时候要好几秒；缓存 60 秒，
  // 迁移/清理这类动作传 force=true 强制重扫
  var SCAN_CACHE_KEY = 'ol_scan_v1';
  var scanCache = { at: 0, bins: [], datas: [] };

  function loadScan(force) {
    // 跨会话先铺上次的结果（10 分钟内），再后台重扫，避免一打开就是"加载中…"
    if (!force && !scanCache.at) {
      try {
        var c = JSON.parse(localStorage.getItem(SCAN_CACHE_KEY) || 'null');
        if (c && c.bins && (Date.now() - c.at) < 600000) {
          scanCache = { at: 0, bins: c.bins, datas: c.datas };
          renderScanBins(c.bins);
          renderScanData(c.datas);
        }
      } catch (e) {}
    }
    if (!force && scanCache.at && (Date.now() - scanCache.at) < 60000) {
      renderScanBins(scanCache.bins);
      renderScanData(scanCache.datas);
      return Promise.resolve();
    }
    return ctl('scan', 60000).then(function (r) {
      var bins = [], datas = [];
      (r.raw.stdout || '').split('\n').forEach(function (l) {
        if (l.indexOf('item=') !== 0) return;
        var p = l.slice(5).split('|');
        if (p[0] === 'bin') bins.push({ path: p[1], size: p[2], cur: p[3] === '1' });
        else if (p[0] === 'data') datas.push({ path: p[1], files: p[2], mt: p[3], cur: p[4] === '1' });
      });
      scanCache = { at: Date.now(), bins: bins, datas: datas };
      try {
        localStorage.setItem(SCAN_CACHE_KEY, JSON.stringify({ at: Date.now(), bins: bins, datas: datas }));
      } catch (e) {}
      renderScanBins(bins);
      renderScanData(datas);
    }).catch(function (e) {
      $('scanBins').textContent = '扫描失败：' + e;
      $('scanData').textContent = '';
    });
  }

  function renderScanBins(list) {
    var box = $('scanBins');
    box.textContent = '';
    if (!list.length) {
      box.textContent = '没有找到二进制文件';
      return;
    }
    list.forEach(function (b) {
      var item = document.createElement('div');
      item.className = 'scanitem';

      var p = document.createElement('div');
      p.className = 'scanpath';
      p.textContent = b.path;
      p.onclick = function () { copyText(b.path); };

      var foot = document.createElement('div');
      foot.className = 'scanfoot';
      var meta = document.createElement('span');
      meta.className = 'scanmeta';
      meta.textContent = fmtSize(b.size);
      var tag = document.createElement('span');
      tag.className = b.cur ? 'chip' : 'chip gray';
      tag.textContent = b.cur ? '当前' : '多余';
      foot.appendChild(meta);
      foot.appendChild(tag);

      item.appendChild(p);
      item.appendChild(foot);
      box.appendChild(item);
    });
  }

  function renderScanData(list) {
    var box = $('scanData');
    box.textContent = '';
    if (!list.length) {
      box.textContent = '没有找到数据目录';
      return;
    }
    list.forEach(function (d) {
      var item = document.createElement('div');
      item.className = 'scanitem';

      var p = document.createElement('div');
      p.className = 'scanpath';
      p.textContent = d.path;
      p.onclick = function () { copyText(d.path); };

      var foot = document.createElement('div');
      foot.className = 'scanfoot';
      var meta = document.createElement('span');
      meta.className = 'scanmeta';
      meta.textContent = d.files + ' 个文件 · db ' + (d.mt || '-');
      foot.appendChild(meta);

      if (d.cur) {
        var t = document.createElement('span');
        t.className = 'chip';
        t.textContent = '当前使用';
        foot.appendChild(t);
      } else {
        var b1 = document.createElement('button');
        b1.className = 'mini ghost';
        b1.textContent = '切换到此';
        b1.onclick = function () { useData(d.path, b1); };
        var b2 = document.createElement('button');
        b2.className = 'mini danger';
        b2.textContent = '删除';
        b2.onclick = function () { askDeleteData(d.path, item); };
        foot.appendChild(b1);
        foot.appendChild(b2);
      }

      item.appendChild(p);
      item.appendChild(foot);
      box.appendChild(item);
    });
  }

  function useData(path, btn) {
    if (btn.dataset.confirm !== '1') {
      btn.dataset.confirm = '1';
      btn.textContent = '确认切换？';
      setTimeout(function () {
        if (btn.dataset.confirm === '1') {
          btn.dataset.confirm = '0';
          btn.textContent = '切换到此';
        }
      }, 4000);
      return;
    }
    btn.dataset.confirm = '0';
    btn.disabled = true;
    btn.textContent = '切换中…';
    ctl("use-data '" + b64utf8(path) + "'", 120000).then(function (r) {
      if (r.kv.result === 'ok') toast('已切换到 ' + path);
      else toast(r.kv.error || '切换失败', true);
      return refresh();
    }).finally(function () {
      btn.disabled = false;
      btn.textContent = '切换到此';
      loadScan();
    });
  }

  function askDeleteData(path, wrap) {
    if (wrap.querySelector('.scanconfirm')) return;
    var box = document.createElement('div');
    box.className = 'scanconfirm';

    var tip = document.createElement('div');
    tip.className = 'hint';
    tip.textContent = '删除不可恢复。请输入下面的目录名确认：' + path;

    var inp = document.createElement('input');
    inp.placeholder = path;
    inp.style.marginTop = '8px';

    var ok = document.createElement('button');
    ok.className = 'mini danger';
    ok.textContent = '确认删除';
    ok.onclick = function () {
      if (inp.value.trim() !== path) return toast('路径不一致，已取消', true);
      ok.disabled = true;
      ok.textContent = '删除中…';
      ctl("delete-data '" + b64utf8(path) + "'", 120000).then(function (r) {
        if (r.kv.result === 'ok') toast('已删除 ' + path);
        else toast(r.kv.error || '删除失败', true);
        return refresh();
      }).finally(function () {
        box.remove();
        loadScan();
      });
    };

    var cancel = document.createElement('button');
    cancel.className = 'mini ghost';
    cancel.textContent = '取消';
    cancel.onclick = function () { box.remove(); };

    var btns = document.createElement('div');
    btns.className = 'scanacts';
    btns.appendChild(ok);
    btns.appendChild(cancel);

    box.appendChild(tip);
    box.appendChild(inp);
    box.appendChild(btns);
    wrap.appendChild(box);
  }

  function cleanBins() {
    var b = $('cleanBinsBtn');
    if (b.dataset.confirm !== '1') {
      b.dataset.confirm = '1';
      b.textContent = '确认清理？';
      setTimeout(function () {
        if (b.dataset.confirm === '1') {
          b.dataset.confirm = '0';
          b.textContent = '清理其余副本';
        }
      }, 4000);
      return;
    }
    b.dataset.confirm = '0';
    b.disabled = true;
    b.textContent = '清理中…';
    ctl('clean-bins', 60000).then(function (r) {
      if (r.kv.result === 'ok') toast('已清理 ' + (r.kv.count || 0) + ' 份多余二进制');
      else toast(r.kv.error || '清理失败', true);
    }).finally(function () {
      b.disabled = false;
      b.textContent = '清理其余副本';
      loadScan();
    });
  }

  /* ---------- 所有版本（含回退） ---------- */
  var VER_CACHE_KEY = 'ol_versions_v1';
  var verRows = null;

  function sortVersions(rows) {
    // 版本号降序（HTML 兜底时没有日期，顺序也不保证）
    rows.sort(function (a, b) {
      var va = (a.split('|')[0] || '').replace(/^v/, '').split('.').map(Number);
      var vb = (b.split('|')[0] || '').replace(/^v/, '').split('.').map(Number);
      for (var i = 0; i < 3; i++) {
        var x = va[i] || 0, y = vb[i] || 0;
        if (x !== y) return y - x;
      }
      return 0;
    });
    return rows;
  }

  function renderVersions(rows) {
    var box = $('verList');
    if (!box || !rows || !rows.length) return;
    var cur = state.version || '';
    box.textContent = '';
    rows.forEach(function (line) {
      var p = line.split('|');
      var ver = (p[0] || '').trim();
      var date = (p[1] || '').trim();
      if (!ver) return;
      var row = document.createElement('div');
      row.className = 'verrow';
      var name = document.createElement('span');
      name.className = 'ver';
      name.textContent = ver;
      var d = document.createElement('span');
      d.className = 'date';
      d.textContent = date || '-';
      row.appendChild(name);
      row.appendChild(d);
      if (ver === cur) {
        var tag = document.createElement('span');
        tag.className = 'chip';
        tag.textContent = '当前';
        row.appendChild(tag);
      } else {
        var btn = document.createElement('button');
        btn.className = 'mini';
        btn.textContent = '安装';
        btn.onclick = function () { installVersion(ver, btn); };
        row.appendChild(btn);
      }
      box.appendChild(row);
    });
  }

  function loadVersions() {
    var box = $('verList');
    if (!box) return Promise.resolve();
    // 先用上次的结果铺满，避免每次都盯着"加载中…"等 5MB 的 releases JSON
    if (!verRows) {
      try {
        var c = JSON.parse(localStorage.getItem(VER_CACHE_KEY) || 'null');
        if (c && c.rows && c.rows.length) {
          verRows = c.rows;
          renderVersions(verRows);
        }
      } catch (e) {}
    }
    if (!verRows) box.textContent = '加载中…';
    return ctl('versions', 60000).then(function (r) {
      var rows = (r.raw.stdout || '').split('\n').filter(function (l) {
        return l && l.indexOf('=') < 0;
      });
      sortVersions(rows);
      if (!rows.length) {
        // 有缓存就保留缓存，只有一次都没成功过才显示错误
        if (!verRows) {
          var msg = r.kv.error || '没有获取到版本列表';
          if (r.kv.debug) msg += '\n' + r.kv.debug;
          box.textContent = msg;
        }
        return;
      }
      verRows = rows;
      try {
        localStorage.setItem(VER_CACHE_KEY, JSON.stringify({ at: Date.now(), rows: rows }));
      } catch (e) {}
      renderVersions(rows);
    }).catch(function (e) {
      if (!verRows) box.textContent = '获取失败：' + e;
    });
  }

  function installVersion(ver, btn) {
    if (btn.dataset.confirm !== '1') {
      btn.dataset.confirm = '1';
      btn.textContent = '确认？';
      setTimeout(function () {
        if (btn.dataset.confirm === '1') {
          btn.dataset.confirm = '0';
          btn.textContent = '安装';
        }
      }, 4000);
      return;
    }
    btn.dataset.confirm = '0';
    btn.disabled = true;
    btn.textContent = '安装中…';
    $('updateHint').textContent = '正在切换到 ' + ver + '…';
    startProgress();
    ctl("update --tag '" + ver + "' --force", 1800000).then(function (r) {
      stopProgress();
      if (r.kv.result === 'ok') {
        toast('已切换到 ' + (r.kv.current || ver));
        $('updateWarn').style.display = 'none';
      } else {
        toast(r.kv.error || '切换失败', true);
        $('updateWarn').textContent = r.kv.error || '切换失败';
        $('updateWarn').style.display = 'block';
      }
      return refresh();
    }).finally(function () {
      btn.disabled = false;
      btn.textContent = '安装';
      loadVersions();
    });
  }

  /* ---------- 配置 ---------- */
  function loadConfig() {
    return ctl('config-get', 20000).then(function (r) {
      if (r.kv.result === 'ok') renderConfig(r.kv);
    });
  }

  function saveConfig() {
    var port = $('cfgPort').value.trim();
    var token = $('cfgToken').value.trim();
    var path = $('cfgPath').value.trim();
    var presets = $('cfgPresets').value.trim();

    if (!/^\d{1,5}$/.test(port) || +port < 1 || +port > 65535) return toast('端口不合法', true);
    if (token && !/^[A-Za-z0-9._-]+$/.test(token)) return toast('Token 含非法字符', true);
    if (!/^\/[A-Za-z0-9_\-./\u4e00-\u9fa5]*$/.test(path)) return toast('路径不合法', true);
    if (presets && !/^\/[A-Za-z0-9_\-./\u4e00-\u9fa5]*(,\/[A-Za-z0-9_\-./\u4e00-\u9fa5]*)*$/.test(presets)) {
      return toast('预设路径不合法', true);
    }

    var body = [
      'HOST=127.0.0.1',
      'PORT=' + port,
      'TOKEN=' + token,
      'PATH=' + path,
      'TOOL=' + $('toolSelect').dataset.value,
      'DELETE_POLICY=' + $('policySelect').dataset.value,
      'PRESET_PATHS=' + presets
    ].join('\n') + '\n';

    var b = $('saveCfgBtn');
    b.disabled = true;
    ctl("config-save '" + b64utf8(body) + "'", 30000).then(function (r) {
      toast(r.kv.result === 'ok' ? '配置已保存' : (r.kv.error || '保存失败'), r.kv.result !== 'ok');
    }).finally(function () { b.disabled = false; });
  }

  /* ---------- 密码 ---------- */
  function changePassword() {
    var uname = $('newUser').value.trim();
    var p1 = $('newPwd').value;
    var p2 = $('newPwd2').value;
    if (uname && !/^[A-Za-z0-9_.-]{3,32}$/.test(uname)) return toast('用户名不合法（3-32 位字母数字 _ . -）', true);
    if (p1.length < 8) return toast('密码至少 8 位', true);
    if (p1 !== p2) return toast('两次输入不一致', true);

    var args = "passwd '" + b64utf8(p1) + "'";
    if (uname) args += " '" + b64utf8(uname) + "'";

    var b = $('pwdBtn');
    b.disabled = true;
    b.textContent = '修改中…';
    ctl(args, 180000).then(function (r) {
      if (r.kv.result === 'ok') {
        var via = r.kv.method === 'api' ? '在线生效，未重启' : 'CLI 方式，已重启服务';
        toast((uname ? '用户名和密码已更新' : '密码已更新') + '（' + via + '）');
        $('newPwd').value = '';
        $('newPwd2').value = '';
        $('newUser').value = '';
        if (uname) $('newUser').placeholder = uname;
      } else {
        toast(r.kv.error || r.kv.api_error || '修改失败', true);
      }
      return refresh();
    }).finally(function () {
      b.disabled = !hasKsu;
      b.textContent = '修改密码';
    });
  }

  /* ---------- 存储 ---------- */
  function loadStorages() {
    var box = $('storageList');
    box.textContent = '加载中…';
    api('GET', '/api/admin/storage/list?page=1&per_page=100').then(function (res) {
      var list = Array.isArray(res.data) ? res.data
        : (res.data && Array.isArray(res.data.content) ? res.data.content : null);
      if (res.code !== 200 || !list) {
        box.textContent = apiHint(res);
        return;
      }
      box.textContent = '';
      if (!list.length) {
        box.textContent = '还没有配置存储。';
        return;
      }
      list.forEach(function (s) {
        var row = document.createElement('div');
        row.className = 'kv';

        var left = document.createElement('span');
        left.textContent = (s.mount_path || '/') + ' · ' + (s.driver || '?');

        var right = document.createElement('span');
        right.style.cssText = 'display:flex;align-items:center;gap:8px;justify-content:flex-end';

        var badge = document.createElement('span');
        badge.className = 'badge ' + (s.disabled ? 'err' : 'ok');
        badge.textContent = s.disabled ? '已禁用' : '启用';

        var btn = document.createElement('button');
        btn.className = 'ghost';
        btn.style.cssText = 'min-width:auto;padding:5px 10px;font-size:12px;min-height:32px';
        btn.textContent = s.disabled ? '启用' : '禁用';
        btn.onclick = function () { toggleStorage(s, btn); };

        right.appendChild(badge);
        right.appendChild(btn);
        row.appendChild(left);
        row.appendChild(right);
        box.appendChild(row);
      });
    });
  }

  function toggleStorage(s, btn) {
    var path = s.disabled ? '/api/admin/storage/enable' : '/api/admin/storage/disable';
    btn.disabled = true;
    api('POST', path, { id: s.id }).then(function (res) {
      toast(res.code === 200 ? (s.disabled ? '已启用' : '已禁用') : (res.message || '操作失败'), res.code !== 200);
      loadStorages();
    });
  }

  function reloadStorages() {
    var b = $('storageReload');
    b.disabled = true;
    api('POST', '/api/admin/storage/load_all', {}).then(function (res) {
      toast(res.code === 200 ? '已触发重载' : (res.message || '重载失败'), res.code !== 200);
      loadStorages();
    }).finally(function () { b.disabled = !hasKsu; });
  }

  /* ---------- 离线任务 ---------- */
  function loadTasks() {
    var box = $('taskList');
    box.textContent = '加载中…';
    api('GET', '/api/admin/task/offline_download/undone?page=1&per_page=100').then(function (res) {
      var list = Array.isArray(res.data) ? res.data
        : (res.data && Array.isArray(res.data.content) ? res.data.content : null);
      if (res.code !== 200 || !list) {
        box.textContent = apiHint(res);
        return;
      }
      box.textContent = '';
      if (!list.length) {
        box.textContent = '没有进行中的任务。';
        return;
      }
      list.forEach(function (t) {
        var row = document.createElement('div');
        row.className = 'kv';

        var left = document.createElement('span');
        left.textContent = (t.name || t.id) + ' · ' + (t.status || '');

        var right = document.createElement('span');
        right.style.cssText = 'display:flex;align-items:center;gap:8px;justify-content:flex-end';

        var pct = document.createElement('span');
        pct.className = 'muted';
        pct.textContent = Math.round(t.progress || 0) + '%';

        var btn = document.createElement('button');
        btn.className = 'danger';
        btn.style.cssText = 'min-width:auto;padding:5px 10px;font-size:12px;min-height:32px';
        btn.textContent = '取消';
        btn.onclick = function () { cancelTask(t, btn); };

        right.appendChild(pct);
        right.appendChild(btn);
        row.appendChild(left);
        row.appendChild(right);
        box.appendChild(row);
      });
    });
  }

  function cancelTask(t, btn) {
    btn.disabled = true;
    api('POST', '/api/admin/task/offline_download/cancel', { id: t.id }).then(function (res) {
      toast(res.code === 200 ? '已取消' : (res.message || '取消失败'), res.code !== 200);
      loadTasks();
    });
  }

  /* ---------- 迁移 ---------- */
  function migrateData() {
    var box = $('dataDirChips');
    var dir = ((box && box.dataset.value) || '').trim();
    if (!dir) return toast('请先点选目标目录', true);
    if (!/^\/(data|sdcard|storage)\/[A-Za-z0-9_\-./]*$/.test(dir)) return toast('目标目录不合法', true);
    var b = $('migrateDataBtn');
    if (b.dataset.confirm !== '1') {
      b.dataset.confirm = '1';
      b.textContent = '再点一次确认';
      setTimeout(function () { b.dataset.confirm = '0'; b.textContent = '开始迁移'; }, 4000);
      return;
    }
    b.dataset.confirm = '0';
    b.disabled = true;
    b.textContent = '迁移中…';
    ctl("migrate-data '" + b64utf8(dir) + "'", 1800000).then(function (r) {
      if (r.kv.result === 'ok') {
        var msg = '已迁移到 ' + (r.kv.new_data_dir || dir);
        if (r.kv.source_removed === '1') msg += '（源目录已删除）';
        if (r.kv.bin_moved) msg += '，二进制同步到 ' + r.kv.bin_moved;
        toast(msg);
        if (box) {
          box.dataset.value = '';
          box.querySelectorAll('.chip-btn').forEach(function (x) { x.classList.remove('active'); });
        }
      } else {
        toast(r.kv.error || '迁移失败', true);
      }
      return refreshAll();
    }).finally(function () {
      b.disabled = !hasKsu;
      b.textContent = '开始迁移';
    });
  }

  function migrateBin() {
    var box = $('binChips');
    var p = ((box && box.dataset.value) || '').trim();
    if (!p) return toast('请先点选目标位置', true);
    if (!/^\/(data|system\/bin)\/[A-Za-z0-9_\-./]*$/.test(p)) return toast('目标路径不合法', true);
    var b = $('migrateBinBtn');
    if (b.dataset.confirm !== '1') {
      b.dataset.confirm = '1';
      b.textContent = '再点一次确认';
      setTimeout(function () { b.dataset.confirm = '0'; b.textContent = '开始迁移'; }, 4000);
      return;
    }
    b.dataset.confirm = '0';
    b.disabled = true;
    b.textContent = '迁移中…';
    ctl("migrate-bin '" + b64utf8(p) + "'", 180000).then(function (r) {
      if (r.kv.result === 'ok') {
        toast(r.kv.old_bin_removed ? '二进制已迁移，旧文件已删除' : '二进制已迁移');
        if (box) {
          box.dataset.value = '';
          box.querySelectorAll('.chip-btn').forEach(function (x) { x.classList.remove('active'); });
        }
      } else {
        toast(r.kv.error || '迁移失败', true);
      }
      return refreshAll();
    }).finally(function () {
      b.disabled = !hasKsu;
      b.textContent = '开始迁移';
    });
  }

  /* ---------- 路径修复 ---------- */
  function fixPaths() {
    var b = $('fixPathsBtn');
    b.disabled = true;
    b.textContent = '检查中…';
    ctl('fix-paths', 60000).then(function (r) {
      if (r.kv.result !== 'ok') {
        toast(r.kv.error || '修复失败', true);
        return;
      }
      if (r.kv.fixed === '1') {
        toast('已修复：' + [r.kv.fixed_action_bin ? 'action.sh' : '', r.kv.fixed_config ? 'config.json' : ''].filter(Boolean).join('、'));
      } else {
        toast('路径一致，无需修复');
      }
      return refresh();
    }).finally(function () {
      b.disabled = !hasKsu;
      b.textContent = '检查并修复';
    });
  }

  /* ---------- 日志 ---------- */
  var logWhich = 'service';

  function loadLog() {
    return sh("sh '" + CONTROL + "' logs 200 " + logWhich, 20000).then(function (r) {
      $('logBox').textContent = r.stdout || '(空)';
    });
  }

  function clearLog() {
    if (!hasKsu) return toast('没有 root 接口', true);
    var f = logWhich === 'openlist' ? 'openlist.log' : 'service.log';
    sh(': > ' + MODDIR + '/' + f, 10000).then(function () {
      $('logBox').textContent = '(空)';
      toast('日志已清空');
    });
  }

  /* ---------- 绑定 ---------- */
  function init() {
    $('themeBtn').onclick = cycleTheme;
    applyTheme();
    initSelects();
    initPresets();

    document.querySelectorAll('#logTabs .chip-btn').forEach(function (b) {
      b.onclick = function () {
        logWhich = b.dataset.log;
        document.querySelectorAll('#logTabs .chip-btn').forEach(function (x) { x.classList.remove('active'); });
        b.classList.add('active');
        loadLog();
      };
    });
    $('modeChip').textContent = hasKsu ? 'KernelSU / APatch' : '无 root 接口';
    ['toggleBtn', 'restartBtn', 'checkBtn', 'updateBtn', 'saveCfgBtn', 'pwdBtn', 'migrateDataBtn', 'migrateBinBtn', 'fixPathsBtn']
      .forEach(function (id) { $(id).disabled = true; });

    if (!hasKsu) {
      $('stateText').textContent = '未连接';
      $('addrText').textContent = '需要 KernelSU 或 APatch';
      $('updateHint').textContent = '当前环境没有 ksu.exec，无法执行命令。请从 KernelSU/APatch 管理器的 WebUI 入口打开。';
      $('logBox').textContent = '(无 root 接口，无法读取)';
      $('storageList').textContent = '(无 root 接口，无法读取)';
      $('taskList').textContent = '(无 root 接口，无法读取)';
      return;
    }

    $('toggleBtn').disabled = false;
    $('restartBtn').disabled = false;
    $('checkBtn').disabled = false;
    $('saveCfgBtn').disabled = false;
    $('pwdBtn').disabled = false;
    $('migrateDataBtn').disabled = false;
    $('migrateBinBtn').disabled = false;
    $('fixPathsBtn').disabled = false;

    $('toggleBtn').onclick = toggleService;
    $('restartBtn').onclick = restart;
    $('refreshBtn').onclick = function () { refresh(); loadLog(); };
    $('checkBtn').onclick = checkUpdate;
    $('cleanBinsBtn').onclick = cleanBins;
    $('updateBtn').onclick = doUpdate;
    $('saveCfgBtn').onclick = saveConfig;
    $('pwdBtn').onclick = changePassword;
    $('migrateDataBtn').onclick = migrateData;
    $('migrateBinBtn').onclick = migrateBin;
    $('fixPathsBtn').onclick = fixPaths;
    $('logRefresh').onclick = loadLog;
    $('logClear').onclick = clearLog;
    $('storageRefresh').onclick = loadStorages;
    $('storageReload').onclick = reloadStorages;
    $('taskRefresh').onclick = loadTasks;
    $('openBtn').onclick = function () {
      if (state.running !== '1') return toast('服务未运行', true);
      var url = 'http://' + state.ip + ':' + state.port;
      sh("am start -a android.intent.action.VIEW -d '" + url + "'", 15000).then(function (r) {
        if (r.errno !== 0) toast('打开失败: ' + (r.stderr || ''), true);
      });
    };

    // 各区块并行加载：串行的话 scan + versions + 存储/任务加起来能拖到几十秒，
    // 页面上就一直挂着"加载中…"
    refresh();
    checkUpdate(true);
    loadScan();
    loadVersions();
    loadConfig();
    loadLog();
    loadStorages();
    loadTasks();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
