# 零写入汉化启动：配置目录在仓库 runtime\，不修改安装目录任何文件。
# 首次使用（或仓库移动 / 换机 / IDE 目录变化）时自动重新生成运行环境。
param(
    [string]$Root = '',
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '探测安装目录.ps1')
$dir = Resolve-IdEDir -Hint $Root
if (-not $dir) {
    Write-Host '[×] 未能定位 STM32CubeIDE 安装目录，启动中止。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}

$proj = Split-Path -Parent $PSScriptRoot
$rt   = Join-Path $proj 'runtime'
$cfg  = Join-Path $rt 'configuration'
$bi   = Join-Path $cfg 'org.eclipse.equinox.simpleconfigurator\bundles.info'
$marker = Join-Path $rt '生成信息.txt'

# 运行环境缺失、或来源目录与当前探测结果不一致（仓库移动 / 换机 / IDE 变化）→ 重新生成
$needGen = $true
if ((Test-Path $bi) -and (Test-Path $marker)) {
    $mark = [System.IO.File]::ReadAllText($marker)
    if ($mark -match [regex]::Escape("source=$dir")) { $needGen = $false }
}
if ($needGen) {
    Write-Host '[i] 零写入运行环境尚未生成（或安装目录已变化），正在自动生成（约几秒）……' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot '生成零写入运行环境.ps1') -Root $dir -NoPause
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[×] 运行环境生成失败，启动中止。' -ForegroundColor Red
        if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
        exit 1
    }
}

$ws  = Join-Path $env:USERPROFILE 'STM32CubeIDE\workspace_1.19.0'
$exe = Join-Path $dir 'stm32cubeide.exe'
Write-Host "STM32CubeIDE 目录：$dir"
Write-Host "配置目录：$cfg"
Write-Host '正在以零写入汉化模式启动（-configuration runtime -nl zh_CN）……'
Start-Process -FilePath $exe -ArgumentList @('-configuration', "`"$cfg`"", '-nl', 'zh_CN', '-data', "`"$ws`"")
Write-Host '已启动。'
