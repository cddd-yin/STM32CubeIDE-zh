# 安装 STM32CubeIDE 汉化：把中文片段包与 Eclipse Babel 官方中文包装入 dropins，
# 并注册进启动配置（bundles.info + -nl zh_CN），使桌面/开始菜单的普通启动即为中文。
# 注意：本脚本会写入 STM32CubeIDE 安装目录（外部修改），运行前请确认已获授权。
param(
    [string]$Root = 'C:\stm32ide\STM32CubeIDE_1.19.0\STM32CubeIDE'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$proj    = Split-Path -Parent $PSScriptRoot
$fragSrc = Join-Path $proj '成品\fragments'
$babelSrc= Join-Path $proj '成品\babel'
$ini     = Join-Path $Root 'stm32cubeide.ini'
$exe     = Join-Path $Root 'stm32cubeide.exe'
$dropins = Join-Path $Root 'dropins'
$zhDir   = Join-Path $dropins 'stm32cubeide-zh'
$dstPlg  = Join-Path $zhDir 'plugins'
$dstFea  = Join-Path $zhDir 'features'
$bi      = Join-Path $Root 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'

if (-not (Test-Path $exe))  { Write-Error "未找到 STM32CubeIDE：$exe"; exit 1 }
if (-not (Test-Path $ini))  { Write-Error "未找到启动配置：$ini"; exit 1 }
if (-not (Test-Path $bi))   { Write-Error "未找到包清单：$bi"; exit 1 }

# 0. 运行中检查
$running = Get-Process -Name 'stm32cubeide' -ErrorAction SilentlyContinue
if ($running) { Write-Warning "STM32CubeIDE 正在运行（PID $($running.Id -join ',')），请先关闭再安装。" ; exit 2 }

# 1. 备份启动配置与包清单（只备份一次，作为还原母本）
$iniBak = "$ini.zhbak"
$biBak  = "$bi.zhbak"
if (-not (Test-Path $iniBak)) { Copy-Item $ini $iniBak -Force; Write-Output "已备份启动配置：$iniBak" }
else { Write-Output "启动配置备份已存在：$iniBak" }
if (-not (Test-Path $biBak)) { Copy-Item $bi $biBak -Force; Write-Output "已备份包清单：$biBak" }
else { Write-Output "包清单备份已存在：$biBak" }

# 2. 建立 dropins 目录并复制自建片段包（留档；真正生效靠第 4 步注册）
New-Item -ItemType Directory -Force -Path $dstPlg, $dstFea | Out-Null
Get-ChildItem $fragSrc -Filter '*.jar' | ForEach-Object { Copy-Item $_.FullName $dstPlg -Force }
$nFrag = (Get-ChildItem $fragSrc -Filter '*.jar' | Measure-Object).Count
Write-Output "已安装自建中文片段包：$nFrag 个"

# 3. 解包 Eclipse Babel 官方中文包（eclipse/plugins|features -> dropins/...）
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
    Write-Output ("已解包 {0}：{1} 个条目" -f $zipPath.Name, $count)
    $nBabel += $count
}

# 4. 把 dropins 里的全部中文 jar 注册进默认配置的 bundles.info。
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
Write-Output "已注册中文包到 bundles.info：$added 个（基于备份母本重建，共 $($lines.Count) 行）"

# 5. 在 stm32cubeide.ini 中启用 zh_CN。
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
Write-Output "已在启动配置加入：-nl zh_CN（-vmargs 前）、-Dosgi.nl=zh_CN（-vmargs 后）"

Write-Output ''
Write-Output "安装完成：片段包 $nFrag 个，Babel 条目 $nBabel 个，目标 $zhDir"
Write-Output '请从桌面快捷方式启动 STM32CubeIDE 查看效果；如需还原，运行 工具\还原英文.cmd'
