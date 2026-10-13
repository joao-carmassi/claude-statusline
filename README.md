# claude-statusline

Status line colorida para o [Claude Code](https://claude.com/claude-code), escrita em Node.js.

```
CAV | CONT [######----] 55% | LIM [########--] 80% 30%
```

| Trecho | O que mostra |
|---|---|
| `CAV` | Estado do plugin caveman: verde = ativo, laranja = desativado, vermelho = não instalado |
| `CONT` | Uso da janela de contexto |
| `LIM` | Limite de 5 horas (barra e primeiro `%`) e limite semanal (trecho azul e segundo `%`) |

## Instalação

Requer **Node.js** no `PATH` e Windows PowerShell 5.1 ou PowerShell 7+.

```powershell
powershell -ExecutionPolicy Bypass -File install-claude-statusline.ps1
```

O instalador:

1. usa `$env:CLAUDE_CONFIG_DIR` (ou `~/.claude`) como pasta de configuração;
2. escreve `hooks/token-usage-statusline.js` nessa pasta;
3. mescla a chave `statusLine` no `settings.json`, sem apagar o resto, e guarda um `settings.json.bak`.

Depois abra um novo Claude Code. A configuração gravada é:

```json
"statusLine": {
  "type": "command",
  "command": "node \"<pasta>\\hooks\\token-usage-statusline.js\"",
  "refreshInterval": 5
}
```

Para usar o mesmo script em duas contas (por exemplo `~/.claude` e `~/.claude-qf`), aponte o `command` das duas para o mesmo `.js`. O script lê `CLAUDE_CONFIG_DIR` para saber qual conta está rodando.

## Cores

As barras têm `#` preenchidos e `-` vazios, e **os dois usam a mesma cor** da barra. Cada um dos 10 blocos vale 10%.

| Barra | Verde | Amarelo | Vermelho |
|---|---|---|---|
| `CONT` | abaixo de 50% | 50% a 74% | 75% ou mais |
| `LIM` (5h) | abaixo de 75% | 75% a 89% | 90% ou mais |

No `LIM`, o trecho do limite semanal fica **sempre azul**, qualquer que seja a cor do limite de 5h. Ele é desenhado depois dos blocos de 5h, até o ponto que o uso semanal alcança.

Sem dados (campo ausente), a barra aparece apagada: `[----------] --%`.

## Como funciona

O Claude Code executa o `command` a cada 5 segundos (`refreshInterval`) e envia um JSON pelo stdin. O script usa estes campos:

- `context_window.used_percentage`
- `rate_limits.five_hour.used_percentage`
- `rate_limits.seven_day.used_percentage`

e imprime uma linha com códigos de cor ANSI, sem quebra de linha no final. Se o JSON for inválido ou faltar campo, imprime as barras apagadas.

O arredondamento é *half-even* (45 → 4, 25 → 2), igual ao `[Math]::Round` do PowerShell, para manter a saída idêntica à versão em PowerShell.

## Por que Node

A versão em PowerShell (`token-usage-statusline.ps1`, mantida como referência) sobe um processo `powershell` novo a cada atualização. Medido no Windows 11, 30 execuções cada, com `refreshInterval` de 5 s:

| Versão | Tempo médio | CPU por execução | CPU por hora |
|---|---|---|---|
| PowerShell 5.1 (comando original) | 458 ms | 435 ms | 314 s |
| PowerShell 5.1 com `-NoProfile -NoLogo` | 238 ms | 263 ms | 189 s |
| **Node** | **52 ms** | **36 ms** | **26 s** |

Com 6 execuções em paralelo, o Node leva 124 ms contra 687 ms do comando original em PowerShell.

A saída do `.js` foi comparada byte a byte com a do `.ps1` em 49 casos: entrada vazia, `{}`, JSON inválido, valores nos limites de arredondamento e fora da faixa, campos faltando ou nulos, e vários estados do arquivo `.caveman-active`. A única diferença conhecida é texto não numérico em `used_percentage` (`"abc"`), que o Claude Code não envia.

## Arquivos

| Arquivo | Função |
|---|---|
| `token-usage-statusline.js` | A status line (usada pelo instalador) |
| `token-usage-statusline.ps1` | Versão em PowerShell (mesma saída), só como referência |
| `install-claude-statusline.ps1` | Instalador. Embute o conteúdo do `.js`: ao editar o `.js`, atualize também o bloco `$StatuslineContent` |

## Desfazer

Restaure o `settings.json.bak` ou volte o `command` para a versão em PowerShell:

```json
"command": "powershell -ExecutionPolicy Bypass -File \"<pasta>\\hooks\\token-usage-statusline.ps1\""
```
