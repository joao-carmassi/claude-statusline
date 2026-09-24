# install-claude-statusline.ps1
# Instala/atualiza statusline de uso de token (barra colorida) em qualquer Claude Code novo.
# Uso: powershell -ExecutionPolicy Bypass -File install-claude-statusline.ps1
#
# Para Claude/agente executando isto: apenas rode o comando acima num terminal
# PowerShell. Script detecta $env:CLAUDE_CONFIG_DIR automaticamente (ou usa
# ~/.claude), escreve hooks\token-usage-statusline.ps1 e mescla a chave
# statusLine em settings.json sem apagar o resto do arquivo. Compativel com
# Windows PowerShell 5.1 e PowerShell 7+. Depois de rodar, abrir novo Claude
# Code para ver a statusline.

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$HooksDir = Join-Path $ClaudeDir "hooks"
$ScriptPath = Join-Path $HooksDir "token-usage-statusline.ps1"
$SettingsPath = Join-Path $ClaudeDir "settings.json"

if (-not (Test-Path $ClaudeDir)) { New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null }
if (-not (Test-Path $HooksDir)) { New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null }

$StatuslineContent = @'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Data = $null
try { $Data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop } catch {}

$Esc = [char]27

# -- Caveman: CAV verde = ativo, vermelho = inativo ------------------------------
$CavemanOn = $false
try {
    $ClaudeDirInner = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
    $Flag = Join-Path $ClaudeDirInner ".caveman-active"
    $Item = Get-Item -LiteralPath $Flag -Force -ErrorAction Stop
    if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $Item.Length -le 64) {
        $Mode = ([string](Get-Content -LiteralPath $Flag -TotalCount 1 -ErrorAction Stop)).Trim().ToLowerInvariant()
        $CavemanOn = $Mode -ne 'off'
    }
} catch {}
$CColor = if ($CavemanOn) { "38;5;114" } else { "38;5;203" }

# -- Barra [####------] NN% ----------------------------------------------------
function Format-Bar($pct, $warn = 50, $crit = 60, $warnColor = "38;5;208") {
    if ($null -eq $pct) { return "${Esc}[2m[----------] --%${Esc}[0m" }
    $Pct = [Math]::Min(100, [Math]::Max(0, [Math]::Round([double]$pct)))
    $Filled = [Math]::Round($Pct / 10)
    $Color = "38;5;114"                                   # verde
    if ($Pct -ge $crit) { $Color = "38;5;203" }           # vermelho
    elseif ($Pct -ge $warn) { $Color = $warnColor }       # laranja/amarelo
    return "[${Esc}[${Color}m" + ('#' * $Filled) + "${Esc}[2m" + ('-' * (10 - $Filled)) + "${Esc}[0m] ${Esc}[${Color}m${Pct}%${Esc}[0m"
}

$CtxPct = if ($Data -and $Data.context_window) { $Data.context_window.used_percentage } else { $null }
$FivePct = if ($Data -and $Data.rate_limits -and $Data.rate_limits.five_hour) { $Data.rate_limits.five_hour.used_percentage } else { $null }

$Sep = " ${Esc}[2m|${Esc}[0m "
[Console]::Write("${Esc}[${CColor}mCAV${Esc}[0m" + $Sep + "CONT " + (Format-Bar $CtxPct) + $Sep + "LIM " + (Format-Bar $FivePct 75 90 "38;5;220"))
'@

Set-Content -LiteralPath $ScriptPath -Value $StatuslineContent -Encoding UTF8
Write-Host "Statusline script escrito em: $ScriptPath"

# -- Merge statusLine config em settings.json sem apagar o resto --------------
$StatusLineConfig = [ordered]@{
    type            = "command"
    command         = "powershell -ExecutionPolicy Bypass -File `"$ScriptPath`""
    refreshInterval = 5
}

if (Test-Path $SettingsPath) {
    $Raw = Get-Content -LiteralPath $SettingsPath -Raw
    $Settings = $null
    try { $Settings = $Raw | ConvertFrom-Json -ErrorAction Stop } catch { $Settings = $null }
    if ($null -eq $Settings) {
        Write-Host "AVISO: settings.json existente nao pode ser lido (JSON invalido). Nada foi alterado."
        Write-Host "Adicione manualmente este bloco em settings.json:"
        Write-Host ($StatusLineConfig | ConvertTo-Json)
        exit 1
    }
    # backup antes de mexer
    Copy-Item -LiteralPath $SettingsPath -Destination "$SettingsPath.bak" -Force

    $StatusLineObj = [PSCustomObject]@{
        type            = "command"
        command         = "powershell -ExecutionPolicy Bypass -File `"$ScriptPath`""
        refreshInterval = 5
    }
    if ($Settings.PSObject.Properties.Name -contains "statusLine") {
        $Settings.statusLine = $StatusLineObj
    } else {
        $Settings | Add-Member -MemberType NoteProperty -Name "statusLine" -Value $StatusLineObj -Force
    }
    ($Settings | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    Write-Host "settings.json atualizado (backup em settings.json.bak)."
} else {
    $NewSettings = @{
        statusLine = @{
            type            = "command"
            command         = "powershell -ExecutionPolicy Bypass -File `"$ScriptPath`""
            refreshInterval = 5
        }
    }
    ($NewSettings | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    Write-Host "settings.json criado com statusLine."
}

Write-Host "Pronto. Abra novo Claude Code para ver a statusline."
