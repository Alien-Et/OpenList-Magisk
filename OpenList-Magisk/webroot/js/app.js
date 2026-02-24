// OpenList 管理面板 - 调试版 v4.0
// 添加了详细的错误处理和调试功能
// 使用通用 Root Shell 兼容层

// ====================== 
// 通用 Root Shell 兼容层 
// 自动适配 KernelSU / Magisk / APatch 
// ====================== 
const RootShell = (function() { 
    // 环境判断 
    const env = (() => { 
        if (typeof ksu !== 'undefined') return 'KSU'; 
        if (typeof Magisk !== 'undefined') return 'MAGISK'; 
        if (typeof APatch !== 'undefined') return 'APATCH'; 
        return 'UNKNOWN'; 
    })(); 
 
    // 统一 Promise exec（带超时保护）
    async function exec(command, timeout = 10000) { 
        console.log('[RootShell] Executing:', command);
        
        switch (env) { 
            case 'KSU': 
                return new Promise((resolve, reject) => { 
                    const cb = `exec_cb_${Date.now()}`; 
                    window[cb] = (errno, out, err) => { 
                        delete window[cb]; 
                        if (errno === 0) {
                            resolve({ code: 0, data: out });
                        } else {
                            resolve({ code: errno, data: err || out });
                        }
                    }; 
                    try { 
                        ksu.exec(command, '{}', cb); 
                    } catch (e) { 
                        delete window[cb]; 
                        resolve({ code: 1, data: 'Exception: ' + e.message });
                    } 
                }); 
 
            case 'MAGISK': 
                return new Promise((resolve, reject) => { 
                    try { 
                        const res = Magisk.exec(command);
                        console.log('[RootShell] Magisk result:', res);
                        resolve(res || { code: 1, data: 'No result' });
                    } catch (e) { 
                        resolve({ code: 1, data: 'Exception: ' + e.message });
                    } 
                }); 
 
            case 'APATCH': 
                return new Promise((resolve, reject) => { 
                    try { 
                        const res = APatch.exec(command);
                        console.log('[RootShell] APatch result:', res);
                        resolve(res || { code: 1, data: 'No result' });
                    } catch (e) { 
                        resolve({ code: 1, data: 'Exception: ' + e.message });
                    } 
                }); 
 
            default: 
                return Promise.resolve({ code: 1, data: '不支持的 Root 环境' });
        } 
    } 
 
    // 统一 spawn（仅 KSU 原生支持，其余降级为 exec 模拟流） 
    function spawn(command, args = []) { 
        const cmdStr = [command, ...args].join(' '); 
        const child = createChildProcess(); 
 
        if (env === 'KSU') { 
            const cb = `spawn_cb_${Date.now()}`; 
            window[cb] = child; 
            child.on('exit', () => delete window[cb]); 
            try { 
                ksu.spawn(command, JSON.stringify(args), '{}', cb); 
            } catch (e) { 
                child.emit('error', e); 
                delete window[cb]; 
            } 
        } else { 
            // Magisk / APatch 无原生 spawn，用 exec 模拟输出 
            (async () => { 
                try { 
                    const out = await exec(cmdStr); 
                    child.stdout.emit('data', out.data || ''); 
                    child.emit('exit', out.code || 0); 
                } catch (e) { 
                    child.stderr.emit('data', e.message); 
                    child.emit('exit', 1); 
                } 
            })(); 
        } 
 
        return child; 
    } 
 
    // 子进程结构
    function createChildProcess() { 
        const events = {}; 
        const ioEvents = { stdout: {}, stderr: {}, stdin: {} }; 
 
        const child = { 
            on(evt, fn) { events[evt] = events[evt] || []; events[evt].push(fn); }, 
            emit(evt, ...args) { (events[evt] || []).forEach(fn => fn(...args)); }, 
            stdout: { 
                on(evt, fn) { ioEvents.stdout[evt] = ioEvents.stdout[evt] || []; ioEvents.stdout[evt].push(fn); }, 
                emit(evt, ...args) { (ioEvents.stdout[evt] || []).forEach(fn => fn(...args)); } 
            }, 
            stderr: { 
                on(evt, fn) { ioEvents.stderr[evt] = ioEvents.stderr[evt] || []; ioEvents.stderr[evt].push(fn); }, 
                emit(evt, ...args) { (ioEvents.stderr[evt] || []).forEach(fn => fn(...args)); } 
            }, 
            stdin: { on() {}, emit() {} } 
        }; 
        return child; 
    } 
 
    return { exec, spawn, env }; 
})(); 

const App = {
    config: {
        debugMode: true,  // 开启调试模式
        autoRefreshInterval: 30000,
        logRefreshInterval: 2000  // 日志刷新间隔（毫秒）
    },
    
    state: {
        env: RootShell.env,  // 使用 RootShell 的环境检测
        isRefreshing: false,
        lastError: null,
        binaryPath: null,
        dataDir: null,
        logMonitoring: false,  // 日志监控状态
        lastLogPosition: 0  // 上次读取的日志位置
    },

    // 初始化
    async init() {
        this.log('Initializing OpenList Panel v4.0');
        this.log('Root Environment:', this.state.env);
        
        try {
            await this.initializePaths();  // 初始化路径（异步）
            this.setupEventListeners();
            this.startRealTimeClock();  // 启动实时时钟
            this.startLogMonitoring();  // 启动实时日志监控
            this.refreshAll();
            
            // 自动刷新
            setInterval(() => this.refreshAll(), this.config.autoRefreshInterval);
            
            this.log('Initialization complete');
        } catch (e) {
            this.error('Initialization failed:', e);
            this.showToast('初始化失败: ' + e.message, 'error');
        }
    },
    
    // 日志函数
    log(...args) {
        if (this.config.debugMode) {
            console.log('[OpenList]', ...args);
        }
    },
    
    error(...args) {
        console.error('[OpenList Error]', ...args);
        this.state.lastError = args.join(' ');
    },
    
    // 使用 RootShell.exec 执行命令
    exec: RootShell.exec,
    
    // 使用 RootShell.spawn 执行命令
    spawn: RootShell.spawn,
    
    // 初始化二进制路径
    async initializePaths() {
        // 固定的二进制路径（按优先级）
        const binaryPaths = [
            '/data/adb/openlist/bin/openlist',
            '/data/adb/modules/openlist/bin/openlist',
            '/data/adb/modules/openlist/system/bin/openlist'
        ];
        
        // 固定的数据目录（按优先级）
        const dataDirs = [
            '/data/adb/openlist',
            '/sdcard/Android/openlist'
        ];
        
        // 检测二进制路径
        for (const path of binaryPaths) {
            const result = await this.exec(`[ -f "${path}" ] && echo "exists"`);
            if (result.code === 0 && result.data?.includes('exists')) {
                this.state.binaryPath = path;
                this.log('Found binary at:', path);
                break;
            }
        }
        
        // 检测数据目录
        for (const path of dataDirs) {
            const result = await this.exec(`[ -d "${path}" ] && echo "exists"`);
            if (result.code === 0 && result.data?.includes('exists')) {
                this.state.dataDir = path;
                this.log('Found data dir at:', path);
                break;
            }
        }
        
        // 如果没找到，使用默认值
        if (!this.state.binaryPath) {
            this.state.binaryPath = '/data/adb/openlist/bin/openlist';
        }
        if (!this.state.dataDir) {
            this.state.dataDir = '/data/adb/openlist';
        }
        
        this.log('Initialized paths:', {
            binaryPath: this.state.binaryPath,
            dataDir: this.state.dataDir
        });
    },

    // 直接调用 OpenList 二进制文件
    async callOpenList(command, ...args) {
        if (!this.state.binaryPath) {
            this.error('Binary path not initialized');
            return { error: 'Binary path not set' };
        }

        // 构建命令
        const cmdArgs = [command, ...args];
        if (this.state.dataDir) {
            cmdArgs.push('--data', `"${this.state.dataDir}"`);
        }
        
        const fullCmd = `"${this.state.binaryPath}" ${cmdArgs.join(' ')}`;
        
        this.log('OpenList call:', fullCmd);
        
        const result = await this.exec(fullCmd);
        
        // 检查执行结果
        if (!result) {
            this.error('OpenList call returned null');
            return { error: 'Command returned null' };
        }
        
        if (result.code !== 0) {
            this.error('OpenList call failed:', result.data);
            return { error: result.data || `Command failed with code ${result.code}` };
        }
        
        if (!result.data) {
            this.error('OpenList call returned empty data');
            return { error: 'Empty response from command' };
        }
        
        // 返回原始数据，因为 OpenList 输出通常是纯文本而非 JSON
        return { success: true, output: result.data.trim() };
    },
    
    // 检查服务是否运行
    async checkServiceStatus() {
        // 使用 pgrep 或 ps 检查 openlist 服务器进程（精确匹配，与 service.sh 一致）
        const result = await this.exec('pgrep -f "openlist server --data" || ps -ef | grep "openlist server --data" | grep -v grep');
        if (result.code === 0 && result.data) {
            // 提取所有 PID
            const lines = result.data.trim().split('\n');
            const pids = [];
            for (const line of lines) {
                const parts = line.trim().split(/\s+/);
                if (parts.length > 0) {
                    pids.push(parts[0]);
                }
            }
            return { running: true, pid: pids[0], pids: pids };
        }
        return { running: false, pid: null, pids: [] };
    },
    
    // 启动 OpenList 服务
    async startOpenListService() {
        if (!this.state.binaryPath) {
            return { error: 'Binary path not set' };
        }
        
        // 检查是否已经在运行（防止重复启动）
        const status = await this.checkServiceStatus();
        if (status.running) {
            this.log('Service already running, preventing duplicate start. PIDs:', status.pids);
            return { success: true, output: 'Service already running', pid: status.pid, pids: status.pids };
        }
        
        // 启动服务：二进制路径 server --data 数据目录 --log-level=info （使用spawn捕获输出）
        const dataDir = this.state.dataDir || '/data/adb/openlist';
        const cmd = `"${this.state.binaryPath}" server --data "${dataDir}" --log-level=info`;
        this.log('Starting service with command:', cmd);
        
        // 使用 spawn 启动服务并捕获输出
        const child = this.spawn('sh', ['-c', cmd]);
        
        // 保存子进程引用
        this.state.serviceChild = child;
        
        // 捕获输出并显示在日志区域
        child.stdout.on('data', (data) => {
            this.log('Service output:', data.toString());
            const logEl = document.getElementById('logContent');
            if (logEl) {
                logEl.textContent += data.toString();
                logEl.scrollTop = logEl.scrollHeight;
            }
        });
        
        child.stderr.on('data', (data) => {
            this.log('Service error:', data.toString());
            const logEl = document.getElementById('logContent');
            if (logEl) {
                logEl.textContent += data.toString();
                logEl.scrollTop = logEl.scrollHeight;
            }
        });
        
        child.on('error', (error) => {
            this.error('Service error:', error);
        });
        
        child.on('close', (code) => {
            this.log('Service exited with code:', code);
            this.state.serviceChild = null;
        });
        
        // 等待一下让服务启动
        await new Promise(resolve => setTimeout(resolve, 1500));
        
        // 检查是否启动成功
        const newStatus = await this.checkServiceStatus();
        if (newStatus.running) {
            // 更新 module.prop 文件为运行状态
            this.log('Service started successfully. PIDs:', newStatus.pids);
            try {
                await this.updateModuleProp('running', newStatus.pid);
                this.log('Module.prop updated successfully');
            } catch (e) {
                this.error('Failed to update module.prop:', e);
            }
            return { success: true, output: 'Service started', pid: newStatus.pid, pids: newStatus.pids };
        }
        
        // 如果进程检测失败，但命令执行成功，也认为启动成功
        this.log('Service started but PID not found');
        return { success: true, output: 'Service started' };
    },
    
    // 停止 OpenList 服务（使用 pkill）
    async stopOpenListService() {
        const status = await this.checkServiceStatus();
        if (!status.running) {
            this.log('Service not running');
            return { success: true, output: 'Service not running' };
        }
        
        try {
            // 杀死所有 openlist 服务器进程（精确匹配，与 service.sh 一致）
            this.log('Stopping all openlist server processes. PIDs:', status.pids);
            const result = await this.exec('pkill -f "openlist server --data"');
            
            // 等待一下让进程完全停止
            await new Promise(resolve => setTimeout(resolve, 1000));
            
            // 再次检查是否还有进程在运行
            const newStatus = await this.checkServiceStatus();
            if (!newStatus.running) {
                this.log('All openlist server processes stopped');
                // 更新 module.prop 文件为已停止状态
                try {
                    await this.updateModuleProp('stopped');
                    this.log('Module.prop updated to stopped status');
                } catch (e) {
                    this.error('Failed to update module.prop:', e);
                }
                return { success: true, output: 'Service stopped' };
            } else {
                this.error('Some openlist server processes still running. PIDs:', newStatus.pids);
                return { error: 'Failed to stop all processes' };
            }
        } catch (e) {
            this.error('Stop service error:', e);
            return { error: e.message || 'Failed to stop service' };
        }
    },
    
    // 重启 OpenList 服务（先 pkill，再启动）
    async restartOpenListService() {
        try {
            this.log('Restarting service...');
            
            // 先停止服务
            const stopResult = await this.stopOpenListService();
            this.log('Stop result:', stopResult);
            
            // 等待一下
            await new Promise(resolve => setTimeout(resolve, 800));
            
            // 启动服务
            const startResult = await this.startOpenListService();
            this.log('Start result:', startResult);
            
            return startResult;
        } catch (e) {
            this.error('Restart service error:', e);
            return { error: e.message || 'Failed to restart service' };
        }
    },
    
    // 读取日志文件
    async readLogFile() {
        // 数据目录的日志路径
        const logPaths = [
            '/data/adb/openlist/log/log.log',
            '/sdcard/Android/openlist/log/log.log'
        ];
        
        for (const logPath of logPaths) {
            const result = await this.exec(`tail -n 1000 "${logPath}" 2>/dev/null`);
            if (result.code === 0 && result.data && result.data.trim()) {
                return { success: true, output: result.data, path: logPath };
            }
        }
        
        return { error: '未找到日志文件' };
    },
    
    // 启动实时日志监控
    async startLogMonitoring() {
        if (this.state.logMonitoring) {
            this.log('Log monitoring already running');
            return;
        }
        
        const logPaths = [
            '/data/adb/openlist/log/log.log',
            '/sdcard/Android/openlist/log/log.log'
        ];
        
        for (const logPath of logPaths) {
            const result = await this.exec(`[ -f "${logPath}" ] && echo "exists"`);
            if (result.code === 0 && result.data?.includes('exists')) {
                this.state.logMonitoring = true;
                this.state.logPath = logPath;
                this.log('Starting log monitoring:', logPath);
                
                // 使用 RootShell.spawn 实时跟踪日志
                const child = this.spawn('tail', ['-f', '-n', '50', logPath]);
                
                child.stdout.on('data', (data) => {
                    const logEl = document.getElementById('logContent');
                    if (logEl) {
                        logEl.textContent = data;
                        logEl.scrollTop = logEl.scrollHeight;
                    }
                });
                
                child.on('error', (error) => {
                    this.error('Log monitoring error:', error);
                    this.state.logMonitoring = false;
                });
                
                child.on('exit', (code) => {
                    this.log('Log monitoring exited with code:', code);
                    this.state.logMonitoring = false;
                });
                
                return;
            }
        }
        
        this.error('No log file found for monitoring');
    },
    
    // 更新 module.prop 文件中的服务状态
    async updateModuleProp(status, pid = null) {
        try {
            this.log('Updating module.prop:', status, pid);
            
            // 尝试多个可能的模块属性文件路径
            const modulePropPaths = [
                '/data/adb/modules/openlist/module.prop',
                '/data/adb/openlist/module.prop'
            ];
            const repoUrl = 'https://github.com/Alien-Et/OpenList-Magisk';
            
            // 找到存在且可写的 module.prop 文件
            let modulePropPath = null;
            for (const path of modulePropPaths) {
                const checkResult = await this.exec(`[ -f "${path}" ] && echo "exists"`);
                if (checkResult.code === 0 && checkResult.data?.includes('exists')) {
                    modulePropPath = path;
                    this.log('Found module.prop at:', path);
                    break;
                }
            }
            
            if (!modulePropPath) {
                this.error('No module.prop file found');
                return { error: 'No module.prop file found' };
            }
            
            // 构建新的 description 行
            let newDescription;
            if (status === 'stopped') {
                newDescription = `description=【已停止】请点击"操作"启动程序。项目地址：${repoUrl}`;
            } else if (status === 'running' && pid) {
                try {
                    // 异步获取 IP 和端口
                    const [currentIp, port] = await Promise.all([
                        this.getCurrentIP(),
                        this.getCurrentPort(pid)
                    ]);
                    
                    // 获取数据目录
                    const dataDir = this.state.dataDir || '/data/adb/openlist';
                    
                    // 获取初始密码（如果存在）
                    let passwordText = '';
                    const passwordResult = await this.exec(`[ -f "${dataDir}/初始密码.txt" ] && cat "${dataDir}/初始密码.txt"`);
                    if (passwordResult.code === 0 && passwordResult.data) {
                        passwordText = ` | 初始密码：${passwordResult.data.trim()}`;
                    }
                    
                    // 构建描述文本
                    if (port && currentIp !== '无法获取IP') {
                        newDescription = `description=【运行中】当前地址：http://${currentIp}:${port} | PID:${pid} | 数据目录：${dataDir} | 点击▲操作关闭程序${passwordText}`;
                    } else {
                        newDescription = `description=【运行中】无法检测 openlist 地址（IP: ${currentIp}, 端口: ${port || '未知'}，PID:${pid}），请检查日志 | 数据目录：${dataDir} | 点击▲操作关闭程序${passwordText}`;
                    }
                } catch (e) {
                    this.error('Error in running status update:', e);
                    // 即使获取 IP 或端口失败，也更新为运行状态
                    const dataDir = this.state.dataDir || '/data/adb/openlist';
                    newDescription = `description=【运行中】OpenList 服务已启动 | PID:${pid} | 数据目录：${dataDir} | 点击▲操作关闭程序`;
                }
            } else {
                return { error: 'Invalid status' };
            }
            
            // 使用与 service.sh 相同的方式更新文件（不使用 sed -i）
            // 1. 读取文件内容，移除旧的 description 行
            const readResult = await this.exec(`cat "${modulePropPath}"`);
            if (readResult.code !== 0) {
                this.error('Failed to read module.prop:', readResult);
                return { error: 'Failed to read module.prop' };
            }
            
            // 2. 移除旧的 description 行，添加新的 description 行
            const lines = readResult.data.split('\n');
            const newLines = lines.filter(line => !line.startsWith('description='));
            newLines.push(newDescription);
            
            // 3. 写入临时文件
            const tempPath = `${modulePropPath}.tmp`;
            const content = newLines.join('\n');
            const writeResult = await this.exec(`echo "${content}" > "${tempPath}"`);
            if (writeResult.code !== 0) {
                this.error('Failed to write temp file:', writeResult);
                return { error: 'Failed to write temp file' };
            }
            
            // 4. 移动临时文件到原文件
            const moveResult = await this.exec(`mv "${tempPath}" "${modulePropPath}"`);
            if (moveResult.code !== 0) {
                this.error('Failed to move temp file:', moveResult);
                return { error: 'Failed to move temp file' };
            }
            
            this.log('Module.prop updated successfully');
            return { success: true };
        } catch (e) {
            this.error('Update module.prop error:', e);
            return { error: e.message };
        }
    },
    
    // 获取当前 IP 地址
    async getCurrentIP() {
        try {
            // 接口定义
            const WIFI_IF = 'wlan0';
            
            // 检查 WiFi 接口是否处于 UP 状态
            const wifiUpResult = await this.exec(`ip link show ${WIFI_IF} 2>/dev/null | grep -q "UP,LOWER_UP" && echo "up"`);
            const wifiUp = wifiUpResult.code === 0 && wifiUpResult.data?.includes('up');
            
            if (wifiUp) {
                // 获取 WiFi IP
                const ipResult = await this.exec(`ip addr show ${WIFI_IF} 2>/dev/null | grep -E 'inet [0-9]+\.' | awk '{print $2}' | cut -d/ -f1 | head -n1`);
                if (ipResult.code === 0 && ipResult.data?.trim()) {
                    return ipResult.data.trim();
                }
            }
            
            // 移动数据或无法获取 IP
            return 'localhost';
        } catch (e) {
            this.error('Get current IP error:', e);
            return '无法获取IP';
        }
    },
    
    // 获取当前端口
    async getCurrentPort(pid) {
        try {
            // 使用 ss 或 netstat 获取端口
            const result = await this.exec(`ss -tulnp 2>/dev/null | grep ${pid} | awk '{print $5}' | cut -d':' -f2 | sort -u | head -n 1`);
            if (result.code === 0 && result.data?.trim()) {
                return result.data.trim();
            }
            
            // 尝试使用 netstat
            const netstatResult = await this.exec(`netstat -tulnp 2>/dev/null | grep ${pid} | awk '{print $4}' | cut -d':' -f2 | sort -u | head -n 1`);
            if (netstatResult.code === 0 && netstatResult.data?.trim()) {
                return netstatResult.data.trim();
            }
            
            return null;
        } catch (e) {
            this.error('Get current port error:', e);
            return null;
        }
    },
    
    // 刷新所有数据
    refreshAll() {
        if (this.state.isRefreshing) {
            this.log('Refresh already in progress, skipping');
            return;
        }
        
        this.state.isRefreshing = true;
        this.log('Starting refresh...');
        
        // 并行更新所有数据
        Promise.all([
            this.updateStatus(),
            this.updateNetwork(),
            this.updatePaths()
        ]).then(() => {
            return this.updateLogs();
        }).then(() => {
            this.log('Refresh complete');
        }).catch(e => {
            this.error('Refresh error:', e);
        }).finally(() => {
            this.state.isRefreshing = false;
        });
    },
    
    // 更新服务状态
    async updateStatus() {
        try {
            this.log('Updating service status...');
            
            const statusEl = document.getElementById('serviceStatus');
            const pidEl = document.getElementById('servicePid');
            
            if (!statusEl || !pidEl) {
                this.error('Status elements not found');
                return;
            }
            
            // 使用 checkServiceStatus 检查服务状态
            const status = await this.checkServiceStatus();
            
            if (status.running) {
                statusEl.textContent = '运行中';
                statusEl.style.color = '#4CAF50';
                pidEl.textContent = status.pid || '获取中...';
            } else {
                statusEl.textContent = '已停止';
                statusEl.style.color = '#F44336';
                pidEl.textContent = '-';
            }
            
            this.log('Service status updated:', status);
            
        } catch (e) {
            this.error('Update status error:', e);
        }
    },
    
    // 更新网络信息
    async updateNetwork() {
        try {
            this.log('Updating network info...');
            
            const modeEl = document.getElementById('networkMode');
            const ipv4El = document.getElementById('ipv4Address');
            const ipv6El = document.getElementById('ipv6Address');
            const sim1InfoEl = document.getElementById('sim1Info');
            const sim1IPv4El = document.getElementById('sim1IPv4');
            const sim1IPv6El = document.getElementById('sim1IPv6');
            const sim2InfoEl = document.getElementById('sim2Info');
            const sim2IPv4El = document.getElementById('sim2IPv4');
            const sim2IPv6El = document.getElementById('sim2IPv6');
            
            if (!modeEl || !ipv4El || !ipv6El) {
                this.error('Network elements not found');
                return;
            }
            
            // 接口定义
            const WIFI_IF = 'wlan0';
            const SIM1_IF = 'rmnet_data1';
            const SIM2_IF = 'rmnet_data2';
            
            // 检查接口是否处于UP状态
            const checkInterfaceUp = async (iface) => {
                const result = await this.exec(`ip link show ${iface} 2>/dev/null | grep -q "UP,LOWER_UP" && echo "up"`);
                return result.code === 0 && result.data?.includes('up');
            };
            
            // 获取IPv4
            const getIPv4 = async (iface) => {
                const isUp = await checkInterfaceUp(iface);
                if (!isUp) return null;
                const result = await this.exec(`ip addr show ${iface} 2>/dev/null | grep -E 'inet [0-9]+\\.' | awk '{print $2}' | cut -d/ -f1 | head -n1`);
                if (result.code === 0 && result.data?.trim()) {
                    return result.data.trim();
                }
                return null;
            };
            
            // 获取IPv6
            const getIPv6 = async (iface) => {
                const isUp = await checkInterfaceUp(iface);
                if (!isUp) return null;
                const result = await this.exec(`ip addr show ${iface} 2>/dev/null | grep -E 'inet6 [23][0-9a-fA-F]{0,3}:' | awk '{print $2}' | cut -d/ -f1 | head -n1`);
                if (result.code === 0 && result.data?.trim()) {
                    return result.data.trim();
                }
                return null;
            };
            
            // 检测网络类型和获取IP
            const wifiUp = await checkInterfaceUp(WIFI_IF);
            const sim1Up = await checkInterfaceUp(SIM1_IF);
            const sim2Up = await checkInterfaceUp(SIM2_IF);
            
            let networkType = '未知';
            let ipv4 = '-';
            let ipv6 = '-';
            
            // 隐藏所有双卡IP元素
            if (sim1InfoEl) sim1InfoEl.style.display = 'none';
            if (sim1IPv6El) sim1IPv6El.parentElement.style.display = 'none';
            if (sim2InfoEl) sim2InfoEl.style.display = 'none';
            if (sim2IPv6El) sim2IPv6El.parentElement.style.display = 'none';
            
            if (wifiUp) {
                // WiFi 优先
                networkType = 'WLAN';
                modeEl.style.color = '#4CAF50';
                ipv4 = await getIPv4(WIFI_IF) || '-';
                ipv6 = await getIPv6(WIFI_IF) || '-';
            } else if (sim1Up || sim2Up) {
                // 移动数据 - 显示双卡IP
                networkType = '移动数据';
                modeEl.style.color = '#2196F3';
                
                // 获取卡1和卡2的IP
                const sim1IPv4 = await getIPv4(SIM1_IF);
                const sim2IPv4 = await getIPv4(SIM2_IF);
                const sim1IPv6 = await getIPv6(SIM1_IF);
                const sim2IPv6 = await getIPv6(SIM2_IF);
                
                // 显示IPv4和IPv6（隐藏原来的元素）
                ipv4El.parentElement.style.display = 'none';
                ipv6El.parentElement.style.display = 'none';
                
                // 显示卡1信息
                if (sim1InfoEl && sim1IPv4El && sim1IPv4) {
                    sim1InfoEl.style.display = 'block';
                    sim1IPv4El.textContent = sim1IPv4;
                }
                if (sim1IPv6El && sim1IPv6) {
                    sim1IPv6El.parentElement.style.display = 'block';
                    const shortIPv6 = sim1IPv6.length > 30 ? sim1IPv6.substring(0, 30) + '...' : sim1IPv6;
                    sim1IPv6El.textContent = shortIPv6;
                }
                
                // 显示卡2信息
                if (sim2InfoEl && sim2IPv4El && sim2IPv4) {
                    sim2InfoEl.style.display = 'block';
                    sim2IPv4El.textContent = sim2IPv4;
                }
                if (sim2IPv6El && sim2IPv6) {
                    sim2IPv6El.parentElement.style.display = 'block';
                    const shortIPv6 = sim2IPv6.length > 30 ? sim2IPv6.substring(0, 30) + '...' : sim2IPv6;
                    sim2IPv6El.textContent = shortIPv6;
                }
                
                // 清空原来的IPv4和IPv6显示
                ipv4 = '-';
                ipv6 = '-';
            } else {
                networkType = '未连接';
                modeEl.style.color = '#9E9E9E';
                
                // 显示原来的IPv4和IPv6元素
                ipv4El.parentElement.style.display = 'block';
                ipv6El.parentElement.style.display = 'block';
            }
            
            modeEl.textContent = networkType;
            ipv4El.textContent = ipv4;
            ipv6El.textContent = ipv6;
            
        } catch (e) {
            this.error('Update network error:', e);
        }
    },
    
    // 更新路径信息
    async updatePaths() {
        try {
            this.log('Updating paths...');
            // 显示已初始化的路径
            const binaryEl = document.getElementById('binaryPath');
            const dataEl = document.getElementById('dataPath');
            
            if (!binaryEl || !dataEl) {
                this.error('Path elements not found');
                return;
            }
            
            binaryEl.textContent = this.state.binaryPath || '路径未设置';
            dataEl.textContent = this.state.dataDir || '/data/adb/openlist';
            
        } catch (e) {
            this.error('Update paths error:', e);
        }
    },
    
    // 更新日志（已弃用，使用实时监控）
    async updateLogs() {
        this.log('updateLogs called, but using real-time monitoring instead');
        // 实时日志监控已启动，此函数不再使用
    },
    
    // 更新时间（实时显示）
    updateTime() {
        try {
            const timeEl = document.getElementById('lastUpdate');
            if (timeEl) {
                const now = new Date();
                const hours = String(now.getHours()).padStart(2, '0');
                const minutes = String(now.getMinutes()).padStart(2, '0');
                const seconds = String(now.getSeconds()).padStart(2, '0');
                timeEl.textContent = `当前时间: ${hours}:${minutes}:${seconds}`;
            }
        } catch (e) {
            this.error('Update time error:', e);
        }
    },
    
    // 启动实时时间更新
    startRealTimeClock() {
        // 立即更新一次
        this.updateTime();
        // 每秒更新时间
        setInterval(() => this.updateTime(), 1000);
    },
    
    // 设置事件监听器
    setupEventListeners() {
    },
    
    // 显示提示
    showToast(message, type = 'info') {
        const toast = document.getElementById('toast');
        if (!toast) {
            this.error('Toast element not found');
            return;
        }
        
        toast.textContent = message;
        toast.className = `toast ${type} show`;
        
        setTimeout(() => {
            toast.className = 'toast';
        }, 3000);
    }
};

// 服务控制函数
function startService() {
    App.log('Starting service...');
    App.showToast('正在启动服务...', 'info');
    
    // 使用 setTimeout 避免阻塞UI
    setTimeout(async () => {
        try {
            const result = await App.startOpenListService();
            App.log('Start result:', result);
            
            if (result?.success) {
                if (result?.output === 'Service already running') {
                    App.showToast('有后台 不需要重复启动', 'info');
                } else {
                    App.showToast('服务启动成功', 'success');
                }
            } else {
                const error = result?.error || result?.output || '未知错误';
                App.showToast('服务启动失败: ' + error, 'error');
            }
            
            App.updateStatus();
            App.updateNetwork();
        } catch (e) {
            App.error('Start service error:', e);
            App.showToast('服务启动异常: ' + e.message, 'error');
        }
    }, 0);
}

function stopService() {
    App.log('Stopping service...');
    App.showToast('正在停止服务...', 'info');
    
    setTimeout(async () => {
        try {
            const result = await App.stopOpenListService();
            App.log('Stop result:', result);
            
            if (result?.success) {
                if (result?.output === 'Service not running') {
                    App.showToast('进程不存在无需关闭', 'info');
                } else {
                    App.showToast('服务已停止', 'success');
                }
            } else {
                const error = result?.error || result?.output || '未知错误';
                App.showToast('服务停止失败: ' + error, 'error');
            }
            
            App.updateStatus();
            App.updateNetwork();
        } catch (e) {
            App.error('Stop service error:', e);
            App.showToast('服务停止异常: ' + e.message, 'error');
        }
    }, 0);
}

function restartService() {
    App.log('Restarting service...');
    App.showToast('正在重启服务...', 'info');
    
    setTimeout(async () => {
        try {
            const result = await App.restartOpenListService();
            App.log('Restart result:', result);
            
            if (result?.success) {
                if (result?.output === 'Service already running') {
                    App.showToast('有后台 不需要重复启动', 'info');
                } else {
                    App.showToast('服务重启成功', 'success');
                }
            } else {
                const error = result?.error || result?.output || '未知错误';
                App.showToast('服务重启失败: ' + error, 'error');
            }
            
            App.updateStatus();
            App.updateNetwork();
        } catch (e) {
            App.error('Restart service error:', e);
            App.showToast('服务重启异常: ' + e.message, 'error');
        }
    }, 0);
}

// 密码管理函数
async function changePassword() {
    const input = document.getElementById('newPassword');
    const password = input?.value?.trim();
    
    if (!password) {
        App.showToast('请输入新密码', 'error');
        return;
    }
    
    App.log('Changing password...');
    App.showToast('正在修改密码...', 'info');
    
    // 使用 OpenList 命令修改密码
    const result = await App.callOpenList('admin', 'set', password);
    App.log('Password change result:', result);
    
    if (result?.success) {
        // 写入密码到初始密码.txt
        const dataDir = App.state.dataDir || '/data/adb/openlist';
        const writeResult = await App.exec(`echo "${password}" > "${dataDir}/初始密码.txt"`);
        if (writeResult.code === 0) {
            App.log('Password saved to initial password file');
        } else {
            App.error('Failed to save password to initial password file:', writeResult);
        }
        
        // 更新 module.prop 文件以显示最新密码
        const statusResult = await App.checkServiceStatus();
        if (statusResult.running) {
            await App.updateModuleProp('running', statusResult.pid);
        } else {
            await App.updateModuleProp('stopped');
        }
        
        App.showToast('密码修改成功', 'success');
        input.value = '';
    } else {
        const error = result?.error || result?.output || '未知错误';
        App.showToast('密码修改失败: ' + error, 'error');
    }
}

async function resetPassword() {
    App.log('Resetting password...');
    App.showToast('正在重置密码...', 'info');
    
    // 使用 OpenList 命令重置密码为 admin
    const result = await App.callOpenList('admin', 'set', 'admin');
    App.log('Password reset result:', result);
    
    if (result?.success) {
        // 写入密码到初始密码.txt
        const dataDir = App.state.dataDir || '/data/adb/openlist';
        const writeResult = await App.exec(`echo "admin" > "${dataDir}/初始密码.txt"`);
        if (writeResult.code === 0) {
            App.log('Password saved to initial password file');
        } else {
            App.error('Failed to save password to initial password file:', writeResult);
        }
        
        // 更新 module.prop 文件以显示最新密码
        const statusResult = await App.checkServiceStatus();
        if (statusResult.running) {
            await App.updateModuleProp('running', statusResult.pid);
        } else {
            await App.updateModuleProp('stopped');
        }
        
        App.showToast('密码已重置为: admin', 'success');
        const input = document.getElementById('newPassword');
        if (input) input.value = '';
    } else {
        const error = result?.error || result?.output || '未知错误';
        App.showToast('密码重置失败: ' + error, 'error');
    }
}

// 刷新日志
function refreshLogs() {
    App.log('Refreshing logs...');
    App.updateLogs();
    App.showToast('日志已刷新', 'success');
}

// 复制到剪贴板
function copyToClipboard(element) {
    const text = element?.textContent;
    if (!text || text === '-') return;
    
    try {
        if (navigator.clipboard) {
            navigator.clipboard.writeText(text).then(() => {
                App.showToast('已复制: ' + text, 'success');
            });
        } else {
            const textarea = document.createElement('textarea');
            textarea.value = text;
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            document.body.removeChild(textarea);
            App.showToast('已复制: ' + text, 'success');
        }
    } catch (e) {
        App.error('Copy error:', e);
        App.showToast('复制失败', 'error');
    }
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', () => {
    console.log('OpenList Panel v3.0 - DOM loaded');
    App.init();
});
