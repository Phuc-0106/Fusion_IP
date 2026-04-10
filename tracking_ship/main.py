"""
Main Script for Ship Tracking using Unscented Kalman Filter

This script orchestrates the UKF-based ship tracking pipeline:
1. Process AIS data and generate synthetic sensor measurements
2. Initialize and run UKF with sensor fusion
3. Compute performance metrics (RMSE)

Supports multiple tuning cases to demonstrate P/Q/R effects.

Author: Ship Tracking UKF Project
"""

import numpy as np
import pandas as pd
from data_processing import process_ais_data, GPS_NOISE_STD, IMU_HEADING_NOISE_STD, IMU_YAW_RATE_NOISE_STD, ODOMETER_NOISE_STD
from ukf import UnscentedKalmanFilter


# =============================================================================
# UKF TUNING CASES
# =============================================================================
# Each case defines P0, Q, R scaling factors to demonstrate different behaviors

TUNING_CASES = {
    0: {
        "name": "Nominal / Baseline",
        "description": "Balanced trust between model and sensors",
        "P0_scale": 1.0,
        "Q_scale": 1.0,
        "R_scale": 1.0,
    },
    1: {
        "name": "Model-driven",
        "description": "Trust model more, doubt sensors (small Q, large R)",
        "P0_scale": 1.0,
        "Q_scale": 0.1,   # Small process noise = trust model
        "R_scale": 5.0,   # Large measurement noise = doubt sensors
    },
    2: {
        "name": "Measurement-driven",
        "description": "Doubt model, trust sensors (large Q, small R)",
        "P0_scale": 1.0,
        "Q_scale": 10.0,  # Large process noise = doubt model
        "R_scale": 0.2,   # Small measurement noise = trust sensors
    },
    3: {
        "name": "Over-confident",
        "description": "Stress test: very small P, Q, R (filter thinks everything is precise)",
        "P0_scale": 0.01,
        "Q_scale": 0.01,
        "R_scale": 0.01,
    },
    4: {
        "name": "Under-confident",
        "description": "Large P, Q, R (filter is very uncertain about everything)",
        "P0_scale": 10.0,
        "Q_scale": 10.0,
        "R_scale": 10.0,
    },
    5: {
        "name": "GPS degraded (urban canyon)",
        "description": "High GPS noise, normal IMU/odometer (simulates signal blockage)",
        "P0_scale": 1.0,
        "Q_scale": 1.0,
        "R_scale": 1.0,
        "R_gps_scale": 10.0,  # GPS specifically degraded
    },
}


def get_tuning_params(case_id: int) -> dict:
    """Get P, Q, R matrices for a specific tuning case."""
    case = TUNING_CASES[case_id]
    
    # Base values
    P0_base = np.diag([
        GPS_NOISE_STD**2,
        GPS_NOISE_STD**2,
        ODOMETER_NOISE_STD**2,
        IMU_HEADING_NOISE_STD**2,
        IMU_YAW_RATE_NOISE_STD**2
    ])
    
    Q_base = np.diag([
        0.5,    # x position
        0.5,    # y position
        0.1,    # speed
        0.01,   # heading
        0.001   # yaw rate
    ])
    
    R_gps_base = np.diag([GPS_NOISE_STD**2, GPS_NOISE_STD**2])
    R_imu_base = np.diag([IMU_HEADING_NOISE_STD**2, IMU_YAW_RATE_NOISE_STD**2])
    R_odo_base = ODOMETER_NOISE_STD**2
    
    # Apply scaling
    P0 = P0_base * case["P0_scale"]
    Q = Q_base * case["Q_scale"]
    
    # Handle GPS-specific scaling for Case 5
    gps_scale = case.get("R_gps_scale", case["R_scale"])
    R_gps = R_gps_base * gps_scale
    R_imu = R_imu_base * case["R_scale"]
    R_odo = R_odo_base * case["R_scale"]
    
    return {
        "P0": P0,
        "Q": Q,
        "R_gps": R_gps,
        "R_imu": R_imu,
        "R_odo": R_odo,
        "name": case["name"],
        "description": case["description"]
    }


def compute_rmse(estimated: np.ndarray, ground_truth: np.ndarray) -> float:
    """Compute Root Mean Square Error."""
    return np.sqrt(np.mean((estimated - ground_truth)**2))


def compute_position_rmse(est_x: np.ndarray, est_y: np.ndarray,
                          true_x: np.ndarray, true_y: np.ndarray) -> float:
    """Compute 2D position RMSE."""
    errors = np.sqrt((est_x - true_x)**2 + (est_y - true_y)**2)
    return np.sqrt(np.mean(errors**2))


def run_ukf_tracking(sensors: dict, case_id: int = 0) -> dict:
    """
    Run UKF tracking with sensor fusion.
    
    Args:
        sensors: Dictionary containing GPS, IMU, and odometer DataFrames
        case_id: Tuning case ID (0-5)
    
    Returns:
        Dictionary containing results and metrics
    """
    gps_data = sensors['gps']
    imu_data = sensors['imu']
    odo_data = sensors['odometer']
    
    n_steps = len(gps_data)
    
    # Get tuning parameters for this case
    params = get_tuning_params(case_id)
    print(f"\n  Case {case_id}: {params['name']}")
    print(f"  {params['description']}")
    
    # Initialize UKF
    ukf = UnscentedKalmanFilter(dim_x=5, alpha=0.1, beta=2.0, kappa=0.0)
    
    # Initial state from first measurements
    x0 = np.array([
        gps_data['x'].iloc[0],
        gps_data['y'].iloc[0],
        odo_data['speed'].iloc[0],
        imu_data['heading'].iloc[0],
        imu_data['yaw_rate'].iloc[0]
    ])
    
    # Set P0, Q from tuning case
    ukf.set_initial_state(x0, params["P0"])
    ukf.set_process_noise(params["Q"])
    
    # Measurement noise covariances from tuning case
    R_gps = params["R_gps"]
    R_imu = params["R_imu"]
    R_odo = params["R_odo"]
    
    # Storage for results
    est_x = np.zeros(n_steps)
    est_y = np.zeros(n_steps)
    est_speed = np.zeros(n_steps)
    est_heading = np.zeros(n_steps)
    est_yaw_rate = np.zeros(n_steps)
    
    # Store initial estimate
    state = ukf.get_state()
    est_x[0] = state[0]
    est_y[0] = state[1]
    est_speed[0] = state[2]
    est_heading[0] = state[3]
    est_yaw_rate[0] = state[4]
    
    print("\nRunning UKF with sensor fusion...")
    print("-" * 40)
    
    # Main UKF loop
    for k in range(1, n_steps):
        # Get time step
        dt = odo_data['dt'].iloc[k]
        if dt <= 0:
            dt = 1.0  # Default time step
        
        # Prediction step
        ukf.predict(dt)
        
        # GPS update
        z_gps = np.array([gps_data['x'].iloc[k], gps_data['y'].iloc[k]])
        ukf.update_gps(z_gps, R_gps)
        
        # IMU update
        z_imu = np.array([imu_data['heading'].iloc[k], imu_data['yaw_rate'].iloc[k]])
        ukf.update_imu(z_imu, R_imu)
        
        # Odometer update
        z_odo = odo_data['speed'].iloc[k]
        ukf.update_odometer(z_odo, R_odo)
        
        # Store estimates
        state = ukf.get_state()
        est_x[k] = state[0]
        est_y[k] = state[1]
        est_speed[k] = state[2]
        est_heading[k] = state[3]
        est_yaw_rate[k] = state[4]
        
        # Progress update
        if k % 100 == 0:
            print(f"  Processed {k}/{n_steps} steps")
    
    print(f"  Processed {n_steps}/{n_steps} steps")
    print("-" * 40)
    
    # Extract ground truth
    true_x = gps_data['x_true'].values
    true_y = gps_data['y_true'].values
    
    # Compute metrics
    gps_rmse = compute_position_rmse(
        gps_data['x'].values, gps_data['y'].values,
        true_x, true_y
    )
    
    ukf_rmse = compute_position_rmse(est_x, est_y, true_x, true_y)
    
    improvement = (gps_rmse - ukf_rmse) / gps_rmse * 100
    
    # Position errors over time
    gps_errors = np.sqrt((gps_data['x'].values - true_x)**2 + 
                         (gps_data['y'].values - true_y)**2)
    ukf_errors = np.sqrt((est_x - true_x)**2 + (est_y - true_y)**2)
    
    params = get_tuning_params(case_id)
    results = {
        'est_x': est_x,
        'est_y': est_y,
        'est_speed': est_speed,
        'est_heading': est_heading,
        'est_yaw_rate': est_yaw_rate,
        'true_x': true_x,
        'true_y': true_y,
        'true_speed': odo_data['speed_true'].values,
        'true_heading': imu_data['heading_true'].values,
        'true_yaw_rate': imu_data['yaw_rate_true'].values,
        'gps_x': gps_data['x'].values,
        'gps_y': gps_data['y'].values,
        'gps_rmse': gps_rmse,
        'ukf_rmse': ukf_rmse,
        'improvement': improvement,
        'gps_errors': gps_errors,
        'ukf_errors': ukf_errors,
        'timestamps': gps_data['timestamp'].values,
        'dt': odo_data['dt'].values,
        'case_id': case_id,
        'case_name': params['name']
    }
    
    return results


def print_performance_metrics(results: dict):
    """Print performance metrics summary."""
    print("\n" + "=" * 50)
    print("PERFORMANCE METRICS")
    print("=" * 50)
    print(f"GPS-only Position RMSE:     {results['gps_rmse']:.3f} meters")
    print(f"UKF Fused Position RMSE:    {results['ukf_rmse']:.3f} meters")
    print(f"Improvement:                {results['improvement']:.1f}%")
    print("-" * 50)
    print(f"Max GPS Error:              {np.max(results['gps_errors']):.3f} meters")
    print(f"Max UKF Error:              {np.max(results['ukf_errors']):.3f} meters")
    print(f"Mean GPS Error:             {np.mean(results['gps_errors']):.3f} meters")
    print(f"Mean UKF Error:             {np.mean(results['ukf_errors']):.3f} meters")
    print("=" * 50)


def save_results(results: dict, output_path: str = 'ukf_results.csv'):
    """Save UKF results to CSV (full 5-state vector + ground truth)."""
    df = pd.DataFrame({
        'timestamp': results['timestamps'],
        'est_x': results['est_x'],
        'est_y': results['est_y'],
        'est_speed': results['est_speed'],
        'est_heading': results['est_heading'],
        'est_yaw_rate': results['est_yaw_rate'],
        'true_x': results['true_x'],
        'true_y': results['true_y'],
        'true_speed': results['true_speed'],
        'true_heading': results['true_heading'],
        'true_yaw_rate': results['true_yaw_rate'],
        'gps_x': results['gps_x'],
        'gps_y': results['gps_y'],
        'dt': results['dt'],
        'gps_error': results['gps_errors'],
        'ukf_error': results['ukf_errors']
    })
    df.to_csv(output_path, index=False)
    print(f"Results saved to {output_path}")


def run_all_cases(sensors: dict) -> dict:
    """Run all tuning cases and compare results."""
    all_results = {}
    
    print("\n" + "=" * 60)
    print("RUNNING ALL TUNING CASES")
    print("=" * 60)
    
    for case_id in range(6):
        results = run_ukf_tracking(sensors, case_id)
        all_results[case_id] = results
        save_results(results, f'ukf_results_case{case_id}.csv')
    
    # Print comparison summary
    print("\n" + "=" * 60)
    print("TUNING CASES COMPARISON SUMMARY")
    print("=" * 60)
    print(f"{'Case':<6} {'Name':<30} {'GPS RMSE':>10} {'UKF RMSE':>10} {'Improve':>10}")
    print("-" * 60)
    
    gps_rmse = all_results[0]['gps_rmse']  # Same for all cases
    for case_id, results in all_results.items():
        print(f"{case_id:<6} {results['case_name']:<30} {gps_rmse:>10.2f}m {results['ukf_rmse']:>10.2f}m {results['improvement']:>9.1f}%")
    
    print("=" * 60)
    
    return all_results


def main(case_id: int = None):
    """
    Main entry point.
    
    Args:
        case_id: Specific case to run (0-5), or None to run all cases
    """
    print("=" * 60)
    print("Ship Tracking using Unscented Kalman Filter")
    print("=" * 60)
    
    # Step 1: Process AIS data
    print("\n[Step 1] Processing AIS data...")
    sensors = process_ais_data('AIS_2024_01_01.csv')
    
    # Step 2: Run UKF tracking
    print("\n[Step 2] Running UKF tracking...")
    
    if case_id is not None:
        # Run single case
        results = run_ukf_tracking(sensors, case_id)
        print_performance_metrics(results)
        save_results(results)
        return results
    else:
        # Run all cases
        all_results = run_all_cases(sensors)
        print("\nTracking complete! Run visualize.py to see plots.")
        return all_results


if __name__ == '__main__':
    import sys
    
    # Parse command line argument for case selection
    if len(sys.argv) > 1:
        case_id = int(sys.argv[1])
        print(f"Running Case {case_id} only...")
        results = main(case_id)
    else:
        print("Running all cases (0-5)...")
        results = main()
