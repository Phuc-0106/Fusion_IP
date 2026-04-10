"""
Data Processing Module for Ship Tracking UKF

This module processes AIS (Automatic Identification System) data and generates
synthetic sensor measurements for UKF-based ship tracking.

IMPORTANT ASSUMPTIONS:
----------------------
1. AIS data provides ground-truth ship positions and kinematics
2. Synthetic sensors are SIMULATED from AIS data with added noise:
   - GPS: uniform radial position error (0..R m) in ENU
   - IMU: Derived from AIS COG (Course Over Ground) with heading/yaw rate noise
   - Odometer: Derived from AIS SOG (Speed Over Ground) with speed noise
3. These synthetic measurements simulate real-world sensor imperfections
4. The ship with most samples is selected to ensure sufficient data for
   meaningful UKF performance evaluation and statistical significance

Author: Ship Tracking UKF Project
"""

import numpy as np
import pandas as pd
from collections import defaultdict
from typing import Tuple, Dict, Optional, List

# GPS: uniform radial error r ~ U(0, GPS_NOISE_R_MAX_M), random azimuth (horizontal plane).
# Equivalent per-axis std for UKF P/R: Var(x)=Var(y)=R^2/6 when r~U(0,R), theta~U(0,2pi).
GPS_NOISE_R_MAX_M = 20.0
GPS_NOISE_STD = float(np.sqrt((GPS_NOISE_R_MAX_M**2) / 6.0))

# Other sensors (Gaussian)
IMU_HEADING_NOISE_STD = 0.15  # radians (~8 degrees)
IMU_YAW_RATE_NOISE_STD = 0.05  # rad/s
ODOMETER_NOISE_STD = 1.5    # m/s (includes slip/calibration errors)

# Realistic sensor degradation parameters
GPS_OUTAGE_PROBABILITY = 0.05  # 5% chance of GPS outage per sample
IMU_DRIFT_RATE = 0.002         # rad/sample bias drift

# Earth radius for coordinate conversion
EARTH_RADIUS = 6371000.0  # meters


def load_ais_data(filepath: str) -> pd.DataFrame:
    """Load AIS data from CSV file."""
    df = pd.read_csv(filepath)
    # Normalize column names to lowercase
    df.columns = df.columns.str.strip().str.lower()
    # Map common AIS column names to expected names
    column_mapping = {
        'basedatetime': 'timestamp',
        'base_date_time': 'timestamp',
        'lat': 'latitude',
        'lon': 'longitude'
    }
    df = df.rename(columns=column_mapping)
    return df


def select_ship_with_most_samples(df: pd.DataFrame) -> Tuple[int, pd.DataFrame]:
    """
    Select the ship (MMSI) with the highest number of AIS samples.
    
    Rationale: More samples provide:
    - Better statistical significance for RMSE evaluation
    - Longer trajectory for meaningful tracking demonstration
    - More robust UKF convergence assessment
    """
    sample_counts = df.groupby('mmsi').size()
    selected_mmsi = sample_counts.idxmax()
    num_samples = sample_counts.max()
    
    print(f"=" * 50)
    print(f"Ship Selection Summary")
    print(f"=" * 50)
    print(f"Total ships in dataset: {len(sample_counts)}")
    print(f"Selected MMSI: {selected_mmsi}")
    print(f"Number of samples: {num_samples}")
    print(f"=" * 50)
    
    ship_data = df[df['mmsi'] == selected_mmsi].copy()
    ship_data = ship_data.sort_values('timestamp').reset_index(drop=True)
    
    return selected_mmsi, ship_data


def latlon_to_enu(lat: np.ndarray, lon: np.ndarray, 
                  lat_ref: float, lon_ref: float) -> Tuple[np.ndarray, np.ndarray]:
    """
    Convert latitude/longitude to local ENU (East-North-Up) coordinates.
    
    Uses flat-Earth approximation suitable for small areas.
    Reference point is set to the first position in the trajectory.
    
    Args:
        lat, lon: Arrays of latitude/longitude in degrees
        lat_ref, lon_ref: Reference point (origin) in degrees
    
    Returns:
        x_east, y_north: Position in meters relative to reference
    """
    lat_rad = np.radians(lat)
    lon_rad = np.radians(lon)
    lat_ref_rad = np.radians(lat_ref)
    lon_ref_rad = np.radians(lon_ref)
    
    # East-North conversion using equirectangular projection
    x_east = EARTH_RADIUS * (lon_rad - lon_ref_rad) * np.cos(lat_ref_rad)
    y_north = EARTH_RADIUS * (lat_rad - lat_ref_rad)
    
    return x_east, y_north


def compute_time_deltas(timestamps: np.ndarray) -> np.ndarray:
    """Seconds between consecutive samples; row 0 is 0. Uses real clock deltas (sub-second ok)."""
    ts = pd.to_datetime(pd.Series(np.asarray(timestamps)), utc=False, errors="coerce")
    dt_sec = ts.diff().dt.total_seconds().to_numpy(dtype=np.float64)
    dt_sec[0] = 0.0
    return np.nan_to_num(dt_sec, nan=0.0)


def generate_synthetic_sensors(ship_data: pd.DataFrame) -> Dict[str, pd.DataFrame]:
    """
    Generate synthetic sensor measurements from AIS ground-truth data.
    
    SYNTHETIC SENSOR GENERATION:
    ----------------------------
    These sensors are SIMULATED to demonstrate UKF sensor fusion:
    
    1. GPS: True position + uniform radial error in [0, GPS_NOISE_R_MAX_M] m
       - Random direction; matches “0 .. ~10–20 m” class error when R_MAX=20
    
    2. IMU: Heading from COG + noise, yaw rate from heading derivative
       - Simulates gyroscope and compass measurements
    
    3. Odometer: SOG + small noise
       - Simulates speed sensor (e.g., Doppler log)
    """
    # Extract reference point (first position)
    lat_ref = ship_data['latitude'].iloc[0]
    lon_ref = ship_data['longitude'].iloc[0]
    
    # Convert to ENU coordinates
    x_true, y_true = latlon_to_enu(
        ship_data['latitude'].values,
        ship_data['longitude'].values,
        lat_ref, lon_ref
    )
    
    # Compute timestamps
    timestamps = ship_data['timestamp'].values
    dt = compute_time_deltas(timestamps)
    
    # Ground truth heading from COG (convert from degrees to radians)
    # COG is typically measured clockwise from North
    heading_true = np.radians(90 - ship_data['cog'].values)  # Convert to math convention
    
    # Ground truth speed (convert from knots to m/s)
    speed_true = ship_data['sog'].values * 0.514444  # knots to m/s
    
    # Compute yaw rate from heading changes
    heading_unwrapped = np.unwrap(heading_true)
    yaw_rate_true = np.zeros_like(heading_true)
    # Compute differences and handle zero/small time steps
    valid_dt = np.maximum(dt[1:], 0.1)
    yaw_rate_true[1:] = np.diff(heading_unwrapped) / valid_dt
    yaw_rate_true[0] = yaw_rate_true[1]  # Copy first non-zero value to handle first sample
    
    # Generate noisy measurements with realistic degradation
    np.random.seed(42)  # For reproducibility
    
    # GPS: uniform radial offset r in [0, R_MAX], random heading (ENU x/y)
    n = len(x_true)
    r = np.random.uniform(0.0, GPS_NOISE_R_MAX_M, n)
    theta = np.random.uniform(0.0, 2.0 * np.pi, n)
    gps_x = x_true + r * np.cos(theta)
    gps_y = y_true + r * np.sin(theta)

    # GPS outages: extra radial error up to ~2x R_MAX (re-acquisition / multipath)
    outage_mask = np.random.random(n) < GPS_OUTAGE_PROBABILITY
    if np.any(outage_mask):
        m = int(np.sum(outage_mask))
        r_o = np.random.uniform(0.0, 2.0 * GPS_NOISE_R_MAX_M, m)
        th_o = np.random.uniform(0.0, 2.0 * np.pi, m)
        gps_x[outage_mask] += r_o * np.cos(th_o)
        gps_y[outage_mask] += r_o * np.sin(th_o)
    
    # IMU measurements with drift (bias accumulates over time)
    imu_drift = np.cumsum(np.random.normal(0, IMU_DRIFT_RATE, len(heading_true)))
    imu_heading = heading_true + imu_drift + np.random.normal(0, IMU_HEADING_NOISE_STD, len(heading_true))
    imu_yaw_rate = yaw_rate_true + np.random.normal(0, IMU_YAW_RATE_NOISE_STD, len(yaw_rate_true))
    # Ensure no NaN or inf values
    imu_heading = np.nan_to_num(imu_heading, nan=0.0, posinf=0.0, neginf=0.0)
    imu_yaw_rate = np.nan_to_num(imu_yaw_rate, nan=0.0, posinf=0.0, neginf=0.0)
    
    # Odometer measurements (speed with noise + occasional slip)
    odo_speed = speed_true + np.random.normal(0, ODOMETER_NOISE_STD, len(speed_true))
    # Add occasional large errors (wheel slip)
    slip_mask = np.random.random(len(speed_true)) < 0.02  # 2% slip rate
    odo_speed[slip_mask] *= np.random.uniform(0.5, 1.5, np.sum(slip_mask))
    odo_speed = np.maximum(odo_speed, 0)  # Speed cannot be negative
    
    # Create DataFrames
    gps_df = pd.DataFrame({
        'timestamp': timestamps,
        'x': gps_x,
        'y': gps_y,
        'x_true': x_true,
        'y_true': y_true
    })
    
    imu_df = pd.DataFrame({
        'timestamp': timestamps,
        'heading': imu_heading,
        'yaw_rate': imu_yaw_rate,
        'heading_true': heading_true,
        'yaw_rate_true': yaw_rate_true
    })
    
    odo_df = pd.DataFrame({
        'timestamp': timestamps,
        'speed': odo_speed,
        'speed_true': speed_true,
        'dt': dt
    })
    
    return {
        'gps': gps_df,
        'imu': imu_df,
        'odometer': odo_df
    }


def save_measurements(sensors: Dict[str, pd.DataFrame], output_dir: str = '.'):
    """Save sensor measurements to CSV files."""
    sensors['gps'].to_csv(f'{output_dir}/gps_measurement.csv', index=False)
    sensors['imu'].to_csv(f'{output_dir}/imu_measurement.csv', index=False)
    sensors['odometer'].to_csv(f'{output_dir}/odometer_measurement.csv', index=False)
    print(f"Saved sensor measurements to {output_dir}/")


def _normalize_ais_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Same column normalization as load_ais_data (for chunked reads)."""
    df = df.copy()
    df.columns = df.columns.str.strip().str.lower()
    column_mapping = {
        'basedatetime': 'timestamp',
        'base_date_time': 'timestamp',
        'lat': 'latitude',
        'lon': 'longitude',
    }
    return df.rename(columns=column_mapping)


def select_ship_mmsi_chunked(ais_filepath: str, chunksize: int = 500_000) -> Tuple[int, int]:
    """
    Scan a large AIS CSV in chunks and return (mmsi, count) for the ship with
    the most records (same rule as select_ship_with_most_samples).
    """
    counts: Dict[int, int] = {}
    for chunk in pd.read_csv(ais_filepath, chunksize=chunksize):
        chunk = _normalize_ais_columns(chunk)
        if 'mmsi' not in chunk.columns:
            raise ValueError("AIS CSV must contain an 'mmsi' column")
        vc = chunk['mmsi'].value_counts()
        for mmsi, cnt in vc.items():
            mmsi_i = int(mmsi)
            counts[mmsi_i] = counts.get(mmsi_i, 0) + int(cnt)
    if not counts:
        raise ValueError(f"No rows read from {ais_filepath}")
    best_mmsi = max(counts, key=lambda k: counts[k])
    return best_mmsi, counts[best_mmsi]


def _median_positive_gap_sec_sorted_ns(ns_sorted: np.ndarray) -> float:
    """Median of positive time gaps (seconds) from sorted unique epoch-ns timestamps."""
    if ns_sorted.size < 2:
        return float("inf")
    d = np.diff(ns_sorted.astype(np.float64)) / 1e9
    d = d[d > 1e-9]
    if d.size == 0:
        return float("inf")
    return float(np.median(d))


def select_mmsi_min_median_inter_message_dt(
    ais_filepath: str,
    chunksize: int = 500_000,
    min_rows: int = 5,
    progress_every: int = 10,
) -> Tuple[int, float, int]:
    """
    Scan entire AIS CSV (chunked): collect timestamps per MMSI, then among ships
    with at least ``min_rows`` rows choose the one with the **smallest median**
    positive gap between consecutive **distinct** timestamps (real AIS spacing).

    Returns:
        (mmsi, median_dt_seconds, row_count)
    """
    by_mmsi: Dict[int, List[int]] = defaultdict(list)

    chunk_idx = 0
    for chunk in pd.read_csv(ais_filepath, chunksize=chunksize):
        chunk = _normalize_ais_columns(chunk)
        if "mmsi" not in chunk.columns or "timestamp" not in chunk.columns:
            raise ValueError("AIS CSV must contain 'mmsi' and a time column (e.g. base_date_time)")
        ts = pd.to_datetime(chunk["timestamp"], utc=False, errors="coerce")
        ok = ts.notna()
        if not bool(ok.any()):
            chunk_idx += 1
            continue
        ms = chunk.loc[ok, "mmsi"].astype(np.int64).to_numpy()
        # datetime64[ns] -> int64 nanoseconds since epoch
        vals = ts.loc[ok].astype("int64").to_numpy()
        for v_ns, m in zip(vals, ms):
            by_mmsi[int(m)].append(int(v_ns))
        chunk_idx += 1
        if progress_every and chunk_idx % progress_every == 0:
            print(f"  ... read {chunk_idx} chunks, {len(by_mmsi)} distinct MMSI so far")

    if not by_mmsi:
        raise ValueError(f"No rows read from {ais_filepath}")

    best_mmsi = -1
    best_med = float("inf")
    best_n = 0

    for mmsi, lst in by_mmsi.items():
        n = len(lst)
        if n < min_rows:
            continue
        arr = np.asarray(lst, dtype=np.int64)
        arr = np.unique(arr)
        med = _median_positive_gap_sec_sorted_ns(arr)
        if med < best_med:
            best_med = med
            best_mmsi = mmsi
            best_n = n

    if best_mmsi < 0:
        raise ValueError(
            f"No MMSI with at least {min_rows} rows and two distinct timestamps"
        )

    return best_mmsi, best_med, best_n


def load_ais_ship_dataframe(ais_filepath: str, mmsi: int, chunksize: int = 500_000) -> pd.DataFrame:
    """Load all rows for one MMSI from a large AIS file without loading the full file."""
    parts: list = []
    for chunk in pd.read_csv(ais_filepath, chunksize=chunksize):
        chunk = _normalize_ais_columns(chunk)
        if 'mmsi' not in chunk.columns:
            raise ValueError("AIS CSV must contain an 'mmsi' column")
        sub = chunk[chunk['mmsi'] == mmsi]
        if len(sub):
            parts.append(sub)
    if not parts:
        raise ValueError(f"No rows found for MMSI {mmsi}")
    ship = pd.concat(parts, ignore_index=True)
    ship = ship.sort_values('timestamp').reset_index(drop=True)
    return ship


def prepare_ship_ais_track(
    ship_data: pd.DataFrame,
    max_rows: Optional[int] = None,
) -> pd.DataFrame:
    """
    One MMSI, time-ordered AIS rows: parse timestamps, drop duplicate times,
    optional head limit. ``dt`` in sensors is then from real message spacing, not
    an artificial uniform grid.
    """
    required = ("timestamp", "latitude", "longitude", "cog", "sog", "mmsi")
    for col in required:
        if col not in ship_data.columns:
            raise ValueError(f"prepare_ship_ais_track: missing column '{col}'")

    df = ship_data.copy()
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=False, errors="coerce")
    bad = df["timestamp"].isna()
    if bool(bad.any()):
        n = int(bad.sum())
        df = df.loc[~bad].reset_index(drop=True)
        print(f"prepare_ship_ais_track: dropped {n} rows with invalid timestamp")

    df = df.sort_values("timestamp").reset_index(drop=True)
    dup = df["timestamp"].duplicated(keep="first")
    if bool(dup.any()):
        n = int(dup.sum())
        df = df.loc[~dup].reset_index(drop=True)
        print(f"prepare_ship_ais_track: dropped {n} duplicate-timestamp rows")

    if len(df) < 2:
        raise ValueError("Need at least 2 valid timestamps after sort/dedupe")

    if max_rows is not None and len(df) > int(max_rows):
        df = df.iloc[: int(max_rows)].reset_index(drop=True)

    return df


def _interp_angle_deg(t_new: np.ndarray, t_old: np.ndarray, angles_deg: np.ndarray) -> np.ndarray:
    """Interpolate course-over-ground (0..360 deg) via sin/cos."""
    rad = np.radians(np.asarray(angles_deg, dtype=float))
    x = np.cos(rad)
    y = np.sin(rad)
    xi = np.interp(t_new, t_old, x)
    yi = np.interp(t_new, t_old, y)
    out = np.degrees(np.arctan2(yi, xi))
    return np.mod(out, 360.0)


def resample_ship_uniform(
    ship_data: pd.DataFrame,
    dt_sec: float,
    max_rows: Optional[int] = None,
) -> pd.DataFrame:
    """
    Resample AIS rows onto a uniform time grid with spacing dt_sec (seconds).

    Raw AIS often has large irregular gaps (tens of seconds); the UKF/RTL testbench
    typically needs a small effective dt (e.g. 0.04--1 s). Interpolating lat/lon,
    SOG, and COG onto a dense grid yields consistent odometer dt and predictable
    simulation length.
    """
    if dt_sec <= 0:
        raise ValueError("dt_sec must be positive")

    required = ('timestamp', 'latitude', 'longitude', 'cog', 'sog', 'mmsi')
    for col in required:
        if col not in ship_data.columns:
            raise ValueError(f"resample_ship_uniform: missing column '{col}'")

    ship_data = ship_data.sort_values('timestamp').reset_index(drop=True)
    ts = pd.to_datetime(ship_data['timestamp'], utc=False)
    t0 = ts.iloc[0]
    t_rel = (ts - t0).dt.total_seconds().to_numpy(dtype=float)

    t_end = float(t_rel[-1])
    if t_end <= 0:
        raise ValueError("Need at least two distinct timestamps to resample")

    n_uniform = int(np.floor(t_end / dt_sec)) + 1
    t_new = np.arange(0, n_uniform, dtype=float) * dt_sec
    t_new = t_new[t_new <= t_end + 1e-9]
    if max_rows is not None:
        t_new = t_new[: max(1, int(max_rows))]

    lat = ship_data['latitude'].to_numpy(dtype=float)
    lon = ship_data['longitude'].to_numpy(dtype=float)
    cog = ship_data['cog'].to_numpy(dtype=float)
    sog = ship_data['sog'].to_numpy(dtype=float)

    lat_i = np.interp(t_new, t_rel, lat)
    lon_i = np.interp(t_new, t_rel, lon)
    cog_i = _interp_angle_deg(t_new, t_rel, cog)
    sog_i = np.interp(t_new, t_rel, sog)

    ts_new = t0 + pd.to_timedelta(t_new, unit='s')
    mmsi_val = int(ship_data['mmsi'].iloc[0])

    return pd.DataFrame({
        'timestamp': ts_new,
        'latitude': lat_i,
        'longitude': lon_i,
        'cog': cog_i,
        'sog': sog_i,
        'mmsi': mmsi_val,
    })


def process_ais_data(ais_filepath: str, output_dir: str = '.') -> Dict[str, pd.DataFrame]:
    """
    Main function to process AIS data and generate synthetic sensor measurements.
    
    Args:
        ais_filepath: Path to AIS CSV file
        output_dir: Directory to save output files
    
    Returns:
        Dictionary containing sensor DataFrames
    """
    # Load and select ship
    ais_data = load_ais_data(ais_filepath)
    mmsi, ship_data = select_ship_with_most_samples(ais_data)
    ship_data = prepare_ship_ais_track(ship_data, max_rows=None)

    # Generate synthetic sensors
    sensors = generate_synthetic_sensors(ship_data)
    
    # Save to files
    save_measurements(sensors, output_dir)
    
    return sensors


if __name__ == '__main__':
    sensors = process_ais_data('ais.csv')
    print("\nData processing complete!")
