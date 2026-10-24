# 共享模块：探测 STM32CubeIDE 安装目录。被 安装/还原/启动 相关脚本通过 dot-source 复用。
# 用法：. (Join-Path $PSScriptRoot '探测安装目录.ps1')  然后调用 Resolve-IdEDir -Hint $Root

function Test-IdERoot([string]$Path) {
    if (-not $Path) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'stm32cubeide.exe') -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $Path 'stm32cubeide.ini') -PathType Leaf)
}

function Resolve-IdEDir([string]$Hint) {
    if ($Hint) {
        $Hint = $Hint.Trim().Trim('"')
        if (Test-IdERoot $Hint) { return (Resolve-Path -LiteralPath $Hint).Path }
        Write-Host "[×] 指定目录里找不到 STM32CubeIDE（应同时包含 stm32cubeide.exe 与 stm32cubeide.ini）：$Hint" -ForegroundColor Red
        return $null
    }

    $cands = New-Object System.Collections.Generic.List[string]

    # (1) 注册表卸载信息（标准安装器会登记；32/64 位视图都查）
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $base)) { continue }
        try {
            Get-ChildItem -Path $base -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $v = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                    if ($v.DisplayName -like '*STM32CubeIDE*') {
                        foreach ($p in @('InstallLocation', 'UninstallString', 'DisplayIcon')) {
                            if ($v.$p) {
                                $d = "$($v.$p)".Trim('"')
                                if ($d -match '\.(exe|ini)$') { $d = Split-Path -Parent $d }
                                [void]$cands.Add($d.TrimEnd('\'))
                            }
                        }
                    }
                } catch { }
            }
        } catch { }
    }

    # (2) 运行中的 STM32CubeIDE 所在目录
    try {
        $p = Get-Process -Name 'stm32cubeide' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p -and $p.Path) { [void]$cands.Add((Split-Path -Parent $p.Path)) }
    } catch { }

    # (3) 各磁盘常见安装位置（官方默认 C:\ST\STM32CubeIDE_<版本>\STM32CubeIDE）
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($pat in @('ST\STM32CubeIDE_*\STM32CubeIDE',
                           'Program Files\STMicroelectronics\STM32CubeIDE*\STM32CubeIDE',
                           'Program Files\STM32CubeIDE*',
                           'stm32ide\STM32CubeIDE_*\STM32CubeIDE')) {
            $full = Join-Path $drive.Root $pat
            Get-Item -Path $full -ErrorAction SilentlyContinue | ForEach-Object { [void]$cands.Add($_.FullName) }
        }
    }

    foreach ($c in $cands) {
        if (Test-IdERoot $c) { return (Resolve-Path -LiteralPath $c).Path }
    }

    # (4) 仍然找不到：交互式让用户粘贴路径
    Write-Host ''
    Write-Host '[i] 未能自动找到 STM32CubeIDE 安装目录。' -ForegroundColor Yellow
    Write-Host '    请粘贴安装目录（其中应有 stm32cubeide.exe 和 stm32cubeide.ini），例如：' -ForegroundColor Yellow
    Write-Host '    C:\ST\STM32CubeIDE_1.19.0\STM32CubeIDE' -ForegroundColor Gray
    Write-Host '    （不知道路径的话：右键桌面 STM32CubeIDE 图标 → 打开文件所在位置，复制地址栏）' -ForegroundColor Gray
    for ($i = 0; $i -lt 3; $i++) {
        try { $in = Read-Host 'STM32CubeIDE 安装目录（直接回车则退出）' } catch { break }
        if ([string]::IsNullOrWhiteSpace($in)) { break }
        $in = $in.Trim().Trim('"')
        if (Test-IdERoot $in) { return (Resolve-Path -LiteralPath $in).Path }
        Write-Host '[×] 该目录下没有 stm32cubeide.exe / stm32cubeide.ini，请检查后重试。' -ForegroundColor Red
    }
    return $null
}
