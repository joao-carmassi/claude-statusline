[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Data = $null
try { $Data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop } catch {}

$Esc = [char]27

# -- Caveman: CAV verde = ativo, laranja = desativado, vermelho = nao instalado --
$ClaudeDirInner = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$CavemanInstalled = $false
try {
    $Plugins = Get-Content -LiteralPath (Join-Path $ClaudeDirInner "plugins\installed_plugins.json") -Raw -ErrorAction Stop
    $CavemanInstalled = $Plugins -match '"caveman@'
} catch {}
$CavemanOn = $false
try {
    $Flag = Join-Path $ClaudeDirInner ".caveman-active"
    $Item = Get-Item -LiteralPath $Flag -Force -ErrorAction Stop
    if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $Item.Length -le 64) {
        $Mode = ([string](Get-Content -LiteralPath $Flag -TotalCount 1 -ErrorAction Stop)).Trim().ToLowerInvariant()
        $CavemanOn = $Mode -ne 'off'
    }
} catch {}
$CColor = if (-not $CavemanInstalled) { "38;5;203" } elseif ($CavemanOn) { "38;5;114" } else { "38;5;208" }

# -- Barra [####------] NN% ----------------------------------------------------
function Format-Bar($pct, $warn = 50, $crit = 60, $warnColor = "38;5;208") {
    if ($null -eq $pct) { return "${Esc}[2m[----------] --%${Esc}[0m" }
    $Pct = [Math]::Min(100, [Math]::Max(0, [Math]::Round([double]$pct)))
    $Filled = [Math]::Round($Pct / 10)
    $Color = "38;5;114"                                   # verde
    if ($Pct -ge $crit) { $Color = "38;5;203" }           # vermelho
    elseif ($Pct -ge $warn) { $Color = $warnColor }       # laranja/amarelo
    return "[${Esc}[${Color}m" + ('#' * $Filled) + "${Esc}[${Color}m" + ('-' * (10 - $Filled)) + "${Esc}[0m] ${Esc}[${Color}m${Pct}%${Esc}[0m"
}

$CtxPct = if ($Data -and $Data.context_window) { $Data.context_window.used_percentage } else { $null }
$FivePct = if ($Data -and $Data.rate_limits -and $Data.rate_limits.five_hour) { $Data.rate_limits.five_hour.used_percentage } else { $null }

$WeekPct = if ($Data -and $Data.rate_limits -and $Data.rate_limits.seven_day) { $Data.rate_limits.seven_day.used_percentage } else { $null }

# -- Barra LIM: 5h (cor por limiar) + semanal (azul) na mesma barra --
function Format-LimBar($five, $week) {
    if ($null -eq $five -and $null -eq $week) { return "${Esc}[2m[----------] --% --%${Esc}[0m" }
    $F = [Math]::Min(100, [Math]::Max(0, [Math]::Round([double]$five)))
    $W = [Math]::Min(100, [Math]::Max(0, [Math]::Round([double]$week)))
    $FN = [Math]::Round($F / 10); $WN = [Math]::Max($FN, [Math]::Round($W / 10))
    $FC = "38;5;114"; if ($F -ge 90) { $FC = "38;5;203" } elseif ($F -ge 75) { $FC = "38;5;220" }
    $Blue = "38;5;75"
    return "[${Esc}[${FC}m" + ('#' * $FN) + "${Esc}[${Blue}m" + ('#' * ($WN - $FN)) + "${Esc}[${FC}m" + ('-' * (10 - $WN)) + "${Esc}[0m] ${Esc}[${FC}m${F}%${Esc}[0m ${Esc}[${Blue}m${W}%${Esc}[0m"
}

$Sep = " ${Esc}[2m|${Esc}[0m "
[Console]::Write("${Esc}[${CColor}mCAV${Esc}[0m" + $Sep + "CONT " + (Format-Bar $CtxPct 50 75 "38;5;220") + $Sep + "LIM " + (Format-LimBar $FivePct $WeekPct))
