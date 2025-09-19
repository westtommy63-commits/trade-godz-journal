# Zorian — Orchestrate Journal Logger

Local-first, CPU-friendly logging of the most recent **orchestrate** run into `C:\Zorian\journal\` as timestamped Markdown. No overwrites; safe, atomic writes.

This repository snapshot packages the PowerShell helper, Python integration helpers, and CLI/API wiring notes you shared so that your agent can read everything from a single document.

---

## 1. PowerShell Helper

The PowerShell entry point lives at [`scripts/journal_log_orchestrate.ps1`](../scripts/journal_log_orchestrate.ps1). Copy it to `C:\Zorian\scripts\journal_log_orchestrate.ps1` (or run inline) and execute with:

```powershell
pwsh -File C:\Zorian\scripts\journal_log_orchestrate.ps1
```

It will:

1. Locate the latest orchestrate report JSON under `C:\Zorian\reports\orchestrate` (prefer today’s run when available).
2. Parse the JSON with defensive fallbacks for missing fields.
3. Build Markdown with JSON front matter describing the run.
4. Write the entry atomically into `C:\Zorian\journal\TIMESTAMP_orchestrate_RUNID.md`.

### Expected Output Example

`C:\Zorian\journal\2025-09-18_153422_orchestrate_abc123.md`

---

## 2. Python Module: `zorian/journal.py`

```python
from __future__ import annotations
import os, io, json, time, tempfile
from datetime import datetime, timezone
from pathlib import Path

JOURNAL_DIR = Path(r"C:\Zorian\journal")
JOURNAL_DIR.mkdir(parents=True, exist_ok=True)

ISO = "%Y-%m-%d_%H%M%S"

def _ts() -> str:
    return datetime.now().strftime(ISO)

def _utc_iso(dt: datetime | None = None) -> str:
    dt = dt or datetime.now(timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()

def write_entry(prefix: str, run_id: str, meta: dict, body: dict | None = None, extra_md: str = "") -> Path:
    JOURNAL_DIR.mkdir(parents=True, exist_ok=True)
    safe_run = (run_id or "noid").replace("/", "-").replace("\\", "-")
    name = f"{_ts()}_{prefix}_{safe_run}.md"
    dest = JOURNAL_DIR / name

    fm = {**meta}
    fm.setdefault("timestamp", _utc_iso())
    fm.setdefault("run_id", run_id)

    def to_json(d: dict) -> str:
        return json.dumps(d, ensure_ascii=False, indent=2)

    body = body or {}

    lines = []
    lines.append("---")
    lines.append(to_json(fm))
    lines.append("---\n")
    lines.append(f"# {prefix.capitalize()} Run — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    if body.get("headline"):
        lines.append(f"**{body['headline']}**\n")

    def sec(title: str, key: str, default: str = "- "):
        lines.append(f"## {title}")
        lines.append(str(body.get(key) or default))
        lines.append("")

    sec("Summary", "summary", "(auto) Logged into Trade God's Journal.")
    sec("Observations", "observations")
    sec("Decisions", "decisions")
    sec("What to Review Next", "review_next", "- Validate parameter sensitivity and slippage assumptions.")

    if extra_md:
        lines.append(extra_md)

    text = "\n".join(lines).rstrip() + "\n"

    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8", dir=str(JOURNAL_DIR)) as tmp:
        tmp.write(text)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, dest)
    return dest


def write_orchestrate_from_report(report_path: Path | str) -> Path:
    p = Path(report_path)
    data = json.loads(Path(p).read_text(encoding="utf-8"))
    run_id = str(data.get("run_id") or p.stem)

    assets = data.get("assets") or data.get("asset") or []
    if isinstance(assets, (str, int)):
        assets = [assets]

    win_rate = data.get("win_rate") or data.get("winRate")
    pnl_usd  = data.get("pnl_usd") or data.get("pnlUSD")
    trades   = data.get("trades")
    min_win  = data.get("min_win") or data.get("minWin")

    meta = {
        "report_path": str(p.resolve()),
        "started_at": data.get("started_at"),
        "finished_at": data.get("finished_at"),
        "assets": assets,
        "win_rate": win_rate,
        "pnl_usd": pnl_usd,
        "trades": trades,
        "min_win": min_win,
        "parameters": data.get("parameters") or data.get("params") or {},
    }

    body = {
        "summary": data.get("summary"),
        "observations": data.get("observations"),
        "decisions": data.get("decisions"),
        "review_next": data.get("review_next"),
    }

    lines = []
    lines.append("## Metrics")
    if assets:
        lines.append(f"Assets: **{', '.join(map(str, assets))}**  ")
    if win_rate is not None:
        try:
            pct = round(float(win_rate) * 100, 2)
            lines.append(f"Win-Rate: **{pct}%**  ")
        except Exception:
            lines.append(f"Win-Rate: **{win_rate}**  ")
    if pnl_usd is not None:
        lines.append(f"PnL (USD): **{pnl_usd}**  ")
    if trades is not None:
        lines.append(f"Trades: **{trades}**  ")
    if min_win is not None:
        lines.append(f"Min-Win Filter: **{min_win}**  ")

    extra_md = "\n".join(lines)
    return write_entry("orchestrate", run_id, meta, body, extra_md)


def write_orchestrate_latest(report_root: Path | str = r"C:\Zorian\reports\orchestrate") -> Path:
    root = Path(report_root)
    candidates = sorted(root.rglob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise FileNotFoundError(f"No orchestrate reports found under {root}")
    today = datetime.now().date()
    todays = [p for p in candidates if datetime.fromtimestamp(p.stat().st_mtime).date() == today]
    pick = todays[0] if todays else candidates[0]
    return write_orchestrate_from_report(pick)
```

---

## 3. Orchestrator Wiring

Inside your orchestrator’s `run()` function, capture the result dictionary and optionally write a journal entry when `--journal` is requested:

```python
from pathlib import Path
from zorian.journal import write_entry

# ... after producing the `result` dict ...
if args.journal:
    meta = {k: result.get(k) for k in ("started_at","finished_at","assets","win_rate","pnl_usd","trades","min_win","parameters")}
    body = {k: result.get(k) for k in ("summary","observations","decisions","review_next")}
    write_entry("orchestrate", result.get("run_id") or "orchestrate", meta, body)
```

---

## 4. CLI + API Hooks

### CLI Command Examples

```python
from zorian.journal import write_orchestrate_latest

# ... argparse wiring ...
if args.cmd == "journal" and args.which == "orchestrate":
    if args.from_path:
        path = write_orchestrate_from_report(args.from_path)
    else:
        path = write_orchestrate_latest()
    print(f"Journal entry created: {path}")
    raise SystemExit(0)
```

### FastAPI Endpoint

```python
from fastapi import FastAPI, HTTPException
from zorian.journal import write_orchestrate_latest, write_orchestrate_from_report

app = FastAPI()

@app.post("/journal/orchestrate")
async def journal_orchestrate(report_path: str | None = None):
    try:
        if report_path:
            p = write_orchestrate_from_report(report_path)
        else:
            p = write_orchestrate_latest()
        return {"status": "ok", "path": str(p)}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
```

---

## 5. Quick Usage Matrix

| Scenario | Command |
| --- | --- |
| One-off (today’s report) | `pwsh -File C:\Zorian\scripts\journal_log_orchestrate.ps1` |
| CLI helper | `python C:\Zorian\cli.py journal orchestrate` |
| During orchestrate run | `python C:\Zorian\cli.py orchestrate --journal ...` |
| REST endpoint | `POST http://localhost:8000/journal/orchestrate` |

All entries land in `C:\Zorian\journal\` with timestamped filenames and JSON front matter for later querying.
