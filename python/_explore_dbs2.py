"""Quick script to explore benchmark databases."""
import sqlite3
import json
import sys

for db_name in ['benchmark.sqlite3', 'benchmark-2.sqlite3']:
    path = f'python/output/{db_name}'
    conn = sqlite3.connect(path)
    print(f'=== {db_name} ===')
    sessions = conn.execute('SELECT session_id, created_at, payload_json FROM benchmark_sessions ORDER BY created_at').fetchall()
    print(f'Sessions: {len(sessions)}')
    for sid, created, payload in sessions:
        p = json.loads(payload)
        print(f'  id={sid[:12]} created={created}')
        print(f'    runs={p.get("runs")} steps={p.get("steps")} hw_width={p.get("hw_width")} width={p.get("width")}')
        print(f'    points={p.get("points")} repeats={p.get("repeats")} pmin={p.get("pmin")} pmax={p.get("pmax")}')
        print(f'    sw_only={p.get("software_only")} hw_only={p.get("hardware_only")}')
        sc = conn.execute('SELECT COUNT(*) FROM benchmark_summary WHERE session_id=?', (sid,)).fetchone()[0]
        rc = conn.execute('SELECT COUNT(*) FROM benchmark_raw WHERE session_id=?', (sid,)).fetchone()[0]
        print(f'    summary={sc} raw={rc}')
        pvals = conn.execute('SELECT DISTINCT p FROM benchmark_summary WHERE session_id=? ORDER BY p', (sid,)).fetchall()
        print(f'    p={[round(pv[0],4) for pv in pvals]}')
        modes = conn.execute('SELECT DISTINCT mode FROM benchmark_raw WHERE session_id=?', (sid,)).fetchall()
        print(f'    modes={[m[0] for m in modes]}')
        sys.stdout.flush()
    conn.close()
    print()
