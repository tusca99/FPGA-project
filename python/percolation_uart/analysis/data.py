"""Data loading: SQLite connection, session listing, row loading."""

from __future__ import annotations

import json
import sqlite3
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from ..protocol import REQUEST_BYTES, RESPONSE_BYTES


# FPGA timing constants (from VHDL analysis)
RNG_WARMUP_CYCLES = 1573        # AES seeding (1536) + Trivium warmup (37) @ 100 MHz
RNG_WARMUP_S = RNG_WARMUP_CYCLES / 100e6
# End-to-end frontier cost per row. The frontier's own pipeline is 3 cycles/row
# (RUN_READY -> RUN_COMPUTE -> RUN_SAVE), but the core's registered row-send
# handshake (ChunkValid/ChunkOpen are registered, Busy is combinatorial) adds
# one extra cycle per row, so the measured end-to-end cost is 4 cycles/row.
# Verified against hardware: fit of core_latency_per_run_cycles_est vs steps
# gives slope ~3.99 cyc/step (see plot_pipeline_efficiency).
FRONTIER_CYCLES_PER_STEP = 4    # 3-stage prefix scan + 1 registered-send handshake
UART_WIRE_S_CALC = (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / 115200.0  # ≈ 2.78 ms

DEFAULT_DB = Path(__file__).resolve().parents[2] / "output" / "benchmark.sqlite3"
DEFAULT_DB2 = Path(__file__).resolve().parents[2] / "output" / "benchmark-2.sqlite3"

# --- Plot style ---
_PLOT_STYLE = {
    "figure.facecolor": "white",
    "axes.facecolor": "#f8f9fa",
    "axes.grid": True,
    "grid.alpha": 0.25,
    "grid.linestyle": "--",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 12,
    "legend.fontsize": 10,
    "figure.dpi": 150,
}


@dataclass(frozen=True)
class BenchmarkSession:
    session_id: str
    created_at: str
    payload: dict[str, object]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def list_sessions(conn: sqlite3.Connection) -> list[BenchmarkSession]:
    rows = conn.execute(
        "SELECT session_id, created_at, payload_json FROM benchmark_sessions ORDER BY created_at"
    ).fetchall()
    sessions: list[BenchmarkSession] = []
    for row in rows:
        sessions.append(
            BenchmarkSession(
                session_id=str(row["session_id"]),
                created_at=str(row["created_at"]),
                payload=json.loads(row["payload_json"]),
            )
        )
    return sessions


def latest_session_id(conn: sqlite3.Connection) -> str | None:
    row = conn.execute(
        "SELECT session_id FROM benchmark_sessions ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    return None if row is None else str(row["session_id"])


def load_summary_rows(conn: sqlite3.Connection, session_id: str | None = None) -> list[dict[str, object]]:
    if session_id is None:
        rows = conn.execute("SELECT row_json FROM benchmark_summary ORDER BY p").fetchall()
    else:
        rows = conn.execute(
            "SELECT row_json FROM benchmark_summary WHERE session_id = ? ORDER BY p",
            (session_id,),
        ).fetchall()
    return [json.loads(row["row_json"]) for row in rows]


def load_raw_rows(conn: sqlite3.Connection, session_id: str | None = None) -> list[dict[str, object]]:
    if session_id is None:
        rows = conn.execute("SELECT row_json FROM benchmark_raw ORDER BY p, repeat_index").fetchall()
    else:
        rows = conn.execute(
            "SELECT row_json FROM benchmark_raw WHERE session_id = ? ORDER BY p, repeat_index",
            (session_id,),
        ).fetchall()
    return [json.loads(row["row_json"]) for row in rows]


def summarize_db(conn: sqlite3.Connection) -> str:
    session_count = conn.execute("SELECT COUNT(*) AS n FROM benchmark_sessions").fetchone()["n"]
    summary_count = conn.execute("SELECT COUNT(*) AS n FROM benchmark_summary").fetchone()["n"]
    raw_count = conn.execute("SELECT COUNT(*) AS n FROM benchmark_raw").fetchone()["n"]

    if summary_count == 0:
        return f"sessions={session_count}, summary_rows=0, raw_rows={raw_count}"

    p_min, p_max = conn.execute(
        "SELECT MIN(p) AS p_min, MAX(p) AS p_max FROM benchmark_summary"
    ).fetchone()
    return (
        f"sessions={session_count}, summary_rows={summary_count}, raw_rows={raw_count}, "
        f"p_range=[{p_min:.4f}, {p_max:.4f}]"
    )


def _find_sessions_by_params(conn: sqlite3.Connection, *, hw_width: int) -> list[dict]:
    """Return all session metadata matching the given effective HW width."""
    cur = conn.execute(
        "SELECT session_id, created_at, payload_json FROM benchmark_sessions ORDER BY created_at"
    )
    matches: list[dict] = []
    for row in cur.fetchall():
        payload = json.loads(row["payload_json"])
        if payload.get("effective_hw_width") == hw_width:
            matches.append(
                {
                    "session_id": str(row["session_id"]),
                    "created_at": str(row["created_at"]),
                    "runs": payload.get("runs", 0),
                    "steps": payload.get("steps", 0),
                    "points": payload.get("points", 0),
                    "repeats": payload.get("repeats", 1),
                }
            )
    return matches


def _session_data(conn: sqlite3.Connection, session_id: str) -> list[dict[str, object]]:
    return load_raw_rows(conn, session_id=session_id)


def _closest_row(rows: list[dict[str, object]], target_p: float) -> dict[str, object]:
    return min(rows, key=lambda r: abs(float(r.get("p", 0.0)) - target_p))


def _find_square_sessions(
    conn: sqlite3.Connection, *, hw_width: int
) -> list[dict]:
    """Return sessions where steps == hw_width (square grids) for physics plots.

    DP finite-size scaling requires square L×L grids.  Falls back to the
    session with the largest total runs if none are perfectly square.
    """
    cur = conn.execute(
        "SELECT session_id, created_at, payload_json FROM benchmark_sessions ORDER BY created_at"
    )
    matches: list[dict] = []
    for row in cur.fetchall():
        payload = json.loads(row["payload_json"])
        if payload.get("effective_hw_width") != hw_width:
            continue
        steps = payload.get("steps", 0)
        if steps != hw_width:
            continue
        matches.append(
            {
                "session_id": str(row["session_id"]),
                "created_at": str(row["created_at"]),
                "runs": payload.get("runs", 0),
                "steps": steps,
                "points": payload.get("points", 0),
                "repeats": payload.get("repeats", 1),
                "total_runs": payload.get("runs", 0) * payload.get("repeats", 1),
            }
        )
    return matches
