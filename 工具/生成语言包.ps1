# 由词库生成 Eclipse NLS 简体中文片段包（nl_zh fragments）。
# 输入：词库\st_strings.tsv（导出结果） + 词库\zh\*.tsv（en<TAB>zh 词库）
# 输出：成品\fragments\<宿主符号名>.nl_zh_1.0.0.jar
# 原理：片段包挂在宿主插件上（Fragment-Host），随宿主类加载器提供 <资源名>_zh_CN.properties，
#       配合启动参数 -nl zh_CN 即可显示中文；未收录的键自动回退到宿主自带文案或英文。
param(
    [string]$Root = 'C:\stm32ide\STM32CubeIDE_1.19.0\STM32CubeIDE',
    [string]$Version = '1.0.0'
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$proj   = Split-Path -Parent $PSScriptRoot
$tsv    = Join-Path $proj '词库\st_strings.tsv'
$dictDir= Join-Path $proj '词库\zh'
$outDir = Join-Path $proj '成品\fragments'
$plugins= Join-Path $Root 'plugins'
if (-not (Test-Path $tsv)) { Write-Error "缺少 $tsv，请先运行 导出词条.ps1"; exit 1 }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# ---- 1. 读词库：en -> zh ----
$dict = @{}
$dup = 0
foreach ($f in (Get-ChildItem $dictDir -Filter '*.tsv' | Sort-Object Name)) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
    $first = $true
    foreach ($line in $lines) {
        if ($first) { $first = $false; if ($line -match '^\s*en\s') { continue } }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $p = $line -split "`t", 2
        if ($p.Count -lt 2 -or [string]::IsNullOrWhiteSpace($p[0])) { continue }
        if ($dict.ContainsKey($p[0])) { $dup++; continue }
        $dict[$p[0]] = $p[1].Trim()
    }
}
Write-Output "词库条目：$($dict.Count)（重复跳过 $dup）"

# ---- 2. 读导出结果，取出有译文的条目 ----
$rows = [System.IO.File]::ReadAllLines($tsv, [System.Text.Encoding]::UTF8)
$byJar = @{}       # jar -> @{ path -> [键值对列表] }
$used = 0; $missKey = New-Object System.Collections.ArrayList
for ($i = 1; $i -lt $rows.Count; $i++) {
    $c = $rows[$i] -split "`t"
    if ($c.Count -lt 6) { continue }
    $jar = $c[0]; $path = $c[1]; $key = $c[2]; $en = $c[3]
    if ($c[5] -ne '1') { continue }              # 只处理缺口条目
    if (-not $dict.ContainsKey($en)) { continue }
    $zh = $dict[$en]
    if ([string]::IsNullOrWhiteSpace($zh)) { continue }
    if (-not $byJar.ContainsKey($jar)) { $byJar[$jar] = @{} }
    if (-not $byJar[$jar].ContainsKey($path)) { $byJar[$jar][$path] = New-Object System.Collections.ArrayList }
    [void]$byJar[$jar][$path].Add(@($key, $zh))
    $used++
}
Write-Output "命中译文条目：$used"

# ---- 3. 取值转义（非 ASCII -> \uXXXX；反斜杠转义序列按原文保留）----
function Esc-Value([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -lt 32 -or $code -gt 126) { [void]$sb.Append('\u' + $code.ToString('x4')) }
        elseif ($ch -eq '`t') { [void]$sb.Append('\t') }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

# ---- 4. OSGi 清单按 72 字节折行（续行必须以单个空格开头，否则清单非法、片段无法装载）----
function Format-Manifest([string[]]$lines) {
    $out = New-Object System.Collections.ArrayList
    foreach ($l in $lines) {
        $line = ''
        $count = 0
        foreach ($ch in $l.ToCharArray()) {
            $b = [System.Text.Encoding]::UTF8.GetByteCount([string]$ch)
            if (($count + $b) -gt 72) {
                [void]$out.Add($line)
                $line = ' '          # 续行前导空格
                $count = 1
            }
            $line += $ch; $count += $b
        }
        [void]$out.Add($line)
    }
    [void]$out.Add('')
    return ($out -join "`r`n")
}

# ---- 5. 读宿主 jar 的 Bundle-SymbolicName / Bundle-Version ----
function Get-HostHeaders([string]$jarPath) {
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
    if (-not $sn) {
        # 回退：从文件名推断（去掉 _版本.jar）
        $sn = [System.IO.Path]::GetFileNameWithoutExtension($jarPath) -replace '_\d.*$',''
    }
    return @{ sn = $sn; ver = $ver }
}

# ---- 6. 逐个宿主生成片段包 ----
$made = New-Object System.Collections.ArrayList
$keysTotal = 0
foreach ($jar in ($byJar.Keys | Sort-Object)) {
    $hostJar = Join-Path $plugins $jar
    if (-not (Test-Path $hostJar)) { Write-Warning "找不到宿主：$jar"; continue }
    $h = Get-HostHeaders $hostJar
    $sn = $h.sn
    $fragSn = "$sn.nl_zh"
    $fragFile = Join-Path $outDir ("$fragSn`_$Version.jar")
    if (Test-Path $fragFile) { Remove-Item $fragFile -Force }

    $zip = [System.IO.Compression.ZipFile]::Open($fragFile, [System.IO.Compression.ZipArchiveMode]::Create)

    # 清单（一行尽量不超过 72 字节，避免折行）
    $manifest = Format-Manifest @(
        'Manifest-Version: 1.0',
        'Bundle-ManifestVersion: 2',
        "Bundle-SymbolicName: $fragSn",
        "Bundle-Version: $Version",
        "Fragment-Host: $sn",
        "Bundle-Name: $fragSn",
        'Bundle-Vendor: opencode-zh'
    )
    $me = $zip.CreateEntry('META-INF/MANIFEST.MF', [System.IO.Compression.CompressionLevel]::Optimal)
    $sw = New-Object IO.StreamWriter($me.Open(), (New-Object System.Text.UTF8Encoding $false))
    $sw.Write($manifest); $sw.Flush(); $sw.Close()

    # 资源
    $n = 0
    foreach ($path in ($byJar[$jar].Keys | Sort-Object)) {
        $target = $path -replace '\.properties$', '_zh_CN.properties'
        $sb = New-Object System.Text.StringBuilder
        foreach ($kv in $byJar[$jar][$path]) {
            [void]$sb.AppendLine("$($kv[0])=$(Esc-Value $kv[1])")
        }
        $ce = $zip.CreateEntry($target, [System.IO.Compression.CompressionLevel]::Optimal)
        $cw = New-Object IO.StreamWriter($ce.Open(), (New-Object System.Text.ASCIIEncoding))
        $cw.Write($sb.ToString()); $cw.Flush(); $cw.Close()
        $n += $byJar[$jar][$path].Count
    }
    $zip.Dispose()
    $keysTotal += $n
    [void]$made.Add("$fragSn`t$n`t$fragFile")
}

$enc = New-Object System.Text.UTF8Encoding $true
$listPath = Join-Path $proj '成品\fragments\fragments.list.tsv'
[System.IO.File]::WriteAllText($listPath, ("fragment_symbolic_name`tkeys`tfile`r`n" + ($made -join "`r`n") + "`r`n"), $enc)

Write-Output "生成片段包：$($made.Count) 个，共写入译文 $keysTotal 条"
Write-Output "输出目录：$outDir"
Write-Output "清单：$listPath"
