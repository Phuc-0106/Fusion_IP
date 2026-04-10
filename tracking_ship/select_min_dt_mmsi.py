#!/usr/bin/env python3
"""
Scan a large AIS CSV and print the MMSI with the smallest median inter-message
gap (seconds), using real timestamps. Requires at least --min-rows messages.

Example:
  python tracking_ship/select_min_dt_mmsi.py --ais tracking_ship/ais-2025-01-02
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_TRACK = Path(__file__).resolve().parent
if str(_TRACK) not in sys.path:
    sys.path.insert(0, str(_TRACK))

from data_processing import select_mmsi_min_median_inter_message_dt  # noqa: E402


def main() -> None:
    p = argparse.ArgumentParser(description="Pick MMSI with smallest median AIS dt")
    p.add_argument("--ais", type=str, required=True, help="Path to AIS CSV")
    p.add_argument("--chunksize", type=int, default=500_000)
    p.add_argument(
        "--min-rows",
        type=int,
        default=5,
        help="Ignore MMSIs with fewer rows (default 5)",
    )
    p.add_argument(
        "--progress-every",
        type=int,
        default=10,
        help="Print progress every N chunks (0=off)",
    )
    args = p.parse_args()

    path = Path(args.ais).resolve()
    if not path.is_file():
        sys.exit(f"Missing file: {path}")

    print(f"Scanning {path} (median inter-message dt per MMSI)...")
    mmsi, med_dt, n = select_mmsi_min_median_inter_message_dt(
        str(path),
        chunksize=args.chunksize,
        min_rows=args.min_rows,
        progress_every=args.progress_every,
    )
    print()
    print(f"MMSI:              {mmsi}")
    print(f"Median dt (s):     {med_dt:.6f}")
    print(f"Row count (file):  {n}")


if __name__ == "__main__":
    main()
