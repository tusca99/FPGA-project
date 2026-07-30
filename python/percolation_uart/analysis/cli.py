"""CLI entry point for percolation benchmark analysis."""

from __future__ import annotations

import argparse
from pathlib import Path

from .data import (
    DEFAULT_DB,
    DEFAULT_DB2,
    _connect,
    list_sessions,
    latest_session_id,
    load_summary_rows,
    load_raw_rows,
    summarize_db,
)
from .plots import (
    plot_dashboard,
    plot_latency_decomposition,
    plot_front_density,
    plot_cluster_mass,
    plot_occupancy_bias,
    plot_core_latency,
    plot_spanning_probability,
    plot_fpga_all,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect percolation benchmark SQLite history")
    parser.add_argument("--db", type=str, default=str(DEFAULT_DB))
    parser.add_argument("--latest", action="store_true", help="Only inspect latest session")
    parser.add_argument("--plot", type=str, default="", help="Optional throughput plot output path")
    parser.add_argument("--plot-dir", type=str, default="", help="Optional output directory for starter plots")
    parser.add_argument(
        "--fpga-plot",
        type=str,
        default="",
        help="Output directory for FPGA engineering analysis plots (uses benchmark-2)",
    )
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        raise SystemExit(f"database not found: {db_path}")

    conn = _connect(db_path)
    try:
        print(summarize_db(conn))
        sessions = list_sessions(conn)
        if sessions:
            latest = sessions[-1]
            print(f"latest_session={latest.session_id}")
            print(f"latest_created_at={latest.created_at}")
            if "config_hash" in latest.payload:
                print(f"latest_config_hash={latest.payload['config_hash']}")

        session_id = latest_session_id(conn) if args.latest else None
        rows = load_summary_rows(conn, session_id=session_id)
        raw_rows = load_raw_rows(conn, session_id=session_id)
        print(f"loaded_summary_rows={len(rows)}")
        print(f"loaded_raw_rows={len(raw_rows)}")
        if rows:
            print(f"p_min={min(float(row['p']) for row in rows):.6f}")
            print(f"p_max={max(float(row['p']) for row in rows):.6f}")

        if args.plot:
            plot_dashboard(rows, raw_rows, Path(args.plot))
            print(f"plot_saved={args.plot}")
        if args.plot_dir:
            plot_dir = Path(args.plot_dir)
            plot_dashboard(rows, raw_rows, plot_dir / "dashboard.png")
            plot_latency_decomposition(rows, raw_rows, plot_dir / "latency_decomposition.png")
            plot_front_density(raw_rows, plot_dir / "front_density.png")
            plot_cluster_mass(raw_rows, plot_dir / "cluster_mass.png")
            plot_occupancy_bias(raw_rows, plot_dir / "occupancy_bias.png")
            plot_core_latency(raw_rows, plot_dir / "core_latency.png")
            plot_spanning_probability(raw_rows, plot_dir / "spanning_probability.png")
            print(f"plot_dir_saved={plot_dir}")
    finally:
        conn.close()

    if args.fpga_plot:
        plot_fpga_all(
            Path(args.fpga_plot),
            db2_path=DEFAULT_DB2,
        )
        print(f"fpga_analysis_saved={args.fpga_plot}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
