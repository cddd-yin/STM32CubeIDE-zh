# 从 STM32CubeIDE 自有的 com.st.*.*.jar 插件中抽取 Eclipse NLS 词条，区分英文原文与 ST 自带中文。
# 输出：词库\st_strings.tsv
#   jar <TAB> 资源基路径 <TAB> 键 <TAB> 英文 <TAB> ST自带中文 <TAB> 是否缺口
# 说明：只读取插件 JAR，不修改任何文件。基准文件与 xx / xx_YY 本地化文件按基路径配对。
param(
    [string]$Root = 'C:\stm32ide\STM32CubeIDE_1.19.0\STM32CubeIDE',
    [string]$Out  = ''
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $Out) {
    $proj = Split-Path -Parent $PSScriptRoot
    $Out = Join-Path $proj '词库\st_strings.tsv'
}

$plugins = Join-Path $Root 'plugins'
if (-not (Test-Path $plugins)) { Write-Error "找不到插件目录：$plugins"; exit 1 }

$excludeKey = '^(Copyright|pluginName|providerName|output|source|bin\.includes|Bundle-|eclipse\.|jars\.|allowBinaryCycles|feature\.|product\.)$'

function Read-Properties([string]$text) {
    $lines = $text -split "\r?\n"
    $map = @{}
    $curKey = $null; $curVal = $null
    foreach ($line in $lines) {
        if ($null -ne $curKey) {
            $curVal += $line
            if (-not $line.EndsWith('\')) { if (-not $map.ContainsKey($curKey)) { $map[$curKey] = $curVal }; $curKey = $null; $curVal = $null; continue }
            $curVal = $curVal.Substring(0, $curVal.Length - 1)
            continue
        }
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#') -or $t.StartsWith('!')) { continue }
        $m = [regex]::Match($line, '^\s*([^=:\s]+)\s*[=:]\s?(.*)$')
        if (-not $m.Success) { continue }
        $k = $m.Groups[1].Value; $v = $m.Groups[2].Value
        if ($v.EndsWith('\')) { $curKey = $k; $curVal = $v.Substring(0, $v.Length - 1) }
        else { if (-not $map.ContainsKey($k)) { $map[$k] = $v } }
    }
    return $map
}

# 把一个 .properties 路径拆成 基路径 + 语言标签
function Split-Locale([string]$path) {
    $m = [regex]::Match($path, '^(.*?)(_([a-z]{2,3})(_[A-Z]{2})?)?\.properties$')
    if (-not $m.Success) { return @{ base = $path; locale = '' } }
    return @{ base = ($m.Groups[1].Value + '.properties'); locale = $m.Groups[3].Value }
}

$rows = New-Object System.Collections.ArrayList
$summary = New-Object System.Collections.ArrayList

foreach ($jar in (Get-ChildItem $plugins -File -Filter 'com.st.*.jar' | Sort-Object Name)) {
    try { $zip = [System.IO.Compression.ZipFile]::OpenRead($jar.FullName) } catch { continue }

    $props = @{}        # base路径 -> @{ locale = @{ key = value } }
    foreach ($entry in ($zip.Entries | Where-Object { $_.FullName -match '\.properties$' })) {
        $parts = Split-Locale $entry.FullName
        $sr = New-Object IO.StreamReader($entry.Open())
        $text = $sr.ReadToEnd(); $sr.Close()
        if (-not $props.ContainsKey($parts.base)) { $props[$parts.base] = @{} }
        $props[$parts.base][$parts.locale] = Read-Properties $text
    }
    $zip.Dispose()

    $n = 0; $gap = 0
    foreach ($base in ($props.Keys | Sort-Object)) {
        $locales = $props[$base]
        if (-not $locales.ContainsKey('')) { continue }
        $zhMap = $null
        if ($locales.ContainsKey('zh_CN')) { $zhMap = $locales['zh_CN'] }
        elseif ($locales.ContainsKey('zh')) { $zhMap = $locales['zh'] }
        foreach ($k in ($locales[''].Keys | Sort-Object)) {
            if ($k -match $excludeKey) { continue }
            $en = $locales[''][$k]
            if ([string]::IsNullOrWhiteSpace($en)) { continue }
            $zh = ''
            if ($zhMap -and $zhMap.ContainsKey($k)) { $zh = $zhMap[$k] }
            $enEsc = ($en -replace "`t", ' ').Trim()
            $zhEsc = ($zh -replace "`t", ' ').Trim()
            $isGap = if ($zhEsc -eq '') { 1 } else { 0 }
            [void]$rows.Add("$($jar.Name)`t$base`t$k`t$enEsc`t$zhEsc`t$isGap")
            $n++; if ($isGap -eq 1) { $gap++ }
        }
    }
    if ($n -gt 0) { [void]$summary.Add("$($jar.Name)`t$n`t$gap") }
}

$enc = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($Out, ("jar`tpath`tkey`ten`tst_zh`tgap`r`n" + ($rows -join "`r`n") + "`r`n"), $enc)
$sumOut = [System.IO.Path]::ChangeExtension($Out, '.summary.tsv')
[System.IO.File]::WriteAllText($sumOut, ("jar`tkeys`tgap`r`n" + ($summary -join "`r`n") + "`r`n"), $enc)

$total = $rows.Count
$gapAll = 0; foreach ($r in $rows) { if ($r.EndsWith("`t1")) { $gapAll++ } }
Write-Output "ST 自有文案：$total 条；ST 已带中文：$($total-$gapAll) 条；缺口（待翻译）：$gapAll 条"
Write-Output "输出：$Out"
