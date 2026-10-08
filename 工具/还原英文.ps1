# 还原 STM32CubeIDE 英文界面：移除 dropins 中的汉化包，并从 .zhbak 恢复启动配置与包清单。
param(
    [string]$Root = 'C:\stm32ide\STM32CubeIDE_1.19.0\STM32CubeIDE'
)
$ErrorActionPreference = 'Stop'

$ini     = Join-Path $Root 'stm32cubeide.ini'
$dropins = Join-Path $Root 'dropins'
$zhDir   = Join-Path $dropins 'stm32cubeide-zh'
$bi      = Join-Path $Root 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'

$running = Get-Process -Name 'stm32cubeide' -ErrorAction SilentlyContinue
if ($running) { Write-Warning "STM32CubeIDE 正在运行（PID $($running.Id -join ',')），请先关闭再还原。" ; exit 2 }

if (Test-Path $zhDir) {
    Remove-Item $zhDir -Recurse -Force
    Write-Output "已移除汉化包目录：$zhDir"
} else { Write-Output "未发现汉化包目录，跳过" }

# dropins 若已空则一并删除（恢复原状：原本无 dropins 目录）
if ((Test-Path $dropins) -and -not (Get-ChildItem $dropins -Force)) {
    Remove-Item $dropins -Force; Write-Output "已移除空的 dropins 目录"
}

# 恢复包清单（去掉注册的中文包）
$biBak = "$bi.zhbak"
if (Test-Path $biBak) {
    Copy-Item $biBak $bi -Force; Write-Output "已从 $biBak 恢复包清单"
} else {
    $lines = [System.IO.File]::ReadAllLines($bi, [System.Text.Encoding]::UTF8)
    $kept = $lines | Where-Object { $_ -notmatch [regex]::Escape('stm32cubeide-zh') }
    if ($kept.Count -ne $lines.Count) {
        [System.IO.File]::WriteAllLines($bi, $kept, (New-Object System.Text.UTF8Encoding $false))
        Write-Output "已从包清单中移除中文包条目（$($lines.Count - $kept.Count) 条）"
    } else { Write-Output "包清单无需改动" }
}

# 恢复启动配置
$bak = "$ini.zhbak"
if (Test-Path $bak) { Copy-Item $bak $ini -Force; Write-Output "已从 $bak 恢复启动配置" }
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
        Write-Output "已从启动配置中移除 -nl zh_CN 与 -Dosgi.nl=zh_CN"
    } else { Write-Output "启动配置无需改动" }
}

Write-Output ''
Write-Output '还原完成，STM32CubeIDE 将恢复英文界面。'
