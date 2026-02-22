const App = {
    bridge: null,
    dataPath: null,
    binaryPath: null,
    logPath: null,
    refreshInterval: null,

    async init() {
        this.detectBridge();
        this.readPathsFromMeta();
        await this.loadConfig();
        await this.refreshAll();
        this.startAutoRefresh();
    },

    readPathsFromMeta() {
        const binaryPathMeta = document.querySelector('meta[name="binary-path"]');
        const dataDirMeta = document.querySelector('meta[name="data-dir"]');
        
        if (binaryPathMeta && binaryPathMeta.content && binaryPathMeta.content !== '__PLACEHOLDER_BINARY_PATH__') {
            this.binaryPath = binaryPathMeta.content;
        }
        
        if (dataDirMeta && dataDirMeta.content && dataDirMeta.content !== '__PLACEHOLDER_DATA_DIR__') {
            this.dataPath = dataDirMeta.content;
        }
    },

    detectBridge() {
        if (typeof window.mmk !== 'undefined') {
            this.bridge = 'magisk';
            console.log('Detected: Magisk');
        } else if (typeof window.ksu !== 'undefined') {
            this.bridge = 'kernelsu';
            console.log('Detected: KernelSU');
        } else if (typeof window.apatch !== 'undefined') {
            this.bridge = 'apatch';
            console.log('Detected: APatch');
        } else {
            this.bridge = 'unknown';
            console.log('Bridge not detected, using fallback');
        }
    },

    exec(command) {
        return new Promise((resolve, reject) => {
            try {
                let result;
                switch (this.bridge) {
                    case 'magisk':
                        result = window.mmk.exec(command);
                        break;
                    case 'kernelsu':
                        result = window.ksu.exec(command);
                        break;
                    case 'apatch':
                        result = window.apatch.exec(command);
                        break;
                    default:
                        result = { code: 1, data: 'Bridge not available' };
                }
                resolve(result);
            } catch (e) {
                reject(e);
            }
        });
    },

    async loadConfig() {
        try {
            // 尝试从模块目录获取配置
            const moduleDir = '/data/adb/modules/openlist';
            let foundModule = false;
            
            const result = await this.exec(`cat ${moduleDir}/module.prop 2>/dev/null`);
            if (result.code === 0 && result.data) {
                const props = this.parseProps(result.data);
                if (!this.dataPath) {
                    this.dataPath = props.DATA_DIR || '/data/adb/openlist';
                }
                foundModule = true;
            }
            
            // 获取二进制路径
            if (!this.binaryPath) {
                const binaryResult = await this.exec(`cat ${moduleDir}/service.sh 2>/dev/null | grep "^OPENLIST_BINARY=" | head -1`);
                if (binaryResult.code === 0 && binaryResult.data) {
                    this.binaryPath = binaryResult.data.replace('OPENLIST_BINARY=', '').replace(/"/g, '');
                    // 替换 $MODDIR 为实际路径
                    if (this.binaryPath.includes('$MODDIR')) {
                        if (await this.fileExists(moduleDir)) {
                            this.binaryPath = this.binaryPath.replace('$MODDIR', moduleDir);
                        }
                    }
                }
            }
            
            // 检测所有可能的数据目录 (2个选项)
            if (!this.dataPath) {
                const possibleDataDirs = ['/data/adb/openlist', '/sdcard/Android/openlist'];
                for (const dir of possibleDataDirs) {
                    if (await this.directoryExists(dir)) {
                        this.dataPath = dir;
                        break;
                    }
                }
            }
            
            // 检测所有可能的二进制路径 (3个安装位置)
            if (!this.binaryPath) {
                const possibleBinaryPaths = [
                    '/data/adb/openlist/bin/openlist',
                    '/data/adb/modules/openlist/bin/openlist',
                    '/data/adb/modules/openlist/system/bin/openlist'
                ];
                for (const path of possibleBinaryPaths) {
                    if (await this.fileExists(path)) {
                        this.binaryPath = path;
                        break;
                    }
                }
            }
            
            // 设置默认路径
            if (!this.dataPath) {
                this.dataPath = '/data/adb/openlist';
            }
            
            if (!this.binaryPath) {
                this.binaryPath = `${this.dataPath}/bin/openlist`;
            }
            
            // 设置日志路径
            this.logPath = '/data/adb/modules/openlist/service.log';
        } catch (e) {
            console.error('Failed to load config:', e);
            // 设置默认值
            if (!this.dataPath) this.dataPath = '/data/adb/openlist';
            if (!this.binaryPath) this.binaryPath = `${this.dataPath}/bin/openlist`;
            if (!this.logPath) this.logPath = '/data/adb/modules/openlist/service.log';
        }
    },

    async fileExists(path) {
        try {
            const result = await this.exec(`ls -l "${path}" 2>/dev/null`);
            return result.code === 0;
        } catch {
            return false;
        }
    },

    async directoryExists(path) {
        try {
            const result = await this.exec(`ls -ld "${path}" 2>/dev/null`);
            return result.code === 0;
        } catch {
            return false;
        }
    },

    parseProps(data) {
        const props = {};
        data.split('\n').forEach(line => {
            const match = line.match(/^([^=]+)=(.*)$/);
            if (match) {
                props[match[1].trim()] = match[2].trim();
            }
        });
        return props;
    },

    async refreshAll() {
        await this.updateServiceStatus();
        await this.updateNetworkInfo();
        await this.updatePathInfo();
        await this.refreshLogs();
        this.updateLastUpdate();
    },

    async updateServiceStatus() {
        const statusBadge = document.getElementById('statusBadge');
        const serviceStatus = document.getElementById('servicePid');
        
        // 检查是否在电脑测试环境中
        if (this.bridge === 'unknown') {
            statusBadge.className = 'status-badge stopped';
            statusBadge.querySelector('.status-text').textContent = '未运行';
            document.getElementById('serviceStatus').textContent = '未运行 (测试环境)';
            document.getElementById('serviceStatus').style.color = '#FF9800';
            serviceStatus.textContent = '-';
            return;
        }
        
        statusBadge.className = 'status-badge checking';
        statusBadge.querySelector('.status-text').textContent = '检测中...';

        try {
            const result = await this.exec('pgrep -f "openlist.*server" 2>/dev/null');
            const pid = result.data ? result.data.trim() : '';
            
            if (pid && pid !== '') {
                statusBadge.className = 'status-badge running';
                statusBadge.querySelector('.status-text').textContent = '运行中';
                document.getElementById('serviceStatus').textContent = '运行中';
                document.getElementById('serviceStatus').style.color = '#4CAF50';
                serviceStatus.textContent = pid.split('\n')[0];
            } else {
                statusBadge.className = 'status-badge stopped';
                statusBadge.querySelector('.status-text').textContent = '已停止';
                document.getElementById('serviceStatus').textContent = '已停止';
                document.getElementById('serviceStatus').style.color = '#F44336';
                serviceStatus.textContent = '-';
            }
        } catch (e) {
            statusBadge.className = 'status-badge stopped';
            statusBadge.querySelector('.status-text').textContent = '检测失败';
            document.getElementById('serviceStatus').textContent = '检测失败';
            serviceStatus.textContent = '-';
        }
    },

    async updateNetworkInfo() {
        // 检查是否在电脑测试环境中
        if (this.bridge === 'unknown') {
            document.getElementById('networkMode').textContent = '测试环境';
            document.getElementById('networkMode').style.color = '#FF9800';
            document.getElementById('ipv4Address').textContent = '测试环境 - 未检测';
            document.getElementById('ipv6Address').textContent = '测试环境 - 未检测';
            return;
        }
        
        try {
            // 检测WLAN接口
            const wlanResult = await this.exec('ip link | grep -E "wlan.*state UP" | head -1');
            const isWifi = wlanResult.data && wlanResult.data.trim() !== '';
            
            let interfaceName = 'wlan0';
            
            if (isWifi) {
                document.getElementById('networkMode').textContent = 'WLAN';
                document.getElementById('networkMode').style.color = '#2196F3';
                interfaceName = (wlanResult.data.match(/(\d+):\s*(\w+):/) || [])[2] || 'wlan0';
            } else {
                // 检测移动数据接口
                document.getElementById('networkMode').textContent = '移动数据';
                document.getElementById('networkMode').style.color = '#FF9800';
                
                // 尝试不同的移动数据接口
                const mobileInterfaces = ['rmnet0', 'rmnet_data0', 'rmnet_data1', 'wwan0'];
                for (const iface of mobileInterfaces) {
                    const ifaceResult = await this.exec(`ip link | grep "${iface}.*state UP"`);
                    if (ifaceResult.data && ifaceResult.data.trim() !== '') {
                        interfaceName = iface;
                        break;
                    }
                }
            }

            // 获取IPv4地址
            let ipv4 = '-';
            const ipv4Result = await this.exec(`ip -4 addr show ${interfaceName} 2>/dev/null | grep inet | awk '{print $2}' | cut -d'/' -f1`);
            if (ipv4Result.data) {
                ipv4 = ipv4Result.data.trim() || '-';
            }
            document.getElementById('ipv4Address').textContent = ipv4;

            // 获取IPv6地址
            let ipv6 = '-';
            const ipv6Result = await this.exec(`ip -6 addr show ${interfaceName} 2>/dev/null | grep inet6 | grep -v fe80 | awk '{print $2}' | cut -d'/' -f1 | head -1`);
            if (ipv6Result.data) {
                ipv6 = ipv6Result.data.trim() || '-';
            }
            document.getElementById('ipv6Address').textContent = ipv6;
        } catch (e) {
            console.error('Failed to update network info:', e);
            document.getElementById('networkMode').textContent = '未知';
            document.getElementById('ipv4Address').textContent = '-';
            document.getElementById('ipv6Address').textContent = '-';
        }
    },

    async updatePathInfo() {
        // 检查是否在电脑测试环境中
        if (this.bridge === 'unknown') {
            document.getElementById('binaryPath').textContent = '测试环境 - 未配置';
            document.getElementById('dataPath').textContent = '测试环境 - 未配置';
            return;
        }
        
        document.getElementById('binaryPath').textContent = this.binaryPath || '-';
        document.getElementById('dataPath').textContent = this.dataPath || '-';
    },

    async refreshLogs() {
        const logContent = document.getElementById('logContent');
        
        // 检查是否在电脑测试环境中
        if (this.bridge === 'unknown') {
            logContent.textContent = '测试环境 - 无法读取日志';
            return;
        }
        
        try {
            const result = await this.exec(`tail -100 ${this.logPath} 2>/dev/null || echo "日志文件不存在"`);
            logContent.textContent = result.data || '无日志内容';
            logContent.scrollTop = logContent.scrollHeight;
        } catch (e) {
            logContent.textContent = '无法读取日志';
        }
    },

    updateLastUpdate() {
        const now = new Date();
        document.getElementById('lastUpdate').textContent = 
            `最后更新: ${now.toLocaleString('zh-CN')}`;
    },

    startAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
        this.refreshInterval = setInterval(() => {
            this.refreshAll();
        }, 30000);
    },

    showToast(message, type = 'info') {
        const toast = document.getElementById('toast');
        toast.textContent = message;
        toast.className = `toast ${type} show`;
        setTimeout(() => {
            toast.className = 'toast';
        }, 3000);
    }
};

async function startService() {
    // 检查是否在电脑测试环境中
    if (App.bridge === 'unknown') {
        App.showToast('测试环境 - 无法启动服务', 'error');
        return;
    }
    
    App.showToast('正在启动服务...', 'info');
    try {
        // 尝试从模块目录启动服务
        const moduleDir = '/data/adb/modules/openlist';
        let startSuccess = false;
        
        const result = await App.exec(`sh ${moduleDir}/service.sh 2>&1 &`);
        if (result.code === 0) {
            startSuccess = true;
        }
        
        if (!startSuccess) {
            // 尝试直接使用二进制启动
            const binaryPath = App.binaryPath || '/data/adb/openlist/bin/openlist';
            const dataPath = App.dataPath || '/data/adb/openlist';
            await App.exec(`${binaryPath} server start --data "${dataPath}" 2>&1 &`);
        }
        
        setTimeout(() => {
            App.refreshAll();
            App.showToast('服务启动成功', 'success');
        }, 2000);
    } catch (e) {
        App.showToast('启动失败: ' + e.message, 'error');
    }
}

async function stopService() {
    // 检查是否在电脑测试环境中
    if (App.bridge === 'unknown') {
        App.showToast('测试环境 - 无法停止服务', 'error');
        return;
    }
    
    App.showToast('正在停止服务...', 'info');
    try {
        // 尝试使用openlist命令停止
        const binaryPath = App.binaryPath || '/data/adb/openlist/bin/openlist';
        const result = await App.exec(`${binaryPath} server stop 2>&1`);
        
        // 如果openlist命令失败，使用pkill
        if (result.code !== 0) {
            await App.exec('pkill -f "openlist.*server"');
        }
        
        setTimeout(() => {
            App.refreshAll();
            App.showToast('服务已停止', 'success');
        }, 1000);
    } catch (e) {
        App.showToast('停止失败: ' + e.message, 'error');
    }
}

async function restartService() {
    // 检查是否在电脑测试环境中
    if (App.bridge === 'unknown') {
        App.showToast('测试环境 - 无法重启服务', 'error');
        return;
    }
    
    App.showToast('正在重启服务...', 'info');
    try {
        // 停止服务
        const binaryPath = App.binaryPath || '/data/adb/openlist/bin/openlist';
        await App.exec(`${binaryPath} server stop 2>&1 || pkill -f "openlist.*server"`);
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        // 启动服务
        const moduleDir = '/data/adb/modules/openlist';
        let startSuccess = false;
        
        const result = await App.exec(`sh ${moduleDir}/service.sh 2>&1 &`);
        if (result.code === 0) {
            startSuccess = true;
        }
        
        if (!startSuccess) {
            const dataPath = App.dataPath || '/data/adb/openlist';
            await App.exec(`${binaryPath} server start --data "${dataPath}" 2>&1 &`);
        }
        
        setTimeout(() => {
            App.refreshAll();
            App.showToast('服务重启成功', 'success');
        }, 2000);
    } catch (e) {
        App.showToast('重启失败: ' + e.message, 'error');
    }
}

async function changePassword() {
    // 检查是否在电脑测试环境中
    if (App.bridge === 'unknown') {
        App.showToast('测试环境 - 无法修改密码', 'error');
        return;
    }
    
    const newPassword = document.getElementById('newPassword').value;
    if (!newPassword) {
        App.showToast('请输入新密码', 'error');
        return;
    }
    
    App.showToast('正在修改密码...', 'info');
    try {
        const binaryPath = App.binaryPath || '/data/adb/openlist/bin/openlist';
        const dataPath = App.dataPath || '/data/adb/openlist';
        const result = await App.exec(`${binaryPath} admin set admin --password "${newPassword}" --data "${dataPath}" 2>&1`);
        
        if (result.code === 0) {
            App.showToast('密码修改成功', 'success');
            document.getElementById('newPassword').value = '';
        } else {
            App.showToast('密码修改失败', 'error');
        }
    } catch (e) {
        App.showToast('修改失败: ' + e.message, 'error');
    }
}

async function resetPassword() {
    // 检查是否在电脑测试环境中
    if (App.bridge === 'unknown') {
        App.showToast('测试环境 - 无法重置密码', 'error');
        return;
    }
    
    App.showToast('正在重置密码...', 'info');
    try {
        const binaryPath = App.binaryPath || '/data/adb/openlist/bin/openlist';
        const dataPath = App.dataPath || '/data/adb/openlist';
        const result = await App.exec(`${binaryPath} admin set admin --password "admin" --data "${dataPath}" 2>&1`);
        
        if (result.code === 0) {
            App.showToast('密码已重置为: admin', 'success');
        } else {
            App.showToast('密码重置失败', 'error');
        }
    } catch (e) {
        App.showToast('重置失败: ' + e.message, 'error');
    }
}

function copyToClipboard(element) {
    const text = element.textContent;
    if (text === '-' || text === '检测中...') {
        return;
    }
    
    if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => {
            App.showToast('已复制: ' + text, 'success');
        }).catch(() => {
            fallbackCopy(text);
        });
    } else {
        fallbackCopy(text);
    }
}

function fallbackCopy(text) {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
        document.execCommand('copy');
        App.showToast('已复制: ' + text, 'success');
    } catch (e) {
        App.showToast('复制失败', 'error');
    }
    document.body.removeChild(textarea);
}

function refreshLogs() {
    App.refreshLogs();
    App.showToast('日志已刷新', 'info');
}

document.addEventListener('DOMContentLoaded', async () => {
    await App.init();
});
