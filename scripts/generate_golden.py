#!/usr/bin/env python3
"""
Golden Vector Generator for Fusion IP UKF RTL Verification
(AIS-based ground truth version)

Reads:
  - ukf_results_case{N}.csv   (est_x/y, true_x/y, gps_x/y from Python UKF)
  - gps_measurement.csv       (gps_x/y noisy + true x/y)
  - imu_measurement.csv       (heading, yaw_rate noisy)
  - odometer_measurement.csv  (speed noisy, dt)

Generates:
  1. state_mem_init.memh       — x[5]=x0 from first-row sensors (like tracking_ship); P, Q, R FP32
  2. golden_stimulus.csv       — row0 dt=0 (dt_hex 0 → TB/RTL use 1.0 s); then per-cycle sensors + GT
  3. golden_expected.csv       — per-cycle: Python UKF est + ground truth
                                 (for offline DUT-vs-GT and DUT-vs-SwUKF analysis)

Usage:
  python generate_golden.py [--case 0] [--steps 200] [--datadir ..]
"""

import argparse
import struct
import numpy as np
import os
import csv

# =============================================================================
# Hex encoding: IEEE-754 float32 only (matches params.vh / fusion_ip RTL)
# =============================================================================
def float_to_fp32(val):
    """Return 32-bit unsigned int with IEEE-754 single-precision encoding."""
    return struct.unpack('>I', struct.pack('>f', float(val)))[0]

def val_to_hex_int(val):
    """Convert a float to 32-bit IEEE-754 hex (unsigned int) for memh / CSV."""
    return float_to_fp32(val)

def val_hex(val):
    """8-char hex string for a float in the active encoding."""
    return f"{val_to_hex_int(val):08x}"



# =============================================================================
# Tuning cases — must match tracking_ship/main.py get_tuning_params()
# =============================================================================
# Match tracking_ship/data_processing: r ~ U(0, R_MAX), Var(xy)=R^2/6 => std = R/sqrt(6)
GPS_NOISE_R_MAX_M = 20.0
GPS_NOISE_STD = float(np.sqrt((GPS_NOISE_R_MAX_M**2) / 6.0))
IMU_HEADING_NOISE_STD = 0.15
IMU_YAW_RATE_NOISE_STD = 0.05
ODOMETER_NOISE_STD = 1.5

def get_tuning_matrices(case_id):
    """Return (P0, Q, R_gps, R_imu, R_odom) matching tracking_ship cases."""
    P0_base = np.diag([
        GPS_NOISE_STD**2,
        GPS_NOISE_STD**2,
        ODOMETER_NOISE_STD**2,
        IMU_HEADING_NOISE_STD**2,
        IMU_YAW_RATE_NOISE_STD**2,
    ])
    Q_base = np.diag([0.5, 0.5, 0.1, 0.01, 0.001])
    R_gps_base = np.diag([GPS_NOISE_STD**2, GPS_NOISE_STD**2])
    R_imu_base = np.diag([IMU_HEADING_NOISE_STD**2, IMU_YAW_RATE_NOISE_STD**2])
    R_odo_base = ODOMETER_NOISE_STD**2

    cases = {
        0: (1.0, 1.0, 1.0, 1.0),
        1: (1.0, 0.1, 5.0, 5.0),
        2: (1.0, 10.0, 0.2, 0.2),
        3: (0.01, 0.01, 0.01, 0.01),
        4: (10.0, 10.0, 10.0, 10.0),
        5: (1.0, 1.0, 1.0, 1.0),   # GPS-specific handled below
    }
    p_s, q_s, r_s, r_s2 = cases[case_id]
    gps_scale = 10.0 if case_id == 5 else r_s

    P0    = P0_base * p_s
    Q     = Q_base * q_s
    R_gps = R_gps_base * gps_scale
    R_imu = R_imu_base * r_s2
    R_odo = R_odo_base * r_s2
    return P0, Q, R_gps, R_imu, R_odo


# =============================================================================
# Read tracking_ship data
# =============================================================================
def read_csv_simple(path):
    """Read CSV into list of dicts (no pandas dependency)."""
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows

def load_data(datadir, case_id, max_steps):
    """Load and merge ukf_results + sensor measurements.

    Returns list of dicts with full 5-state vector keys:
        true_x/y, gps_x/y, est_x/y/speed/heading/yaw_rate,
        imu_heading, imu_yaw_rate, odom_speed, dt, timestamp
    """
    ukf_path = os.path.join(datadir, f"ukf_results_case{case_id}.csv")
    gps_path = os.path.join(datadir, "gps_measurement.csv")
    imu_path = os.path.join(datadir, "imu_measurement.csv")
    odo_path = os.path.join(datadir, "odometer_measurement.csv")

    for p in [ukf_path, gps_path, imu_path, odo_path]:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing: {p}")

    ukf_rows = read_csv_simple(ukf_path)
    imu_rows = read_csv_simple(imu_path)
    odo_rows = read_csv_simple(odo_path)

    n = min(len(ukf_rows), len(imu_rows), len(odo_rows))
    if max_steps and max_steps < n:
        n = max_steps

    merged = []
    for i in range(n):
        u = ukf_rows[i]
        im = imu_rows[i]
        od = odo_rows[i]

        true_x = float(u['true_x'])
        true_y = float(u['true_y'])
        gps_x  = float(u['gps_x'])
        gps_y  = float(u['gps_y'])
        est_x  = float(u['est_x'])
        est_y  = float(u['est_y'])

        # Full 5-state vector from extended CSV (fall back to 0 if columns missing)
        est_speed    = float(u.get('est_speed', 0))
        est_heading  = float(u.get('est_heading', 0))
        est_yaw_rate = float(u.get('est_yaw_rate', 0))

        imu_heading  = float(im['heading'])
        imu_yaw_rate = float(im['yaw_rate'])
        odom_speed   = float(od['speed'])
        dt           = float(od['dt'])
        # Row 0: stimulus dt column = 0 and dt_hex = 0 (golden_stimulus_reader maps REG 0 -> 1.0 s FP32).
        # Other rows: match tracking_ship/main.py — if dt <= 0: dt = 1.0
        if i == 0:
            dt = 0.0
        elif dt <= 0.0:
            dt = 1.0

        merged.append({
            'timestamp':      u.get('timestamp', str(i)),
            'true_x':         true_x,
            'true_y':         true_y,
            'gps_x':          gps_x,
            'gps_y':          gps_y,
            'est_x':          est_x,
            'est_y':          est_y,
            'est_speed':      est_speed,
            'est_heading':    est_heading,
            'est_yaw_rate':   est_yaw_rate,
            'imu_heading':    imu_heading,
            'imu_yaw_rate':   imu_yaw_rate,
            'odom_speed':     odom_speed,
            'dt':             dt,
        })

    return merged


# =============================================================================
# Writers
# =============================================================================
def write_memh(path, P, Q, R_gps, R_imu, R_odom, data):
    """Write 256-word state_mem_init.memh (IEEE-754 float32 words).

    x[5] words 0-4: CTRV x0 = [gps_x, gps_y, odom_speed, imu_heading, imu_yaw_rate]
    from merged row 0 (same convention as tracking_ship main.py x0).
    """
    enc = "IEEE754-FP32"
    mem = [0] * 256
    m0 = data[0]
    x0 = [
        float(m0['gps_x']),
        float(m0['gps_y']),
        float(m0['odom_speed']),
        float(m0['imu_heading']),
        float(m0['imu_yaw_rate']),
    ]
    for j in range(5):
        mem[j] = val_to_hex_int(x0[j])
    # P[5x5]: words 5-29
    for r in range(5):
        for c in range(5):
            mem[5 + r*5 + c] = val_to_hex_int(P[r, c])
    # Q[5x5]: words 30-54
    for r in range(5):
        for c in range(5):
            mem[30 + r*5 + c] = val_to_hex_int(Q[r, c])
    # R_gps[2x2]: words 55-58
    for r in range(2):
        for c in range(2):
            mem[55 + r*2 + c] = val_to_hex_int(R_gps[r, c])
    # R_imu[2x2]: words 59-62
    for r in range(2):
        for c in range(2):
            mem[59 + r*2 + c] = val_to_hex_int(R_imu[r, c])
    # R_odom: word 63
    mem[63] = val_to_hex_int(R_odom)

    with open(path, 'w') as f:
        f.write(f"// State memory init: x0 (row0 sensors), P, Q, R in {enc} (AIS-based golden)\n")
        for v in mem:
            f.write(f"{v:08x}\n")
    print(f"  Wrote {path}  ({enc})")


def write_stimulus_csv(path, data):
    """Write golden_stimulus.csv with sensor hex + dt_hex + ground truth."""
    with open(path, 'w') as f:
        f.write("step,timestamp,"
                "gps_x_hex,gps_y_hex,gps_valid,"
                "imu_psi_hex,imu_dot_hex,imu_valid,"
                "odom_v_hex,odom_valid,"
                "dt_hex,"
                "gt_x,gt_y,"
                "gps_x,gps_y,"
                "imu_heading,imu_yaw_rate,odom_speed,dt\n")
        for k, m in enumerate(data):
            gps_valid = 1
            imu_valid = 1
            odom_valid = 1
            f.write(f"{k},{m['timestamp']},"
                    f"{val_hex(m['gps_x'])},{val_hex(m['gps_y'])},{gps_valid},"
                    f"{val_hex(m['imu_heading'])},{val_hex(m['imu_yaw_rate'])},{imu_valid},"
                    f"{val_hex(m['odom_speed'])},{odom_valid},"
                    f"{val_hex(m['dt'])},"
                    f"{m['true_x']:.8f},{m['true_y']:.8f},"
                    f"{m['gps_x']:.8f},{m['gps_y']:.8f},"
                    f"{m['imu_heading']:.8f},{m['imu_yaw_rate']:.8f},"
                    f"{m['odom_speed']:.8f},{m['dt']:.4f}\n")
    print(f"  Wrote {path}  ({len(data)} rows)")


def write_expected_csv(path, data):
    """Write golden_expected.csv with full 5-state Python UKF estimates + GT.

    Columns:
      step, est_x/y/speed/heading/yaw_rate (Python UKF float),
      gt_x/y (AIS ground truth), gps_x/y (noisy GPS),
      gps_error, ukf_sw_error
    """
    with open(path, 'w') as f:
        f.write("step,timestamp,"
                "est_x,est_y,est_speed,est_heading,est_yaw_rate,"
                "gt_x,gt_y,"
                "gps_x,gps_y,"
                "gps_error,ukf_sw_error\n")
        for k, m in enumerate(data):
            gps_err = np.sqrt((m['gps_x'] - m['true_x'])**2 +
                              (m['gps_y'] - m['true_y'])**2)
            ukf_err = np.sqrt((m['est_x'] - m['true_x'])**2 +
                              (m['est_y'] - m['true_y'])**2)
            f.write(f"{k},{m['timestamp']},"
                    f"{m['est_x']:.8f},{m['est_y']:.8f},"
                    f"{m['est_speed']:.8f},{m['est_heading']:.8f},"
                    f"{m['est_yaw_rate']:.8f},"
                    f"{m['true_x']:.8f},{m['true_y']:.8f},"
                    f"{m['gps_x']:.8f},{m['gps_y']:.8f},"
                    f"{gps_err:.8f},{ukf_err:.8f}\n")
    print(f"  Wrote {path}  ({len(data)} rows)")


# =============================================================================
# Main
# =============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Generate golden vectors from AIS-based UKF results")
    parser.add_argument("--case", type=int, default=0,
                        help="Tuning case ID 0-5 (default: 0)")
    parser.add_argument("--steps", type=int, default=None,
                        help="Max UKF cycles (default: all)")
    parser.add_argument("--datadir", type=str, default=None,
                        help="Directory with ukf_results + measurement CSVs")
    parser.add_argument("--outdir", type=str, default=None,
                        help="Output directory (default: ../tb/golden/)")
    parser.add_argument("--fp32", action="store_true",
                        help=argparse.SUPPRESS)  # deprecated; float32 is always used
    parser.add_argument("--no-fp32", action="store_true",
                        help=argparse.SUPPRESS)  # deprecated no-op
    args = parser.parse_args()
    if args.no_fp32:
        print("  NOTE: --no-fp32 is ignored; RTL expects IEEE-754 float32 in memh/stimulus.\n")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    datadir = args.datadir or os.path.join(script_dir, "..")
    outdir  = args.outdir  or os.path.join(script_dir, "..", "tb", "golden")
    os.makedirs(outdir, exist_ok=True)

    print("=== Golden Vector Generator (AIS-based) ===")
    print(f"  Case:    {args.case}")
    print(f"  Data:    {datadir}")
    print(f"  Output:  {outdir}")
    if args.steps:
        print(f"  Steps:   {args.steps}")
    print()

    # Load data
    data = load_data(datadir, args.case, args.steps)
    print(f"  Loaded {len(data)} merged rows")

    # Get P/Q/R for this case
    P0, Q, R_gps, R_imu, R_odom = get_tuning_matrices(args.case)
    print(f"  P0 diag: {np.diag(P0)}")
    print(f"  Q  diag: {np.diag(Q)}")
    print(f"  R_gps:   {np.diag(R_gps)}")
    print(f"  R_imu:   {np.diag(R_imu)}")
    print(f"  R_odom:  {R_odom}")

    print(f"  Encoding: IEEE-754 float32 (memh + stimulus hex)\n")

    # Write outputs
    write_memh(os.path.join(outdir, "state_mem_init.memh"), P0, Q, R_gps, R_imu, R_odom, data)
    write_stimulus_csv(os.path.join(outdir, "golden_stimulus.csv"), data)
    write_expected_csv(os.path.join(outdir, "golden_expected.csv"), data)

    # Also copy memh to tb/ for direct simulation
    import shutil
    tb_memh = os.path.join(script_dir, "..", "tb", "state_mem_init.memh")
    shutil.copy2(os.path.join(outdir, "state_mem_init.memh"), tb_memh)
    print(f"  Copied memh -> {tb_memh}")

    # Summary statistics
    print()
    gt_x  = np.array([m['true_x'] for m in data])
    gt_y  = np.array([m['true_y'] for m in data])
    gps_x = np.array([m['gps_x'] for m in data])
    gps_y = np.array([m['gps_y'] for m in data])
    est_x = np.array([m['est_x'] for m in data])
    est_y = np.array([m['est_y'] for m in data])

    gps_err = np.sqrt((gps_x - gt_x)**2 + (gps_y - gt_y)**2)
    ukf_err = np.sqrt((est_x - gt_x)**2 + (est_y - gt_y)**2)

    print(f"  GPS  Position RMSE: {np.sqrt(np.mean(gps_err**2)):.3f} m")
    print(f"  UKF(SW) Pos RMSE:   {np.sqrt(np.mean(ukf_err**2)):.3f} m")
    print(f"  Improvement:        {(1 - np.sqrt(np.mean(ukf_err**2))/np.sqrt(np.mean(gps_err**2)))*100:.1f}%")
    print()
    print("Done. Files ready for UVM simulation.")


if __name__ == "__main__":
    main()
