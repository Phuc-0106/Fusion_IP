"""
Data Processing Module for Ship Tracking UKF

This module processes AIS (Automatic Identification System) data and generates
synthetic sensor measurements for UKF-based ship tracking.

IMPORTANT ASSUMPTIONS:
----------------------
1. AIS data provides ground-truth ship positions and kinematics
2. Synthetic sensors are SIMULATED from AIS data with added Gaussian noise:
   - GPS: Derived from AIS lat/lon with position noise
   - IMU: Derived from AIS COG (Course Over Ground) with heading/yaw rate noise
   - Odometer: Derived from AIS SOG (Speed Over Ground) with speed noise
3. These synthetic measurements simulate real-world sensor imperfections
4. The ship with most samples is selected to ensure sufficient data for
   meaningful UKF performance evaluation and statistical significance

Author: Ship Tracking UKF Project
"""

import numpy as np
import pandas as pd
from typing import Tuple, Dict

# Sensor noise standard deviations (realistic degraded conditions)
GPS_NOISE_STD = 25.0        # meters (degraded GPS with multipath)
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
    """Compute time differences between consecutive measurements in seconds."""
    # Assume timestamps are in seconds or convert if needed
    if timestamps.dtype == 'object' or np.issubdtype(timestamps.dtype, np.datetime64):
        timestamps = pd.to_datetime(timestamps)
        dt = np.diff(timestamps).astype('timedelta64[s]').astype(float)
    else:
        dt = np.diff(timestamps)
    
    return np.concatenate([[0], dt])


def generate_synthetic_sensors(ship_data: pd.DataFrame) -> Dict[str, pd.DataFrame]:
    """
    Generate synthetic sensor measurements from AIS ground-truth data.
    
    SYNTHETIC SENSOR GENERATION:
    ----------------------------
    These sensors are SIMULATED to demonstrate UKF sensor fusion:
    
    1. GPS: True position + Gaussian noise
       - Simulates typical GPS accuracy (~10m CEP)
    
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
    
    # GPS measurements (position with noise + random outages)
    gps_x = x_true + np.random.normal(0, GPS_NOISE_STD, len(x_true))
    gps_y = y_true + np.random.normal(0, GPS_NOISE_STD, len(y_true))
    
    # Simulate GPS outages (use last known position with large jump)
    outage_mask = np.random.random(len(x_true)) < GPS_OUTAGE_PROBABILITY
    outage_indices = np.where(outage_mask)[0]
    for idx in outage_indices:
        # During outage, GPS jumps to random position (simulates re-acquisition)
        gps_x[idx] += np.random.normal(0, GPS_NOISE_STD * 3)
        gps_y[idx] += np.random.normal(0, GPS_NOISE_STD * 3)
    
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
    
    # Generate synthetic sensors
    sensors = generate_synthetic_sensors(ship_data)
    
    # Save to files
    save_measurements(sensors, output_dir)
    
    return sensors


if __name__ == '__main__':
    sensors = process_ais_data('ais.csv')
    print("\nData processing complete!")
