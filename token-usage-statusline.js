// Port of token-usage-statusline.ps1; output must stay byte-identical to it.
const fs = require('fs');
const path = require('path');
const os = require('os');

const ESC = '\x1b';

// PowerShell [Math]::Round is half-even; Math.round is half-up.
function round(x) {
  const f = Math.floor(x), d = x - f;
  if (d < 0.5) return f;
  if (d > 0.5) return f + 1;
  return f % 2 === 0 ? f : f + 1;
}
const clamp = (x) => Math.min(100, Math.max(0, round(x)));
// PowerShell [double]$null is 0; a non-numeric value throws there, and nothing is printed.
const dbl = (v) => {
  const n = v == null ? 0 : Number(v);
  if (Number.isNaN(n)) throw new Error('not a number');
  return n;
};

let Data = null;
try { Data = JSON.parse(fs.readFileSync(0, 'utf8')); } catch {}
const truthy = (v) => v != null && v !== false && v !== 0 && v !== '' && !(Array.isArray(v) && v.length === 0);

// -- CAV: verde = ativo, laranja = desativado, vermelho = nao instalado --
const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
let installed = false;
try {
  installed = /"caveman@/i.test(fs.readFileSync(path.join(claudeDir, 'plugins', 'installed_plugins.json'), 'utf8'));
} catch {}
let cavOn = false;
try {
  const flag = path.join(claudeDir, '.caveman-active');
  const st = fs.lstatSync(flag);
  if (!st.isSymbolicLink() && (st.isDirectory() || st.size <= 64)) {
    const txt = fs.readFileSync(flag, 'utf8').replace(/^\uFEFF/, '');
    // an empty flag file counts as off in the .ps1 (Get-Content yields nothing)
    cavOn = txt !== '' && txt.split(/\r\n|\r|\n/)[0].trim().toLowerCase() !== 'off';
  }
} catch {}
const cColor = !installed ? '38;5;203' : cavOn ? '38;5;114' : '38;5;208';

function bar(pct, warn, crit, warnColor) {
  if (pct == null) return `${ESC}[2m[----------] --%${ESC}[0m`;
  const p = clamp(dbl(pct));
  const filled = round(p / 10);
  let color = '38;5;114';
  if (p >= crit) color = '38;5;203';
  else if (p >= warn) color = warnColor;
  return `[${ESC}[${color}m` + '#'.repeat(filled) + `${ESC}[${color}m` + '-'.repeat(10 - filled) + `${ESC}[0m] ${ESC}[${color}m${p}%${ESC}[0m`;
}

function limBar(five, week) {
  if (five == null && week == null) return `${ESC}[2m[----------] --% --%${ESC}[0m`;
  const f = clamp(dbl(five)), w = clamp(dbl(week));
  const fn = round(f / 10), wn = Math.max(fn, round(w / 10));
  let fc = '38;5;114';
  if (f >= 90) fc = '38;5;203'; else if (f >= 75) fc = '38;5;220';
  const blue = '38;5;75';
  return `[${ESC}[${fc}m` + '#'.repeat(fn) + `${ESC}[${blue}m` + '#'.repeat(wn - fn) + `${ESC}[${fc}m` + '-'.repeat(10 - wn) + `${ESC}[0m] ${ESC}[${fc}m${f}%${ESC}[0m ${ESC}[${blue}m${w}%${ESC}[0m`;
}

const D = truthy(Data) ? Data : null;
const ctx = D && truthy(D.context_window) ? D.context_window.used_percentage : null;
const rl = D && truthy(D.rate_limits) ? D.rate_limits : null;
const five = rl && truthy(rl.five_hour) ? rl.five_hour.used_percentage : null;
const week = rl && truthy(rl.seven_day) ? rl.seven_day.used_percentage : null;

const sep = ` ${ESC}[2m|${ESC}[0m `;
try {
  process.stdout.write(`${ESC}[${cColor}mCAV${ESC}[0m` + sep + 'CONT ' + bar(ctx, 50, 75, '38;5;220') + sep + 'LIM ' + limBar(five, week));
} catch {}
