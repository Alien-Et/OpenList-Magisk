/* OpenList 模块 WebUI
 * 仅做界面与参数校验，所有实际操作交给 control.sh
 */
(function () {
  'use strict';

  var MODDIR = '/data/adb/modules/openlist';
  var CONTROL = MODDIR + '/control.sh';
  var PROGRESS = '/data/local/tmp/openlist_update.progress';
  var hasKsu = typeof window.ksu !== 'undefined';

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

  /* ---------- KernelSU / APatch 兼容层 ---------- */
  var cbSeq = 0;
  function sh(cmd, timeout) {
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
    return sh("sh '" + CONTROL + "' " + args, timeout || 30000).then(function (r) {
      var kv = {};
      (r.stdout || '').split('\n').forEach(function (line) {
        var i = line.indexOf('=');
        if (i > 0) kv[line.slice(0, i)] = line.slice(i + 1);
      });
      return { raw: r, kv: kv };
    });
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
    $('dataDirText').textContent = '数据目录 ' + (kv.data_dir || '-');
    $('modDirText').textContent = kv.module_dir || MODDIR;
    $('binText').textContent = kv.bin || '-';
    $('curVer').textContent = state.version;
    if (kv.abi) $('abiText').textContent = kv.abi;

    var b = $('toggleBtn');
    b.textContent = state.running === '1' ? '停止服务' : '启动服务';
    b.className = state.running === '1' ? 'danger' : '';
    b.disabled = !hasKsu;
    $('restartBtn').disabled = !hasKsu;
  }

  function renderConfig(kv) {
    $('cfgPort').value = kv.PORT || '5244';
    $('cfgToken').value = kv.TOKEN || '';
    $('cfgPath').value = kv.PATH || '/115/影视/';
    if (kv.TOOL) $('cfgTool').value = kv.TOOL;
    if (kv.DELETE_POLICY) $('cfgPolicy').value = kv.DELETE_POLICY;
    $('cfgPresets').value = kv.PRESET_PATHS || '/115/影视/,/115/';
  }

  /* ---------- 状态 ---------- */
  function refresh() {
    return ctl('status', 20000).then(function (r) {
      if (r.kv.result === 'ok') renderStatus(r.kv);
      else toast(r.kv.error || '读取状态失败', true);
    }).catch(function (e) { toast('读取失败: ' + e, true); });
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
  function checkUpdate() {
    var b = $('checkBtn');
    b.disabled = true;
    $('updateHint').textContent = '正在查询 GitHub…';
    ctl('check', 60000).then(function (r) {
      var kv = r.kv;
      if (kv.result !== 'ok') {
        $('updateHint').textContent = '检查失败';
        return toast(kv.error || '检查失败', true);
      }
      $('latestVer').textContent = kv.latest || '-';
      $('assetText').textContent = kv.asset || '-';
      if (kv.abi) $('abiText').textContent = kv.abi;
      var up = kv.up_to_date === '1';
      $('updateBtn').disabled = !hasKsu || up;
      $('updateBtn').textContent = up ? '已是最新' : '立即更新';
      $('updateHint').textContent = up ? '当前已是最新版本。' : '发现新版本，可直接更新。';
    }).catch(function (e) {
      toast('检查失败: ' + e, true);
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
      'TOOL=' + $('cfgTool').value,
      'DELETE_POLICY=' + $('cfgPolicy').value,
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
    var p1 = $('newPwd').value;
    var p2 = $('newPwd2').value;
    if (p1.length < 8) return toast('密码至少 8 位', true);
    if (p1 !== p2) return toast('两次输入不一致', true);

    var b = $('pwdBtn');
    b.disabled = true;
    b.textContent = '修改中…';
    ctl("passwd '" + b64utf8(p1) + "'", 180000).then(function (r) {
      if (r.kv.result === 'ok') {
        toast('密码已修改');
        $('newPwd').value = '';
        $('newPwd2').value = '';
      } else {
        toast(r.kv.error || '改密失败', true);
      }
      return refresh();
    }).finally(function () {
      b.disabled = !hasKsu;
      b.textContent = '修改密码';
    });
  }

  /* ---------- 迁移 ---------- */
  function migrateData() {
    var dir = $('newDataDir').value.trim();
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
        toast('已迁移到 ' + (r.kv.new_data_dir || dir));
        $('newDataDir').value = '';
      } else {
        toast(r.kv.error || '迁移失败', true);
      }
      return refresh();
    }).finally(function () {
      b.disabled = !hasKsu;
      b.textContent = '开始迁移';
    });
  }

  function migrateBin() {
    var p = $('newBinPath').value.trim();
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
        toast('二进制已迁移');
        $('newBinPath').value = '';
      } else {
        toast(r.kv.error || '迁移失败', true);
      }
      return refresh();
    }).finally(function () {
      b.disabled = !hasKsu;
      b.textContent = '开始迁移';
    });
  }

  /* ---------- 日志 ---------- */
  function loadLog() {
    return sh("sh '" + CONTROL + "' logs 200", 20000).then(function (r) {
      $('logBox').textContent = r.stdout || '(空)';
    });
  }

  function clearLog() {
    if (!hasKsu) return toast('没有 root 接口', true);
    sh(': > ' + MODDIR + '/service.log', 10000).then(function () {
      $('logBox').textContent = '(空)';
      toast('日志已清空');
    });
  }

  /* ---------- 绑定 ---------- */
  function init() {
    $('modeChip').textContent = hasKsu ? 'KernelSU / APatch' : '无 root 接口';
    if (!hasKsu) {
      $('updateHint').textContent = '当前环境不支持 WebUI 执行命令（需要 KernelSU 或 APatch）。';
    }
    ['toggleBtn', 'restartBtn', 'checkBtn', 'updateBtn', 'saveCfgBtn', 'pwdBtn', 'migrateDataBtn', 'migrateBinBtn']
      .forEach(function (id) { $(id).disabled = !hasKsu; });

    $('toggleBtn').onclick = toggleService;
    $('restartBtn').onclick = restart;
    $('refreshBtn').onclick = function () { refresh(); loadLog(); };
    $('checkBtn').onclick = checkUpdate;
    $('updateBtn').onclick = doUpdate;
    $('saveCfgBtn').onclick = saveConfig;
    $('pwdBtn').onclick = changePassword;
    $('migrateDataBtn').onclick = migrateData;
    $('migrateBinBtn').onclick = migrateBin;
    $('logRefresh').onclick = loadLog;
    $('logClear').onclick = clearLog;
    $('openBtn').onclick = function () {
      if (state.running !== '1') return toast('服务未运行', true);
      var url = 'http://' + state.ip + ':' + state.port;
      sh("am start -a android.intent.action.VIEW -d '" + url + "'", 15000).then(function (r) {
        if (r.errno !== 0) toast('打开失败: ' + (r.stderr || ''), true);
      });
    };

    refresh().then(loadConfig).then(loadLog);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
