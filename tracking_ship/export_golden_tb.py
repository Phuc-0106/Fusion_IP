#!/usr/bin/env python3
"""
Export Fusion_IP testbench golden CSVs from AIS: dt from real timestamps (per MMSI).

Pipeline:
  1. Scan or pass MMSI; load all rows for that MMSI (sorted by timestamp).
  2. prepare_ship_ais_track: parse times, dedupe duplicate timestamps, cap length.
     Odometer ``dt`` = consecutive timestamp differences (see compute_time_deltas).
  3. Optional: --uniform-dt + --dt to resample onto a synthetic grid (old behavior).
  4. generate_synthetic_sensors -> save_measurements; UKF; generate_golden.py.

Example (real AIS message spacing):
  python tracking_ship/export_golden_tb.py \\
    --ais tracking_ship/ais-2025-01-02 \\
    --max-steps 512 \\
    --case 0 \\
    --work-dir tb/golden_work \\
    --outdir tb/golden
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

_TRACK = Path(__file__).resolve().parent
_REPO = _TRACK.parent
if str(_TRACK) not in sys.path:
    sys.path.insert(0, str(_TRACK))

from data_processing import (  # noqa: E402
    generate_synthetic_sensors,
    load_ais_ship_dataframe,
    prepare_ship_ais_track,
    resample_ship_uniform,
    save_measurements,
    select_mmsi_min_median_inter_message_dt,
    select_ship_mmsi_chunked,
)
from main import run_ukf_tracking, save_results  # noqa: E402


def main() -> None:
    p = argparse.ArgumentParser(
        description="AIS (timestamp-based dt) + UKF + generate_golden for TB",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Do not pass a literal ... at the end of the command (that causes "
            "'unrecognized arguments: ...'). In PowerShell, use a single line or "
            "a backtick ` for line continuation — not three dots.\n\n"
            "Example (auto MMSI = smallest median AIS gap):\n"
            "  python tracking_ship/export_golden_tb.py "
            "--ais tracking_ship/ais-2025-01-02 --mmsi-select min_median_dt "
            "--min-rows-mmsi 5 --case 0 --max-steps 512 "
            "--work-dir tb/golden_work --outdir tb/golden"
        ),
    )
    p.add_argument("--ais", type=str, required=True, help="Path to AIS CSV (any column names via normalize)")
    p.add_argument(
        "--uniform-dt",
        action="store_true",
        help="Resample onto a uniform grid; --dt is spacing (s). Default: use real AIS timestamps.",
    )
    p.add_argument(
        "--dt",
        type=float,
        default=0.2,
        help="With --uniform-dt: grid spacing in seconds (default 0.2). Ignored otherwise.",
    )
    p.add_argument("--case", type=int, default=0, help="UKF tuning case 0-5 (default 0)")
    p.add_argument(
        "--max-steps",
        type=int,
        default=512,
        help="Cap trajectory length (rows) after resample (default 512)",
    )
    p.add_argument("--chunksize", type=int, default=500_000, help="Rows per read_csv chunk (default 500k)")
    p.add_argument("--mmsi", type=int, default=None, help="Fixed MMSI (skip auto selection)")
    p.add_argument(
        "--mmsi-select",
        choices=("most_samples", "min_median_dt"),
        default="most_samples",
        help="When --mmsi omitted: most rows in file, or smallest median AIS gap (default: most_samples).",
    )
    p.add_argument(
        "--min-rows-mmsi",
        type=int,
        default=5,
        help="With min_median_dt: ignore MMSIs with fewer than this many rows (default 5).",
    )
    p.add_argument(
        "--work-dir",
        type=str,
        default=None,
        help="Scratch dir for ukf_results + sensor CSVs (default: <repo>/tb/golden_work)",
    )
    p.add_argument(
        "--outdir",
        type=str,
        default=None,
        help="Output dir for golden_stimulus/expected/memh (default: <repo>/tb/golden)",
    )
    p.add_argument("--skip-ukf", action="store_true", help="Only prepare+sensors+save (no UKF/golden)")
    args = p.parse_args()

    ais_path = Path(args.ais).resolve()
    if not ais_path.is_file():
        sys.exit(f"Missing AIS file: {ais_path}")

    work_dir = Path(args.work_dir) if args.work_dir else _REPO / "tb" / "golden_work"
    outdir = Path(args.outdir) if args.outdir else _REPO / "tb" / "golden"
    work_dir.mkdir(parents=True, exist_ok=True)
    outdir.mkdir(parents=True, exist_ok=True)

    if args.mmsi is not None:
        mmsi = int(args.mmsi)
        print(f"Using MMSI {mmsi} (--mmsi)")
    elif args.mmsi_select == "most_samples":
        print("Scanning AIS for MMSI with most rows (chunked count)...")
        mmsi, n = select_ship_mmsi_chunked(str(ais_path), chunksize=args.chunksize)
        print(f"Selected MMSI {mmsi} ({n} rows in file)")
    else:
        print(
            "Scanning AIS for MMSI with smallest median inter-message dt "
            f"(min_rows={args.min_rows_mmsi})..."
        )
        mmsi, med_dt, n = select_mmsi_min_median_inter_message_dt(
            str(ais_path),
            chunksize=args.chunksize,
            min_rows=args.min_rows_mmsi,
            progress_every=10,
        )
        print(f"Selected MMSI {mmsi} (median AIS gap {med_dt:.3f} s, {n} rows)")

    print(f"Loading ship {mmsi}...")
    ship = load_ais_ship_dataframe(str(ais_path), mmsi=mmsi, chunksize=args.chunksize)
    print(f"  Raw rows: {len(ship)}")

    if args.uniform_dt:
        print(f"Uniform resample: dt={args.dt} s, max_steps={args.max_steps}...")
        ship_tr = resample_ship_uniform(ship, dt_sec=args.dt, max_rows=args.max_steps)
        print(f"  Rows after resample: {len(ship_tr)}")
    else:
        print(f"Using AIS timestamps (per MMSI); max_steps={args.max_steps}...")
        ship_tr = prepare_ship_ais_track(ship, max_rows=args.max_steps)
        print(f"  Rows after sort/dedupe/cap: {len(ship_tr)}")

    sensors = generate_synthetic_sensors(ship_tr)
    save_measurements(sensors, output_dir=str(work_dir))
    print(f"Saved measurements -> {work_dir}")

    if args.skip_ukf:
        print("skip-ukf: done.")
        return

    print(f"Running UKF case {args.case}...")
    results = run_ukf_tracking(sensors, case_id=args.case)
    ukf_name = f"ukf_results_case{args.case}.csv"
    save_results(results, output_path=str(work_dir / ukf_name))

    gen = _REPO / "scripts" / "generate_golden.py"
    if not gen.is_file():
        sys.exit(f"Missing {gen}")

    cmd = [
        sys.executable,
        str(gen),
        "--case",
        str(args.case),
        "--datadir",
        str(work_dir),
        "--outdir",
        str(outdir),
        "--steps",
        str(len(ship_tr)),
    ]
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, check=True)
    print(f"Done. Golden files in {outdir}")


if __name__ == "__main__":
    main()
