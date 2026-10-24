#Requires -Version 5.1
# 还原 STM32CubeIDE 英文界面：移除 dropins 中的汉化包，并从 .zhbak 恢复启动配置与包清单。
# 易用性：自动请求管理员权限；自动探测安装目录，失败可交互粘贴。
[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'

# ---------- 1. 自动请求管理员权限 ----------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host '[i] 还原安装目录需要管理员权限，正在弹出授权窗口……' -ForegroundColor Yellow
    $psExe   = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Root)    { $argList += @('-Root', "`"$Root`"") }
    if ($NoPause) { $argList += '-NoPause' }
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    }
    catch {
        Write-Host '[×] 未获得管理员权限（授权被取消）。' -ForegroundColor Red
        Write-Host '    可右键「一键还原英文.bat」→「以管理员身份运行」重试。' -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
        exit 1
    }
}

# ---------- 2. 探测 STM32CubeIDE 安装目录（共享模块） ----------
. (Join-Path $PSScriptRoot '探测安装目录.ps1')

$dir = Resolve-IdEDir -Hint $Root
if (-not $dir) {
    Write-Host '[×] 未能定位 STM32CubeIDE 安装目录，还原中止。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}

$ini     = Join-Path $dir 'stm32cubeide.ini'
$dropins = Join-Path $dir 'dropins'
$zhDir   = Join-Path $dropins 'stm32cubeide-zh'
$bi      = Join-Path $dir 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'

# ---------- 3. 运行中检查 ----------
$running = Get-Process -Name 'stm32cubeide' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "[×] STM32CubeIDE 正在运行，请先完全关闭再还原。" -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 2
}

# ---------- 4. 还原 ----------
if (Test-Path $zhDir) {
    Remove-Item $zhDir -Recurse -Force
    Write-Host "已移除汉化包目录：$zhDir"
} else { Write-Host "未发现汉化包目录，跳过" }

# dropins 若已空则一并删除（恢复原状：原本无 dropins 目录）
if ((Test-Path $dropins) -and -not (Get-ChildItem $dropins -Force)) {
    Remove-Item $dropins -Force; Write-Host "已移除空的 dropins 目录"
}

# 恢复包清单（去掉注册的中文包）
if (Test-Path $bi) {
    $biBak = "$bi.zhbak"
    if (Test-Path $biBak) {
        Copy-Item -LiteralPath $biBak $bi -Force; Write-Host "已从 $biBak 恢复包清单"
    } else {
        $lines = [System.IO.File]::ReadAllLines($bi, [System.Text.Encoding]::UTF8)
        $kept = $lines | Where-Object { $_ -notmatch [regex]::Escape('stm32cubeide-zh') }
        if ($kept.Count -ne $lines.Count) {
            [System.IO.File]::WriteAllLines($bi, $kept, (New-Object System.Text.UTF8Encoding $false))
            Write-Host "已从包清单中移除中文包条目（$($lines.Count - $kept.Count) 条）"
        } else { Write-Host "包清单无需改动" }
    }
}

# 恢复启动配置
$bak = "$ini.zhbak"
if (Test-Path $bak) { Copy-Item -LiteralPath $bak $ini -Force; Write-Host "已从 $bak 恢复启动配置" }
else {
    $lines = [System.IO.File]::ReadAllLines($ini, [System.Text.Encoding]::UTF8)
    if (($lines -contains '-nl') -or ($lines -contains '-Dosgi.nl=zh_CN')) {
        $out = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '-nl') { $i++; continue }   # 连同下一行 zh_CN 一起跳过
            if ($lines[$i].Trim() -eq '-Dosgi.nl=zh_CN') { continue }
            [void]$out.Add($lines[$i])
        }
        [System.IO.File]::WriteAllLines($ini, $out, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "已从启动配置中移除 -nl zh_CN 与 -Dosgi.nl=zh_CN"
    } else { Write-Host "启动配置无需改动" }
}

Write-Host ''
Write-Host "[√] 还原完成，STM32CubeIDE 将恢复英文界面。" -ForegroundColor Green

if (-not $NoPause) {
    Write-Host ''
    Read-Host '还原完成，按回车键关闭窗口' | Out-Null
}
