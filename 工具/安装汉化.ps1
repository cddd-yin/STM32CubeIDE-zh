#Requires -Version 5.1
# 安装 STM32CubeIDE 汉化：把中文片段包与 Eclipse Babel 官方中文包装入 dropins，
# 并注册进启动配置（bundles.info + -nl zh_CN），使桌面/开始菜单的普通启动即为中文。
# 易用性：自动请求管理员权限（UAC）；自动探测安装目录（参数 → 注册表 → 运行中进程 → 常见路径），
#         探测失败时可交互粘贴路径，无需命令行知识。
[CmdletBinding()]
param(
    [string]$Root = '',    # STM32CubeIDE 安装目录（留空自动探测）
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---------- 1. 自动请求管理员权限（写安装目录需要） ----------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host '[i] 写入 STM32CubeIDE 安装目录需要管理员权限，正在弹出授权窗口……' -ForegroundColor Yellow
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
        Write-Host '    可右键「一键安装汉化.bat」→「以管理员身份运行」重试。' -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
        exit 1
    }
}

# ---------- 2. 定位源文件 ----------
$proj     = Split-Path -Parent $PSScriptRoot
$fragSrc  = Join-Path $proj '成品\fragments'
$babelSrc = Join-Path $proj '成品\babel'

if (-not (Test-Path -LiteralPath $fragSrc)) {
    Write-Host "[×] 找不到汉化包：$fragSrc" -ForegroundColor Red
    Write-Host '    请确认已完整解压整个压缩包，且没有单独移动「成品」文件夹。' -ForegroundColor Yellow
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}

# ---------- 3. 探测 STM32CubeIDE 安装目录（共享模块） ----------
. (Join-Path $PSScriptRoot '探测安装目录.ps1')

$dir = Resolve-IdEDir -Hint $Root
if (-not $dir) {
    Write-Host '[×] 未能定位 STM32CubeIDE 安装目录，安装中止。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}

$ini     = Join-Path $dir 'stm32cubeide.ini'
$dropins = Join-Path $dir 'dropins'
$zhDir   = Join-Path $dropins 'stm32cubeide-zh'
$dstPlg  = Join-Path $zhDir 'plugins'
$dstFea  = Join-Path $zhDir 'features'
$bi      = Join-Path $dir 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'

if (-not (Test-Path -LiteralPath $bi)) {
    Write-Host "[×] 未找到包清单：$bi" -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}

# ---------- 4. 运行中检查 ----------
$running = Get-Process -Name 'stm32cubeide' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "[×] STM32CubeIDE 正在运行，请先完全关闭再安装。" -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 2
}

# ---------- 5. 备份启动配置与包清单（只备份一次，作为还原母本） ----------
$iniBak = "$ini.zhbak"
$biBak  = "$bi.zhbak"
if (-not (Test-Path $iniBak)) { Copy-Item -LiteralPath $ini $iniBak -Force; Write-Host "已备份启动配置：$iniBak" }
else { Write-Host "启动配置备份已存在：$iniBak" }
if (-not (Test-Path $biBak))  { Copy-Item -LiteralPath $bi $biBak -Force;  Write-Host "已备份包清单：$biBak" }
else { Write-Host "包清单备份已存在：$biBak" }

# ---------- 6. 建立 dropins 目录并复制自建片段包 ----------
New-Item -ItemType Directory -Force -Path $dstPlg, $dstFea | Out-Null
Get-ChildItem $fragSrc -Filter '*.jar' | ForEach-Object { Copy-Item $_.FullName $dstPlg -Force }
$nFrag = (Get-ChildItem $fragSrc -Filter '*.jar' | Measure-Object).Count
Write-Host "已安装自建中文片段包：$nFrag 个"

# ---------- 7. 解包 Eclipse Babel 官方中文包（eclipse/plugins|features -> dropins/...） ----------
$nBabel = 0
foreach ($zipPath in (Get-ChildItem $babelSrc -Filter '*.zip' | Sort-Object Name)) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath.FullName)
    $count = 0
    foreach ($e in $zip.Entries) {
        if ($e.FullName -match '^eclipse/plugins/(.+\.jar)$') {
            $target = Join-Path $dstPlg $Matches[1]
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true); $count++
        } elseif ($e.FullName -match '^eclipse/features/(.+)$' -and $e.Length -gt 0) {
            $target = Join-Path $dstFea ($Matches[1] -replace '/', '\')
            New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true); $count++
        }
    }
    $zip.Dispose()
    Write-Host ("已解包 {0}：{1} 个条目" -f $zipPath.Name, $count)
    $nBabel += $count
}

# ---------- 8. 把 dropins 里的全部中文 jar 注册进默认配置的 bundles.info ----------
#    实测本产品的 p2 不接管 dropins（清单毫无变化），因此必须直接写进包清单；
#    以备份为母本重建，天然幂等、不会重复追加。
function Get-Headers([string]$jarPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
    $sn = $null; $ver = $null
    $e = $zip.Entries | Where-Object { $_.FullName -eq 'META-INF/MANIFEST.MF' } | Select-Object -First 1
    if ($e) {
        $sr = New-Object IO.StreamReader($e.Open())
        $text = $sr.ReadToEnd(); $sr.Close()
        $unfolded = ($text -replace "`r?`n ", '')
        foreach ($ln in ($unfolded -split "`r?`n")) {
            if ($ln -match '^Bundle-SymbolicName:\s*(.+)$') { $sn = ($Matches[1] -replace ';.*$','').Trim() }
            if ($ln -match '^Bundle-Version:\s*(.+)$') { $ver = $Matches[1].Trim() }
        }
    }
    $zip.Dispose()
    return @{ sn = $sn; ver = $ver }
}

$lines = New-Object System.Collections.ArrayList
foreach ($l in [System.IO.File]::ReadAllLines($biBak, [System.Text.Encoding]::UTF8)) { [void]$lines.Add($l) }
$added = 0
foreach ($jar in (Get-ChildItem $dstPlg -Filter '*.jar' | Sort-Object Name)) {
    $h = Get-Headers $jar.FullName
    if (-not $h.sn) { $h.sn = [System.IO.Path]::GetFileNameWithoutExtension($jar.Name) }
    if (-not $h.ver) { $h.ver = '0.0.0' }
    $uri = ([System.Uri]::new($jar.FullName)).AbsoluteUri
    [void]$lines.Add("$($h.sn),$($h.ver),$uri,4,false")
    $added++
}
[System.IO.File]::WriteAllLines($bi, $lines, (New-Object System.Text.UTF8Encoding $false))
Write-Host "已注册中文包到 bundles.info：$added 个（基于备份母本重建，共 $($lines.Count) 行）"

# ---------- 9. 在 stm32cubeide.ini 中启用 zh_CN ----------
#    -nl 是启动器参数，必须在 -vmargs 之前；-Dosgi.nl 是 JVM 参数，放在 -vmargs 之后。
#    同样以备份为母本重建，保证幂等。
$srcLines = [System.IO.File]::ReadAllLines($iniBak, [System.Text.Encoding]::UTF8)
$out = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $srcLines.Count; $i++) {
    $t = $srcLines[$i].Trim()
    if ($t -eq '-nl') { $i++; continue }                 # 去掉旧位置的 -nl 及其后的 zh_CN
    if ($t -eq '-Dosgi.nl=zh_CN') { continue }
    if ($t -eq '-vmargs') { [void]$out.Add('-nl'); [void]$out.Add('zh_CN') }
    [void]$out.Add($srcLines[$i])
    if ($t -eq '-vmargs') { [void]$out.Add('-Dosgi.nl=zh_CN') }
}
[System.IO.File]::WriteAllLines($ini, $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host "已在启动配置加入：-nl zh_CN（-vmargs 前）、-Dosgi.nl=zh_CN（-vmargs 后）"

Write-Host ''
Write-Host "STM32CubeIDE 目录：$dir"
Write-Host "[√] 安装完成：片段包 $nFrag 个，Babel 条目 $nBabel 个。" -ForegroundColor Green
Write-Host '请从桌面快捷方式启动 STM32CubeIDE 查看效果；如需还原，双击仓库根目录的「一键还原英文.bat」。'

if (-not $NoPause) {
    Write-Host ''
    Read-Host '安装完成，按回车键关闭窗口' | Out-Null
}
