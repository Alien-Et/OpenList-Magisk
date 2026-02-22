<#
.SYNOPSIS
OpenList Magisk 模块本地打包脚本

.DESCRIPTION
基于 GitHub Actions 工作流逻辑，在 Windows 环境中打包 OpenList Magisk 模块

.EXAMPLE
./build.ps1

.NOTES
需要安装以下工具：
1. Python 3 (用于处理 JSON 数据)
2. PowerShell 5.1 或更高版本
3. tar (Windows 10/11 已内置) 或 7-Zip (用于解压 tar.gz 文件)

可选工具（用于加速下载）：
- aria2: 多线程下载工具，可大幅提升下载速度
  安装: scoop install aria2 或 choco install aria2

下载优先级：
1. aria2c (最快，支持多线程下载)
2. BITS (Windows后台智能传输服务，较快)
3. .NET WebClient (标准下载，带进度显示)
#>

Write-Host "========================================" -ForegroundColor Green
Write-Host "OpenList Magisk 模块本地打包脚本" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# 检查依赖工具
Write-Host "检查依赖工具..." -ForegroundColor Cyan

$requiredTools = @("python")
foreach ($tool in $requiredTools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "错误: 缺少依赖工具 $tool" -ForegroundColor Red
        Write-Host "请确保 $tool 已安装并添加到环境变量" -ForegroundColor Yellow
        exit 1
    }
}

# 检查 7z 或 tar 是否可用
$has7z = Get-Command "7z" -ErrorAction SilentlyContinue
$hasTar = Get-Command "tar" -ErrorAction SilentlyContinue

if (!$has7z -and !$hasTar) {
    Write-Host "错误: 缺少解压工具" -ForegroundColor Red
    Write-Host "请安装 7-Zip 或确保 tar 命令可用" -ForegroundColor Yellow
    exit 1
}

# 检查下载工具
$hasAria2 = Get-Command "aria2c" -ErrorAction SilentlyContinue
$hasBits = Get-Command "Start-BitsTransfer" -ErrorAction SilentlyContinue

Write-Host "依赖工具检查通过" -ForegroundColor Green

# 下载函数（支持多种下载方式）
function Download-File {
    param(
        [string]$Url,
        [string]$Output
    )
    
    $fileName = Split-Path -Leaf $Output
    
    # 优先使用 aria2c（速度最快）
    if ($hasAria2) {
        Write-Host "使用 aria2c 下载 $fileName..." -ForegroundColor Cyan
        aria2c -x 16 -s 16 -k 1M -o $Output $Url 2>&1 | Out-Null
        return $?
    }
    
    # 使用 BITS（Windows后台智能传输服务，速度较快）
    if ($hasBits) {
        Write-Host "使用 BITS 下载 $fileName..." -ForegroundColor Cyan
        try {
            Start-BitsTransfer -Source $Url -Destination $Output -ErrorAction Stop
            return $true
        } catch {
            Write-Host "BITS下载失败，尝试其他方式..." -ForegroundColor Yellow
        }
    }
    
    # 使用 Invoke-WebRequest（带进度显示）
    Write-Host "使用 Invoke-WebRequest 下载 $fileName..." -ForegroundColor Cyan
    try {
        # 使用 .NET WebClient 以获得更好的性能和进度显示
        $webClient = New-Object System.Net.WebClient
        
        # 注册进度事件
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -SourceIdentifier WebClient.DownloadProgressChanged -Action {
            $Global:DownloadProgress = $EventArgs.ProgressPercentage
            Write-Progress -Activity "下载文件" -Status "进度: $($EventArgs.ProgressPercentage)%" -PercentComplete $EventArgs.ProgressPercentage
        } | Out-Null
        
        # 开始下载
        $webClient.DownloadFileAsync($Url, $Output)
        
        # 等待下载完成
        while ($webClient.IsBusy) {
            Start-Sleep -Milliseconds 100
        }
        
        # 清理事件
        Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged -ErrorAction SilentlyContinue
        $webClient.Dispose()
        
        Write-Progress -Activity "下载文件" -Completed
        return (Test-Path $Output)
    } catch {
        Write-Host "下载失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 进入脚本所在目录
Set-Location -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition)

# 获取 OpenList 最新版本
Write-Host "获取 OpenList 最新版本..." -ForegroundColor Cyan

$apiUrl = "https://api.github.com/repos/OpenListTeam/OpenList/releases/latest"
$latestReleaseFile = "latest_release.json"

for ($i = 1; $i -le 3; $i++) {
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
        $response | ConvertTo-Json -Depth 100 | Out-File -FilePath $latestReleaseFile -Encoding UTF8
        Write-Host "成功获取 OpenList Release 数据" -ForegroundColor Green
        break
    } catch {
        Write-Host "尝试 $i 失败: $($_.Exception.Message)" -ForegroundColor Yellow
        Start-Sleep -Seconds (5 * $i)
    }
}

if (!(Test-Path $latestReleaseFile) -or !(Get-Content $latestReleaseFile)) {
    Write-Host "错误: 无法获取 OpenList 版本信息" -ForegroundColor Red
    exit 1
}

# 提取版本号
$releaseData = Get-Content $latestReleaseFile | ConvertFrom-Json
$version = $releaseData.tag_name
if (!$version) {
    Write-Host "错误: 无法提取版本号" -ForegroundColor Red
    Get-Content $latestReleaseFile
    exit 1
}

Write-Host "获取到版本: $version" -ForegroundColor Green

# 生成版本代码（比如 v4.1.10 -> 4110）
$versionNum = $version -replace 'v', ''
$versionParts = $versionNum -split '\.'
$versionCode = [int]$versionParts[0] * 1000 + [int]$versionParts[1] * 100 + [int]$versionParts[2]

Write-Host "版本代码: $versionCode" -ForegroundColor Green

# 提取下载链接
$armUrl = $releaseData.assets | Where-Object { $_.browser_download_url -like '*openlist-android-arm.tar.gz' } | Select-Object -ExpandProperty browser_download_url
$arm64Url = $releaseData.assets | Where-Object { $_.browser_download_url -like '*openlist-android-arm64.tar.gz' } | Select-Object -ExpandProperty browser_download_url

# 提取 CHANGELOG
$changelog = $releaseData.body

if (!$armUrl -or !$arm64Url) {
    Write-Host "错误: 无法提取二进制下载链接" -ForegroundColor Red
    exit 1
}

Write-Host "ARM 下载链接: $armUrl" -ForegroundColor Cyan
Write-Host "ARM64 下载链接: $arm64Url" -ForegroundColor Cyan

# 同步 OpenList 二进制文件
Write-Host "下载并同步 OpenList 二进制文件..." -ForegroundColor Cyan

# 下载并解压 ARM 版本
for ($i = 1; $i -le 3; $i++) {
    try {
        Write-Host "下载 ARM 版本 ($i/3)..." -ForegroundColor Cyan
        # 使用优化的下载函数
        if (Download-File -Url $armUrl -Output "openlist-arm.tar.gz") {
            break
        }
    } catch {
        Write-Host "下载 ARM 版本失败，重试 $i/3: $($_.Exception.Message)" -ForegroundColor Yellow
        Start-Sleep -Seconds (5 * $i)
    }
}

if (!(Test-Path "openlist-arm.tar.gz")) {
    Write-Host "错误: 下载 ARM 版本失败" -ForegroundColor Red
    exit 1
}

Write-Host "解压 ARM 版本..." -ForegroundColor Cyan

if ($has7z) {
    7z x "openlist-arm.tar.gz" -y
    7z x "openlist-arm.tar" -y
    Remove-Item "openlist-arm.tar.gz", "openlist-arm.tar" -Force
} elseif ($hasTar) {
    tar -xzf "openlist-arm.tar.gz"
    Remove-Item "openlist-arm.tar.gz" -Force
}

if (!(Test-Path "openlist")) {
    Write-Host "错误: 解压 ARM 版本失败" -ForegroundColor Red
    exit 1
}

Rename-Item "openlist" "openlist-arm"

# 下载并解压 ARM64 版本
for ($i = 1; $i -le 3; $i++) {
    try {
        Write-Host "下载 ARM64 版本 ($i/3)..." -ForegroundColor Cyan
        # 使用优化的下载函数
        if (Download-File -Url $arm64Url -Output "openlist-arm64.tar.gz") {
            break
        }
    } catch {
        Write-Host "下载 ARM64 版本失败，重试 $i/3: $($_.Exception.Message)" -ForegroundColor Yellow
        Start-Sleep -Seconds (5 * $i)
    }
}

if (!(Test-Path "openlist-arm64.tar.gz")) {
    Write-Host "错误: 下载 ARM64 版本失败" -ForegroundColor Red
    exit 1
}

Write-Host "解压 ARM64 版本..." -ForegroundColor Cyan

if ($has7z) {
    7z x "openlist-arm64.tar.gz" -y
    7z x "openlist-arm64.tar" -y
    Remove-Item "openlist-arm64.tar.gz", "openlist-arm64.tar" -Force
} elseif ($hasTar) {
    tar -xzf "openlist-arm64.tar.gz"
    Remove-Item "openlist-arm64.tar.gz" -Force
}

if (!(Test-Path "openlist")) {
    Write-Host "错误: 解压 ARM64 版本失败" -ForegroundColor Red
    exit 1
}

Rename-Item "openlist" "openlist-arm64"

# 移动二进制文件到模块目录
if (!(Test-Path "openlist-arm") -or !(Test-Path "openlist-arm64")) {
    Write-Host "错误: 二进制文件不存在" -ForegroundColor Red
    exit 1
}

Move-Item "openlist-arm" "OpenList-Magisk/" -Force
Move-Item "openlist-arm64" "OpenList-Magisk/" -Force

# 设置权限 (Windows 环境下跳过)
Write-Host "二进制文件同步完成" -ForegroundColor Green

# 更新配置文件
Write-Host "更新配置文件..." -ForegroundColor Cyan

# 更新 update.json
$updateJsonContent = @"
{
    "version": "$version",
    "versionCode": $versionCode,
    "zipUrl": "https://github.com/OpenListTeam/OpenList-Magisk/releases/download/$version/openlist-magisk-$version.zip",
    "changelog": "https://github.com/OpenListTeam/OpenList-Magisk/raw/main/OpenList-Magisk/CHANGELOG.md"
}
"@

$updateJsonContent | Out-File -FilePath "update.json" -Encoding UTF8

# 更新 module.prop
if (Test-Path "OpenList-Magisk/module.prop") {
    $modulePropContent = Get-Content "OpenList-Magisk/module.prop"
    $modulePropContent = $modulePropContent -replace '^version=.*', "version=$version"
    $modulePropContent = $modulePropContent -replace '^versionCode=.*', "versionCode=$versionCode"
    $modulePropContent | Out-File -FilePath "OpenList-Magisk/module.prop" -Encoding UTF8
} else {
    Write-Host "错误: module.prop 文件不存在" -ForegroundColor Red
    exit 1
}

# 更新 CHANGELOG.md
if (!(Test-Path "OpenList-Magisk")) {
    New-Item -ItemType Directory -Path "OpenList-Magisk" -Force
}

$changelog | Out-File -FilePath "OpenList-Magisk/CHANGELOG.md" -Encoding UTF8

Write-Host "配置文件更新完成" -ForegroundColor Green

# 打包模块
Write-Host "打包模块..." -ForegroundColor Cyan

# 使用 PowerShell 压缩文件，输出到项目根目录
$zipFileName = "openlist-magisk-$version.zip"

# 创建临时目录用于构建
$tempDir = Join-Path -Path $env:TEMP -ChildPath "openlist-build-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# 复制所有文件到临时目录
# 进入OpenList-Magisk目录，只复制其中的文件
$openListDir = "OpenList-Magisk"
$sourceDir = Get-Item -Path $openListDir

# 复制所有文件和子目录
Get-ChildItem -Path $sourceDir -Recurse | ForEach-Object {
    # 计算相对路径
    $relativePath = $_.FullName.Substring($sourceDir.FullName.Length + 1)
    $destPath = Join-Path -Path $tempDir -ChildPath $relativePath
    
    if ($_.PSIsContainer) {
        # 创建目录
        New-Item -ItemType Directory -Path $destPath -Force | Out-Null
    } else {
        # 复制文件
        Copy-Item -Path $_.FullName -Destination $destPath -Force
    }
}

# 压缩文件 - 使用临时文件名避免锁定问题
$tempZipFileName = "$zipFileName.tmp"

if (Test-Path "$tempZipFileName") {
    Remove-Item "$tempZipFileName" -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
# 使用 includeBaseDirectory=false 确保zip文件中直接包含内容，而不是包含在子目录中
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $tempZipFileName, [System.IO.Compression.CompressionLevel]::Optimal, $false)

# 如果成功创建临时文件，替换原文件
if (Test-Path "$tempZipFileName") {
    if (Test-Path "$zipFileName") {
        Remove-Item "$zipFileName" -Force -ErrorAction SilentlyContinue
    }
    Move-Item "$tempZipFileName" "$zipFileName" -Force
}

# 清理临时目录
Remove-Item $tempDir -Recurse -Force

if (!(Test-Path "$zipFileName")) {
    Write-Host "错误: 打包失败" -ForegroundColor Red
    exit 1
}

# 清理临时文件
Remove-Item $latestReleaseFile -Force -ErrorAction SilentlyContinue

# 获取文件大小
$fileSize = (Get-Item "$zipFileName").Length
$fileSizeHuman = if ($fileSize -ge 1MB) {
    "{0:N2} MB" -f ($fileSize / 1MB)
} else {
    "{0:N2} KB" -f ($fileSize / 1KB)
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "打包完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "模块版本: $version" -ForegroundColor Yellow
Write-Host "版本代码: $versionCode" -ForegroundColor Yellow
Write-Host "打包文件: $zipFileName" -ForegroundColor Yellow
Write-Host "文件大小: $fileSizeHuman" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green
