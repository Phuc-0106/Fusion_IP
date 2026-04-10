#!/usr/bin/env python3
"""
Steps 1-2 (plan golden-RTL): kiểm tra merge CSV, cột 5-state, dt, và khớp P/Q/R memh ↔ generate_golden tuning.

Usage (from repo root):
  python scripts/check_golden_consistency.py --case 0 --datadir .
  python scripts/check_golden_consistency.py --case 0 --datadir . --golden-dir tb/golden --memh tb/state_mem_init.memh
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import os
import struct
import sys


def _load_generate_golden(script_dir: str):
    path = os.path.join(script_dir, "generate_golden.py")
    spec = importlib.util.spec_from_file_location("generate_golden", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_csv_rows(path: str) -> list[dict]:
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def fp32_word_to_float(w: int) -> float:
    return struct.unpack(">f", struct.pack(">I", w & 0xFFFFFFFF))[0]


def read_memh_words(path: str, max_words: int = 256) -> list[int]:
    words: list[int] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("//"):
                continue
            words.append(int(s, 16))
    if len(words) < max_words:
        raise ValueError(f"{path}: expected at least {max_words} hex words, got {len(words)}")
    return words[:max_words]


REQUIRED_UKF_COLUMNS = {"est_x", "est_y", "true_x", "true_y", "gps_x", "gps_y"}
OPTIONAL_5STATE = ("est_speed", "est_heading", "est_yaw_rate")


def main() -> int:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Golden / RTL alignment checks (plan steps 1–2)")
    ap.add_argument("--case", type=int, default=0, help="Tuning case 0–5 (must match ukf_results_caseN.csv)")
    ap.add_argument("--datadir", type=str, default=None, help="Directory with ukf_results + measurement CSVs")
    ap.add_argument("--golden-dir", type=str, default=None, help="If set, verify golden_stimulus dt vs odom source")
    ap.add_argument("--memh", type=str, default=None, help="state_mem_init.memh to compare vs get_tuning_matrices")
    ap.add_argument("--max-rows", type=int, default=None, help="Only check first N merged rows (default: all)")
    args = ap.parse_args()

    datadir = args.datadir or os.path.join(script_dir, "..")
    datadir = os.path.abspath(datadir)

    ukf_path = os.path.join(datadir, f"ukf_results_case{args.case}.csv")
    imu_path = os.path.join(datadir, "imu_measurement.csv")
    odo_path = os.path.join(datadir, "odometer_measurement.csv")

    errors: list[str] = []
    warnings: list[str] = []

    print("=== check_golden_consistency (plan steps 1-2) ===")
    print(f"  datadir: {datadir}")
    print(f"  case:    {args.case}")
    print()

    # ---- Step 1: files exist ----
    for p in (ukf_path, imu_path, odo_path):
        if not os.path.isfile(p):
            errors.append(f"Missing file: {p}")
    if errors:
        for e in errors:
            print(f"[FAIL] {e}")
        return 1

    ukf_rows = read_csv_rows(ukf_path)
    imu_rows = read_csv_rows(imu_path)
    odo_rows = read_csv_rows(odo_path)

    h0 = set(ukf_rows[0].keys()) if ukf_rows else set()
    missing = REQUIRED_UKF_COLUMNS - h0
    if missing:
        errors.append(f"ukf_results missing columns: {sorted(missing)}")

    for col in OPTIONAL_5STATE:
        if col not in h0:
            warnings.append(
                f"ukf_results missing '{col}' -> generate_golden uses 0.0; "
                "golden_expected 5-state CALIBRATION vs Python is unreliable. "
                "Regenerate ukf_results from tracking_ship with full state export."
            )

    n_ukf, n_imu, n_odo = len(ukf_rows), len(imu_rows), len(odo_rows)
    n_merge = min(n_ukf, n_imu, n_odo)
    if args.max_rows is not None:
        n_merge = min(n_merge, args.max_rows)

    if n_ukf != n_imu or n_ukf != n_odo:
        warnings.append(
            f"Row count mismatch: ukf={n_ukf} imu={n_imu} odo={n_odo} -> merge uses min={min(n_ukf, n_imu, n_odo)} rows (index alignment risk)."
        )

    print(f"[Step 1] Row counts: ukf={n_ukf}  imu={n_imu}  odo={n_odo}  merge_cap={n_merge}")
    if n_ukf == n_imu == n_odo:
        print("         Row counts OK (equal).")
    else:
        print("         WARNING: unequal lengths — see warning below.")

    # dt: row 0 forced to 0 in golden_stimulus; rows i>=1 use odom effective dt (dt<=0 -> 1.0)
    print(
        "[Step 1] dt: golden_stimulus row 0 is 0 (dt_hex 0; TB maps REG_DT 0 -> 1.0 s); "
        "rows i>=1 match odom effective dt (dt<=0 -> 1.0)."
    )

    dt_mismatches = 0
    if args.golden_dir:
        gdir = os.path.abspath(args.golden_dir)
        stim_path = os.path.join(gdir, "golden_stimulus.csv")
        if not os.path.isfile(stim_path):
            warnings.append(f"--golden-dir given but missing {stim_path}")
        else:
            stim = read_csv_rows(stim_path)
            n_g = len(stim)
            for i in range(min(n_merge, n_g)):
                gdt = float(stim[i]["dt"])
                if i == 0:
                    if abs(gdt) > 1e-9:
                        dt_mismatches += 1
                        if dt_mismatches <= 3:
                            warnings.append(
                                f"golden_stimulus row 0: expected dt=0, got dt={gdt} (regenerate golden)"
                            )
                    continue
                raw_dt = float(odo_rows[i]["dt"])
                eff = 1.0 if raw_dt <= 0.0 else raw_dt
                if abs(gdt - eff) > 1e-4:
                    dt_mismatches += 1
                    if dt_mismatches <= 3:
                        warnings.append(
                            f"golden_stimulus row {i}: dt={gdt} vs odom effective dt={eff} (raw={raw_dt})"
                        )
            if dt_mismatches == 0:
                print(f"[Step 1] golden_stimulus.csv dt column OK for rows 0..{min(n_merge,n_g)-1}.")
            else:
                print(f"[Step 1] WARNING: {dt_mismatches} dt mismatches vs golden_stimulus (regenerate golden or fix CSV).")

    print()
    print("[Step 1] gps_measurement.csv is NOT used in generate_golden.load_data() merge; GPS in stimulus comes from ukf_results (gps_x, gps_y).")
    print()

    # ---- Step 2: memh vs tuning matrices ----
    gg = _load_generate_golden(script_dir)
    P0, Q, R_gps, R_imu, R_odom = gg.get_tuning_matrices(args.case)

    memh_path = args.memh
    if memh_path is None:
        memh_path = os.path.join(script_dir, "..", "tb", "state_mem_init.memh")
    memh_path = os.path.abspath(memh_path)

    import numpy as np

    print(f"         P0 diag: {np.diag(P0)}")
    print(f"         Q  diag: {np.diag(Q)}")
    print(f"         R_gps diag: {np.diag(R_gps)}  R_imu diag: {np.diag(R_imu)}  R_odom: {R_odom}")

    if os.path.isfile(memh_path):
        mem = read_memh_words(memh_path)
        tol = 1e-5
        memh_errors: list[str] = []

        def check_mat(label: str, base: int, rows: int, cols: int, np_mat) -> None:
            for r in range(rows):
                for c in range(cols):
                    idx = base + r * cols + c
                    got = fp32_word_to_float(mem[idx])
                    exp = float(np_mat[r, c])
                    if abs(got - exp) > tol * max(1.0, abs(exp)):
                        memh_errors.append(
                            f"memh word[{idx}] {label}[{r},{c}]: got {got} expected {exp}"
                        )

        check_mat("P", 5, 5, 5, P0)
        check_mat("Q", 30, 5, 5, Q)
        check_mat("R_gps", 55, 2, 2, R_gps)
        check_mat("R_imu", 59, 2, 2, R_imu)
        got_ro = fp32_word_to_float(mem[63])
        if abs(got_ro - float(R_odom)) > tol * max(1.0, abs(R_odom)):
            memh_errors.append(f"memh word[63] R_odom: got {got_ro} expected {R_odom}")

        if memh_errors:
            errors.extend(memh_errors)
        else:
            print(f"[Step 2] memh matches get_tuning_matrices(case={args.case}): {memh_path}")
    else:
        warnings.append(f"No memh at {memh_path} — skipped P/Q/R byte compare.")

    print()
    print("[Step 2] RTL update order (must match tracking_ship one cycle if golden is to match DUT):")
    print("         ukf_controller: PREDICT -> UPDATE_GPS -> UPDATE_IMU -> UPDATE_ODOM -> WRITEBACK")
    print("         ukf_predictor.step(): predict_step then update_gps -> update_imu -> update_odom")
    print("[Step 2] Q(dt): RTL uses fixed Q in state RAM each step (no automatic Q proportional to dt scaling).")
    print("         If tracking_ship scales process noise by dt, golden will diverge from DUT until aligned.")
    print()

    for w in warnings:
        print(f"[WARN] {w}")
    for e in errors:
        print(f"[FAIL] {e}")

    if errors:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
