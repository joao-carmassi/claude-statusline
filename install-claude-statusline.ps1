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

$Input_Json = [Console]::In.ReadToEnd()
$Data = $null
try { $Data = $Input_Json | ConvertFrom-Json -ErrorAction Stop } catch {}

$TranscriptPath = if ($Data) { $Data.transcript_path } else { $null }
$ModelId = if ($Data -and $Data.model) { $Data.model.id } else { $null }
$ModelName = if ($Data -and $Data.model) { $Data.model.display_name } else { $null }
$CostUsd = if ($Data -and $Data.cost) { $Data.cost.total_cost_usd } else { $null }

$Esc = [char]27

# -- Caveman badge ------------------------------------------------------------
$CavemanBadge = ""
try {
    $ClaudeDirInner = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
    $Flag = Join-Path $ClaudeDirInner ".caveman-active"
    $Item = Get-Item -LiteralPath $Flag -Force -ErrorAction Stop
    if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $Item.Length -le 64) {
        $Raw = Get-Content -LiteralPath $Flag -TotalCount 1 -ErrorAction Stop
        $Mode = if ($null -ne $Raw) { ([string]$Raw).Trim().ToLowerInvariant() } else { "" }
        $Mode = ($Mode -replace '[^a-z0-9-]', '')
        $Valid = @('off','lite','full','ultra','wenyan-lite','wenyan','wenyan-full','wenyan-ultra','commit','review','compress')
        if ($Valid -contains $Mode) {
            if ([string]::IsNullOrEmpty($Mode) -or $Mode -eq "full") {
                $CavemanBadge = "${Esc}[38;5;172m[CAVEMAN]${Esc}[0m"
            } else {
                $CavemanBadge = "${Esc}[38;5;172m[CAVEMAN:$($Mode.ToUpperInvariant())]${Esc}[0m"
            }
        }
    }
} catch {}

# -- Token usage ---------------------------------------------------------------
function Get-ContextWindow($modelId) {
    if ($env:TOKEN_STATUSLINE_CONTEXT_WINDOW) {
        return [int]$env:TOKEN_STATUSLINE_CONTEXT_WINDOW
    }
    if ($modelId -match '1m') { return 1000000 }
    return 200000
}

function Format-Tokens($n) {
    if ($n -ge 1000000) { return "{0:N1}M" -f ($n / 1000000) }
    if ($n -ge 1000) { return "{0:N1}k" -f ($n / 1000) }
    return "$n"
}

$Bar = ""
if ($TranscriptPath -and (Test-Path -LiteralPath $TranscriptPath)) {
    try {
        $Lines = Get-Content -LiteralPath $TranscriptPath -Tail 200 -ErrorAction Stop
        $Usage = $null
        $LastModel = $null
        for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
            $line = $Lines[$i]
            if (-not $line -or $line.Trim().Length -eq 0) { continue }
            try { $entry = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($entry.type -eq 'system' -and $entry.subtype -eq 'compact_boundary' -and $entry.compactMetadata) {
                $Usage = [PSCustomObject]@{
                    input_tokens                = $entry.compactMetadata.postTokens
                    cache_creation_input_tokens = 0
                    cache_read_input_tokens     = 0
                }
                break
            }
            if ($entry.type -eq 'assistant' -and $entry.message -and $entry.message.usage) {
                $Usage = $entry.message.usage
                if ($entry.message.model) { $LastModel = $entry.message.model }
                break
            }
        }
        if ($Usage) {
            $ContextTokens = [int64]($Usage.input_tokens) + [int64]($Usage.cache_creation_input_tokens) + [int64]($Usage.cache_read_input_tokens)
            $EffectiveModel = if ($ModelId) { $ModelId } else { $LastModel }
            $Limit = Get-ContextWindow $EffectiveModel
            $Pct = [Math]::Min(100, [Math]::Round(($ContextTokens / $Limit) * 100))

            $Segments = 20
            $Filled = [Math]::Round(($Pct / 100) * $Segments)
            if ($Filled -gt $Segments) { $Filled = $Segments }
            $EmptyCount = $Segments - $Filled

            $Color = "38;5;114" # green: 0-49%
            if ($Pct -ge 60) { $Color = "38;5;203" } # red: 60%+
            elseif ($Pct -ge 50) { $Color = "38;5;208" } # orange: 50-59%

            $FilledChars = "${Esc}[${Color}m" + ('#' * $Filled)
            $EmptyChars = "${Esc}[2m" + ('-' * $EmptyCount) + "${Esc}[0m"
            $Bar = "[${FilledChars}${EmptyChars}] ${Esc}[${Color}m${Pct}%${Esc}[0m (${Esc}[2m$(Format-Tokens $ContextTokens)/$(Format-Tokens $Limit)${Esc}[0m)"
        }
    } catch {}
}

$Parts = @()
if ($CavemanBadge) { $Parts += $CavemanBadge }
if ($Bar) { $Parts += $Bar }
if ($ModelName) { $Parts += "${Esc}[2m$ModelName${Esc}[0m" }

[Console]::Write(($Parts -join " "))
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
