# 生成「零写入」汉化运行环境：把独立配置目录放在工作区，IDE 从工作区加载中文片段包与 Babel 包。
# 不修改 C:\stm32ide 下任何文件（只读其 plugins / configuration 作为母本）。
param(
    [string]$Root = 'C:\stm32ide\STM32CubeIDE_1.19.0\STM32CubeIDE'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$proj    = Split-Path -Parent $PSScriptRoot
$rt      = Join-Path $proj 'runtime'
$cfg     = Join-Path $rt 'configuration'
$simpleC = Join-Path $cfg 'org.eclipse.equinox.simpleconfigurator'
$extra   = Join-Path $rt 'extra-plugins'

if (-not (Test-Path (Join-Path $Root 'stm32cubeide.exe'))) { Write-Error "未找到 IDE：$Root"; exit 1 }

# 1. 目录
foreach ($d in @($rt, $cfg, $simpleC, $extra, (Join-Path $rt 'p2'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# 2. config.ini：以原配置为母本，替换 p2 数据区并加 osgi.nl
$srcIni = Join-Path $Root 'configuration\config.ini'
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
$srcInfo = Join-Path $Root 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'
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

# 6. 启动器（.cmd 须用系统 ANSI/OEM 代码页保存：批处理按该页解析，且工作区路径含中文，
#    若写成 UTF-8 会导致 start 行的中文路径被解错、启动失败）
$exe = Join-Path $Root 'stm32cubeide.exe'
$ws  = Join-Path $env:USERPROFILE 'STM32CubeIDE\workspace_1.19.0'
$cmd = @"
@echo off
rem 零写入汉化启动：配置目录在工作区 runtime\configuration，不改 C:\stm32ide 任何文件
start "" "$exe" -configuration "$cfg" -nl zh_CN -data "$ws"
"@
[System.IO.File]::WriteAllText((Join-Path $proj '工具\以汉化启动-零写入.cmd'), $cmd, [System.Text.Encoding]::GetEncoding(936))

Write-Output "零写入运行环境已生成："
Write-Output "  配置目录 $cfg"
Write-Output "  附加插件 $added 个（自建片段 38 + Babel $babelCount），$extra"
Write-Output "  清单 $((Join-Path $simpleC 'bundles.info'))（共 $($lines.Count) 行）"
Write-Output "  启动器 工具\以汉化启动-零写入.cmd"
