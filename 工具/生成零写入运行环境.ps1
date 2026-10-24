# 生成「零写入」汉化运行环境：把独立配置目录放在仓库 runtime\，IDE 从仓库加载中文片段包与 Babel 包。
# 不修改 STM32CubeIDE 安装目录任何文件（只读其 plugins / configuration 作为母本）。
# 安装目录自动探测；成功后在 runtime\生成信息.txt 记录来源目录，供启动器校验是否需要重新生成。
param(
    [string]$Root = '',    # STM32CubeIDE 安装目录（留空自动探测）
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

. (Join-Path $PSScriptRoot '探测安装目录.ps1')
$dir = Resolve-IdEDir -Hint $Root
if (-not $dir) {
    Write-Host '[×] 未能定位 STM32CubeIDE 安装目录，生成中止。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}

$proj    = Split-Path -Parent $PSScriptRoot
$rt      = Join-Path $proj 'runtime'
$cfg     = Join-Path $rt 'configuration'
$simpleC = Join-Path $cfg 'org.eclipse.equinox.simpleconfigurator'
$extra   = Join-Path $rt 'extra-plugins'

# 1. 目录
foreach ($d in @($rt, $cfg, $simpleC, $extra, (Join-Path $rt 'p2'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# 2. config.ini：以原配置为母本，替换 p2 数据区并加 osgi.nl
$srcIni = Join-Path $dir 'configuration\config.ini'
$txt = [System.IO.File]::ReadAllText($srcIni, [System.Text.Encoding]::UTF8)
$txt = $txt -replace '(?m)^eclipse\.p2\.data\.area=.*$', 'eclipse.p2.data.area=@config.dir/../p2'
if ($txt -notmatch '(?m)^osgi\.nl=') { $txt = $txt.TrimEnd() + "`r`nosgi.nl=zh_CN`r`n" }
[System.IO.File]::WriteAllText((Join-Path $cfg 'config.ini'), $txt, (New-Object System.Text.UTF8Encoding $false))

# 3. 释放中文片段包（自建 + Babel）到 runtime\extra-plugins
Get-ChildItem (Join-Path $proj '成品\fragments') -Filter '*.jar' | ForEach-Object {
    Copy-Item $_.FullName $extra -Force
}
$babelCount = 0
foreach ($zipPath in (Get-ChildItem (Join-Path $proj '成品\babel') -Filter '*.zip')) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath.FullName)
    foreach ($e in $zip.Entries) {
        if ($e.FullName -match '^eclipse/plugins/(.+\.jar)$') {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $extra $Matches[1]), $true)
            $babelCount++
        }
    }
    $zip.Dispose()
}

# 4. 读清单头（符号名 / 版本）
function Get-Headers([string]$jarPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
    $sn = $null; $ver = $null
    $e = $zip.Entries | Where-Object { $_.FullName -eq 'META-INF/MANIFEST.MF' } | Select-Object -First 1
    if ($e) {
        $sr = New-Object IO.StreamReader($e.Open())
        $t = ($sr.ReadToEnd() -replace "`r?`n ", ''); $sr.Close()
        foreach ($ln in ($t -split "`r?`n")) {
            if ($ln -match '^Bundle-SymbolicName:\s*(.+)$') { $sn = ($Matches[1] -replace ';.*$','').Trim() }
            if ($ln -match '^Bundle-Version:\s*(.+)$') { $ver = $Matches[1].Trim() }
        }
    }
    $zip.Dispose()
    return @{ sn = $sn; ver = $ver }
}

# 5. bundles.info = 原件 + 追加条目（绝对 file: URI，非 ASCII 自动百分号编码）
$srcInfo = Join-Path $dir 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'
$lines = New-Object System.Collections.ArrayList
foreach ($l in [System.IO.File]::ReadAllLines($srcInfo, [System.Text.Encoding]::UTF8)) { [void]$lines.Add($l) }

$added = 0
foreach ($jar in (Get-ChildItem $extra -Filter '*.jar' | Sort-Object Name)) {
    $h = Get-Headers $jar.FullName
    if (-not $h.sn) { $h.sn = [System.IO.Path]::GetFileNameWithoutExtension($jar.Name) }
    if (-not $h.ver) { $h.ver = '0.0.0' }
    $uri = ([System.Uri]::new($jar.FullName)).AbsoluteUri
    [void]$lines.Add("$($h.sn),$($h.ver),$uri,4,false")
    $added++
}
[System.IO.File]::WriteAllLines((Join-Path $simpleC 'bundles.info'), $lines, (New-Object System.Text.UTF8Encoding $false))

# 6. 记录来源目录标记（启动器据此判断仓库移动/换机后是否需要重新生成）
[System.IO.File]::WriteAllText((Join-Path $rt '生成信息.txt'),
    "source=$dir`r`ngenerated=$(Get-Date -Format 'yyyy-MM-dd HH:mm')", (New-Object System.Text.UTF8Encoding $false))

Write-Host "零写入运行环境已生成："
Write-Host "  IDE 目录  $dir"
Write-Host "  配置目录  $cfg"
Write-Host "  附加插件  $added 个（自建片段 + Babel $babelCount），$extra"
Write-Host "  清单      $((Join-Path $simpleC 'bundles.info'))（共 $($lines.Count) 行）"
Write-Host "  双击 工具\以汉化启动-零写入.cmd 即可以中文启动（不改安装目录）"

if (-not $NoPause) {
    Write-Host ''
    Read-Host '生成完成，按回车键关闭窗口' | Out-Null
}
