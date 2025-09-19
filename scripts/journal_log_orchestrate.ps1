$ErrorActionPreference = 'Stop'

$journalRoot = 'C:\Zorian\journal'
$reportRoot  = 'C:\Zorian\reports\orchestrate'
New-Item -ItemType Directory -Force -Path $journalRoot | Out-Null

$today = (Get-Date).Date
$reports = Get-ChildItem -Path $reportRoot -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if (-not $reports) { throw "No orchestrate reports found under $reportRoot" }

$todayReports = $reports | Where-Object { $_.LastWriteTime.Date -eq $today }
$pick = if ($todayReports) { $todayReports[0] } else { $reports[0] }

$raw = Get-Content -Raw -Path $pick.FullName
try { $j = $raw | ConvertFrom-Json } catch { throw "Invalid JSON in $($pick.FullName): $_" }

$runId      = if ($j.run_id) { "$( $j.run_id )" } else { [IO.Path]::GetFileNameWithoutExtension($pick.Name) }
$started    = if ($j.started_at) { Get-Date $j.started_at } else { $pick.CreationTime }
$finished   = if ($j.finished_at) { Get-Date $j.finished_at } else { $pick.LastWriteTime }
$assets     = if ($j.assets) { ($j.assets | ForEach-Object { "$_" }) -join ', ' } else { ($j.asset -join ', ') }
$winRate    = if ($j.win_rate) { [math]::Round([double]$j.win_rate * 100, 2) } elseif ($j.winRate) { [math]::Round([double]$j.winRate * 100, 2) } else { $null }
$pnlUsd     = if ($j.pnl_usd -ne $null) { '{0:N2}' -f [double]$j.pnl_usd } elseif ($j.pnlUSD -ne $null) { '{0:N2}' -f [double]$j.pnlUSD } else { $null }
$trades     = if ($j.trades) { [int]$j.trades } else { $null }
$minWin     = if ($j.min_win) { [double]$j.min_win } else { $j.minWin }
$notes      = if ($j.notes) { "$( $j.notes )" } else { '' }
$errors     = if ($j.errors) { ($j.errors | Out-String).Trim() } else { '' }
$parameters = if ($j.parameters) { $j.parameters } else { $j.params }

$ts = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$fname = "${ts}_orchestrate_${runId}.md" -replace '[^a-zA-Z0-9_\.-]','-'
$tmp   = Join-Path $journalRoot ("." + $fname)
$dest  = Join-Path $journalRoot $fname

$frontMatter = @{
  timestamp   = (Get-Date -AsUTC).ToString('o')
  run_id      = $runId
  report_path = $pick.FullName
  started_at  = $started.ToString('o')
  finished_at = $finished.ToString('o')
  assets      = $assets
  win_rate    = if ($winRate -ne $null) { "$winRate%" } else { '' }
  pnl_usd     = $pnlUsd
  trades      = if ($trades -ne $null) { "$trades" } else { '' }
  min_win     = if ($minWin -ne $null) { "$minWin" } else { '' }
} | ConvertTo-Json -Depth 6

$paramLines = @()
if ($parameters) {
    $parameters.PSObject.Properties | ForEach-Object {
        $paramLines += "| $($_.Name) | $($_.Value) |"
    }
}

$todayNote = if ($pick.LastWriteTime.Date -eq $today) { '' } else { "\n> Note: Latest available orchestrate report is from $($pick.LastWriteTime.ToString('yyyy-MM-dd'))." }

$md = @()
$md += '---'
$md += $frontMatter
$md += '---'
$md += "\n# Orchestrate Run — $($finished.ToString('yyyy-MM-dd HH:mm:ss'))"
$md += "Run ID: **$runId**  "
$md += "Assets: **$assets**  "
if ($winRate -ne $null) { $md += "Win-Rate: **$winRate%**  " }
if ($pnlUsd) { $md += "PnL (USD): **$pnlUsd**  " }
if ($trades -ne $null) { $md += "Trades: **$trades**  " }
if ($minWin -ne $null) { $md += "Min-Win Filter: **$minWin**  " }
$md += $todayNote
$md += "\n## Summary\n$(if($j.summary){$j.summary}else{'(auto) Logged latest orchestrate result into the Trade God's Journal.'})"
$md += "\n## Observations\n$(if($j.observations){$j.observations}else{'- })"
$md += "\n## Decisions\n$(if($j.decisions){$j.decisions}else{'- })"
$md += "\n## What to Review Next\n$(if($j.review_next){$j.review_next}else{'- Validate parameter sensitivity and slippage assumptions.'})"
if ($paramLines.Count -gt 0) {
  $md += "\n## Parameters\n| Name | Value |\n|---|---|\n" + ($paramLines -join "`n")
}
if ($errors) {
  $md += "\n## Errors\n````\n$errors\n````"
}
$mdText = $md -join "`n"

Set-Content -Path $tmp -Value $mdText -Encoding UTF8 -NoNewline
Move-Item -Path $tmp -Destination $dest -ErrorAction Stop
Write-Host "Journal entry created: $dest"
