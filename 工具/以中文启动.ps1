# 以中文启动 STM32CubeIDE（仅切换语言，不改任何文件；启用 ST 插件自带的中文文案）。
# 安装目录自动探测，失败可交互粘贴。
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

$exe = Join-Path $dir 'stm32cubeide.exe'
Write-Host "STM32CubeIDE 目录：$dir"
Write-Host '正在以中文模式启动（-nl zh_CN）……'
Start-Process -FilePath $exe -ArgumentList @('-nl', 'zh_CN')
Write-Host '已启动。'
