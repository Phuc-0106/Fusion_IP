"""
Visualization Module for Ship Tracking UKF

Generates plots showing:
1. Trajectory comparison (ground truth, GPS, UKF)
2. Position error time series
3. RMSE improvement demonstration

Author: Ship Tracking UKF Project
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Patch


def load_results(results_path: str = 'ukf_results.csv') -> pd.DataFrame:
    """Load UKF results from CSV."""
    return pd.read_csv(results_path)


def plot_trajectories(results: pd.DataFrame, save_path: str = None):
    """
    Plot trajectory comparison: Ground truth, GPS, and UKF estimate.
    """
    fig, ax = plt.subplots(figsize=(12, 10))
    
    # Ground truth trajectory
    ax.plot(results['true_x'], results['true_y'], 
            'g-', linewidth=2, label='Ground Truth (AIS)', zorder=3)
    
    # GPS measurements (noisy)
    ax.scatter(results['gps_x'], results['gps_y'], 
               c='red', s=15, alpha=0.5, label='GPS Measurements (Noisy)', zorder=1)
    
    # UKF estimate
    ax.plot(results['est_x'], results['est_y'], 
            'b-', linewidth=2, label='UKF Estimate (Fused)', zorder=2)
    
    # Mark start and end points
    ax.scatter(results['true_x'].iloc[0], results['true_y'].iloc[0], 
               c='green', s=200, marker='o', edgecolors='black', 
               linewidths=2, label='Start', zorder=4)
    ax.scatter(results['true_x'].iloc[-1], results['true_y'].iloc[-1], 
               c='purple', s=200, marker='s', edgecolors='black', 
               linewidths=2, label='End', zorder=4)
    
    ax.set_xlabel('East Position (m)', fontsize=12)
    ax.set_ylabel('North Position (m)', fontsize=12)
    ax.set_title('Ship Trajectory: Ground Truth vs GPS vs UKF Estimate', fontsize=14)
    ax.legend(loc='best', fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_aspect('equal')
    
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Saved trajectory plot to {save_path}")
    
    return fig, ax


def plot_position_errors(results: pd.DataFrame, save_path: str = None):
    """
    Plot position error time series comparing GPS and UKF.
    """
    fig, axes = plt.subplots(2, 1, figsize=(14, 8), sharex=True)
    
    time_idx = np.arange(len(results))
    
    # Top plot: Error comparison
    ax1 = axes[0]
    ax1.plot(time_idx, results['gps_error'], 'r-', alpha=0.7, 
             linewidth=1, label='GPS Error')
    ax1.plot(time_idx, results['ukf_error'], 'b-', alpha=0.9, 
             linewidth=1.5, label='UKF Error')
    
    # Add RMSE lines
    gps_rmse = np.sqrt(np.mean(results['gps_error']**2))
    ukf_rmse = np.sqrt(np.mean(results['ukf_error']**2))
    
    ax1.axhline(gps_rmse, color='red', linestyle='--', linewidth=2, 
                label=f'GPS RMSE: {gps_rmse:.2f}m')
    ax1.axhline(ukf_rmse, color='blue', linestyle='--', linewidth=2, 
                label=f'UKF RMSE: {ukf_rmse:.2f}m')
    
    ax1.set_ylabel('Position Error (m)', fontsize=12)
    ax1.set_title('Position Error Over Time: GPS vs UKF', fontsize=14)
    ax1.legend(loc='upper right', fontsize=10)
    ax1.grid(True, alpha=0.3)
    ax1.set_ylim(bottom=0)
    
    # Bottom plot: Error improvement
    ax2 = axes[1]
    improvement = results['gps_error'] - results['ukf_error']
    
    colors = ['green' if x > 0 else 'red' for x in improvement]
    ax2.bar(time_idx, improvement, color=colors, alpha=0.6, width=1.0)
    ax2.axhline(0, color='black', linewidth=1)
    
    mean_improvement = np.mean(improvement)
    ax2.axhline(mean_improvement, color='blue', linestyle='--', linewidth=2,
                label=f'Mean Improvement: {mean_improvement:.2f}m')
    
    ax2.set_xlabel('Time Step', fontsize=12)
    ax2.set_ylabel('Error Reduction (m)', fontsize=12)
    ax2.set_title('UKF Error Improvement (Positive = UKF Better)', fontsize=14)
    ax2.legend(loc='upper right', fontsize=10)
    ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Saved error plot to {save_path}")
    
    return fig, axes


def plot_rmse_comparison(results: pd.DataFrame, save_path: str = None):
    """
    Bar chart comparing GPS and UKF RMSE.
    """
    gps_rmse = np.sqrt(np.mean(results['gps_error']**2))
    ukf_rmse = np.sqrt(np.mean(results['ukf_error']**2))
    improvement = (gps_rmse - ukf_rmse) / gps_rmse * 100
    
    fig, ax = plt.subplots(figsize=(8, 6))
    
    methods = ['GPS Only', 'UKF (Sensor Fusion)']
    rmse_values = [gps_rmse, ukf_rmse]
    colors = ['#e74c3c', '#3498db']
    
    bars = ax.bar(methods, rmse_values, color=colors, edgecolor='black', linewidth=2)
    
    # Add value labels on bars
    for bar, val in zip(bars, rmse_values):
        height = bar.get_height()
        ax.annotate(f'{val:.2f}m',
                    xy=(bar.get_x() + bar.get_width() / 2, height),
                    xytext=(0, 5),
                    textcoords="offset points",
                    ha='center', va='bottom', fontsize=14, fontweight='bold')
    
    # Add improvement arrow
    ax.annotate('', xy=(1, ukf_rmse), xytext=(1, gps_rmse),
                arrowprops=dict(arrowstyle='->', color='green', lw=3))
    ax.annotate(f'{improvement:.1f}% better',
                xy=(1.25, (gps_rmse + ukf_rmse) / 2),
                fontsize=12, color='green', fontweight='bold')
    
    ax.set_ylabel('Position RMSE (meters)', fontsize=12)
    ax.set_title('Position Accuracy: GPS vs UKF Sensor Fusion', fontsize=14)
    ax.set_ylim(0, max(rmse_values) * 1.3)
    ax.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Saved RMSE comparison to {save_path}")
    
    return fig, ax


def plot_error_histogram(results: pd.DataFrame, save_path: str = None):
    """
    Histogram of position errors for GPS and UKF.
    """
    fig, ax = plt.subplots(figsize=(10, 6))
    
    bins = np.linspace(0, max(results['gps_error'].max(), results['ukf_error'].max()) * 1.1, 40)
    
    ax.hist(results['gps_error'], bins=bins, alpha=0.6, color='red', 
            label='GPS Error', edgecolor='darkred')
    ax.hist(results['ukf_error'], bins=bins, alpha=0.6, color='blue', 
            label='UKF Error', edgecolor='darkblue')
    
    # Add statistics
    gps_mean = results['gps_error'].mean()
    ukf_mean = results['ukf_error'].mean()
    
    ax.axvline(gps_mean, color='red', linestyle='--', linewidth=2,
               label=f'GPS Mean: {gps_mean:.2f}m')
    ax.axvline(ukf_mean, color='blue', linestyle='--', linewidth=2,
               label=f'UKF Mean: {ukf_mean:.2f}m')
    
    ax.set_xlabel('Position Error (m)', fontsize=12)
    ax.set_ylabel('Frequency', fontsize=12)
    ax.set_title('Distribution of Position Errors', fontsize=14)
    ax.legend(loc='upper right', fontsize=10)
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Saved histogram to {save_path}")
    
    return fig, ax


def create_summary_figure(results: pd.DataFrame, save_path: str = None):
    """
    Create a comprehensive summary figure with all plots.
    """
    fig = plt.figure(figsize=(16, 12))
    
    # Trajectory plot (top left, larger)
    ax1 = fig.add_subplot(2, 2, 1)
    ax1.plot(results['true_x'], results['true_y'], 'g-', linewidth=2, label='Ground Truth')
    ax1.scatter(results['gps_x'], results['gps_y'], c='red', s=10, alpha=0.4, label='GPS')
    ax1.plot(results['est_x'], results['est_y'], 'b-', linewidth=2, label='UKF')
    ax1.scatter(results['true_x'].iloc[0], results['true_y'].iloc[0], 
                c='green', s=150, marker='o', edgecolors='black', zorder=5)
    ax1.set_xlabel('East (m)')
    ax1.set_ylabel('North (m)')
    ax1.set_title('Ship Trajectory Comparison')
    ax1.legend(loc='best')
    ax1.grid(True, alpha=0.3)
    ax1.set_aspect('equal')
    
    # RMSE comparison (top right)
    ax2 = fig.add_subplot(2, 2, 2)
    gps_rmse = np.sqrt(np.mean(results['gps_error']**2))
    ukf_rmse = np.sqrt(np.mean(results['ukf_error']**2))
    bars = ax2.bar(['GPS Only', 'UKF Fused'], [gps_rmse, ukf_rmse], 
                   color=['#e74c3c', '#3498db'], edgecolor='black')
    for bar, val in zip(bars, [gps_rmse, ukf_rmse]):
        ax2.annotate(f'{val:.2f}m', xy=(bar.get_x() + bar.get_width()/2, val),
                     xytext=(0, 5), textcoords="offset points", ha='center', fontweight='bold')
    ax2.set_ylabel('Position RMSE (m)')
    ax2.set_title(f'RMSE Comparison ({(gps_rmse-ukf_rmse)/gps_rmse*100:.1f}% improvement)')
    ax2.grid(True, alpha=0.3, axis='y')
    
    # Error time series (bottom left)
    ax3 = fig.add_subplot(2, 2, 3)
    time_idx = np.arange(len(results))
    ax3.plot(time_idx, results['gps_error'], 'r-', alpha=0.7, linewidth=1, label='GPS Error')
    ax3.plot(time_idx, results['ukf_error'], 'b-', alpha=0.9, linewidth=1.5, label='UKF Error')
    ax3.axhline(gps_rmse, color='red', linestyle='--', alpha=0.7)
    ax3.axhline(ukf_rmse, color='blue', linestyle='--', alpha=0.7)
    ax3.set_xlabel('Time Step')
    ax3.set_ylabel('Position Error (m)')
    ax3.set_title('Position Error Over Time')
    ax3.legend(loc='upper right')
    ax3.grid(True, alpha=0.3)
    
    # Error histogram (bottom right)
    ax4 = fig.add_subplot(2, 2, 4)
    bins = np.linspace(0, max(results['gps_error'].max(), results['ukf_error'].max()) * 1.1, 30)
    ax4.hist(results['gps_error'], bins=bins, alpha=0.6, color='red', label='GPS')
    ax4.hist(results['ukf_error'], bins=bins, alpha=0.6, color='blue', label='UKF')
    ax4.axvline(results['gps_error'].mean(), color='red', linestyle='--', linewidth=2)
    ax4.axvline(results['ukf_error'].mean(), color='blue', linestyle='--', linewidth=2)
    ax4.set_xlabel('Position Error (m)')
    ax4.set_ylabel('Frequency')
    ax4.set_title('Error Distribution')
    ax4.legend(loc='upper right')
    ax4.grid(True, alpha=0.3)
    
    plt.suptitle('UKF Ship Tracking: Sensor Fusion Performance Summary', fontsize=16, y=1.02)
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Saved summary figure to {save_path}")
    
    return fig


def plot_sensor_noise_analysis(save_path: str = None):
    """
    Visualize noise characteristics for each sensor over time.
    Shows measured vs ground truth values with noise magnitude.
    """
    # Load sensor data
    gps_data = pd.read_csv('gps_measurement.csv')
    imu_data = pd.read_csv('imu_measurement.csv')
    odo_data = pd.read_csv('odometer_measurement.csv')
    
    fig = plt.figure(figsize=(16, 12))
    time_idx = np.arange(len(gps_data))
    
    # ============ GPS Noise (Position) ============
    ax1 = fig.add_subplot(4, 2, 1)
    gps_x_noise = gps_data['x'] - gps_data['x_true']
    gps_y_noise = gps_data['y'] - gps_data['y_true']
    gps_total_noise = np.sqrt(gps_x_noise**2 + gps_y_noise**2)
    
    ax1.plot(time_idx, gps_total_noise, 'r-', linewidth=1.5, label='GPS Position Noise')
    ax1.axhline(np.mean(gps_total_noise), color='red', linestyle='--', 
                linewidth=2, label=f'Mean: {np.mean(gps_total_noise):.2f}m')
    ax1.axhline(np.std(gps_total_noise), color='orange', linestyle=':', 
                linewidth=2, label=f'Std Dev: {np.std(gps_total_noise):.2f}m')
    ax1.set_ylabel('Position Noise (m)', fontsize=11)
    ax1.set_title('GPS Sensor: Position Noise Over Time', fontsize=12, fontweight='bold')
    ax1.legend(loc='upper right', fontsize=9)
    ax1.grid(True, alpha=0.3)
    ax1.set_xlabel('Time Step')
    
    # GPS X and Y components
    ax2 = fig.add_subplot(4, 2, 2)
    ax2.plot(time_idx, gps_x_noise, 'r-', alpha=0.7, linewidth=1, label='X (East) Noise')
    ax2.plot(time_idx, gps_y_noise, 'orange', alpha=0.7, linewidth=1, label='Y (North) Noise')
    ax2.axhline(0, color='black', linewidth=0.5)
    ax2.set_ylabel('Component Noise (m)', fontsize=11)
    ax2.set_title('GPS: X and Y Position Noise Components', fontsize=12, fontweight='bold')
    ax2.legend(loc='upper right', fontsize=9)
    ax2.grid(True, alpha=0.3)
    ax2.set_xlabel('Time Step')
    
    # ============ IMU Heading Noise ============
    ax3 = fig.add_subplot(4, 2, 3)
    imu_heading_noise = imu_data['heading'] - imu_data['heading_true']
    # Normalize heading difference to [-pi, pi]
    imu_heading_noise = np.arctan2(np.sin(imu_heading_noise), np.cos(imu_heading_noise))
    imu_heading_noise_deg = np.degrees(imu_heading_noise)
    
    ax3.plot(time_idx, imu_heading_noise_deg, 'g-', linewidth=1.5, label='Heading Noise')
    ax3.axhline(np.mean(imu_heading_noise_deg), color='green', linestyle='--', 
                linewidth=2, label=f'Mean: {np.mean(imu_heading_noise_deg):.3f}°')
    ax3.axhline(np.std(imu_heading_noise_deg), color='lightgreen', linestyle=':', 
                linewidth=2, label=f'Std Dev: {np.std(imu_heading_noise_deg):.3f}°')
    ax3.set_ylabel('Heading Noise (degrees)', fontsize=11)
    ax3.set_title('IMU Sensor: Heading Noise Over Time', fontsize=12, fontweight='bold')
    ax3.legend(loc='upper right', fontsize=9)
    ax3.grid(True, alpha=0.3)
    ax3.set_xlabel('Time Step')
    
    # ============ IMU Yaw Rate Noise ============
    ax4 = fig.add_subplot(4, 2, 4)
    imu_yawrate_noise = imu_data['yaw_rate'] - imu_data['yaw_rate_true']
    imu_yawrate_noise_deg = np.degrees(imu_yawrate_noise)
    
    ax4.plot(time_idx, imu_yawrate_noise_deg, 'b-', linewidth=1.5, label='Yaw Rate Noise')
    ax4.axhline(np.mean(imu_yawrate_noise_deg), color='blue', linestyle='--', 
                linewidth=2, label=f'Mean: {np.mean(imu_yawrate_noise_deg):.4f}°/s')
    ax4.axhline(np.std(imu_yawrate_noise_deg), color='lightblue', linestyle=':', 
                linewidth=2, label=f'Std Dev: {np.std(imu_yawrate_noise_deg):.4f}°/s')
    ax4.axhline(0, color='black', linewidth=0.5)
    ax4.set_ylabel('Yaw Rate Noise (deg/s)', fontsize=11)
    ax4.set_title('IMU Sensor: Yaw Rate Noise Over Time', fontsize=12, fontweight='bold')
    ax4.legend(loc='upper right', fontsize=9)
    ax4.grid(True, alpha=0.3)
    ax4.set_xlabel('Time Step')
    
    # ============ Odometer Speed Noise ============
    ax5 = fig.add_subplot(4, 2, 5)
    odo_speed_noise = odo_data['speed'] - odo_data['speed_true']
    
    ax5.plot(time_idx, odo_speed_noise, 'purple', linewidth=1.5, label='Speed Noise')
    ax5.axhline(np.mean(odo_speed_noise), color='purple', linestyle='--', 
                linewidth=2, label=f'Mean: {np.mean(odo_speed_noise):.3f}m/s')
    ax5.axhline(np.std(odo_speed_noise), color='plum', linestyle=':', 
                linewidth=2, label=f'Std Dev: {np.std(odo_speed_noise):.3f}m/s')
    ax5.axhline(0, color='black', linewidth=0.5)
    ax5.set_ylabel('Speed Noise (m/s)', fontsize=11)
    ax5.set_title('Odometer Sensor: Speed Noise Over Time', fontsize=12, fontweight='bold')
    ax5.legend(loc='upper right', fontsize=9)
    ax5.grid(True, alpha=0.3)
    ax5.set_xlabel('Time Step')
    
    # ============ GPS Measured vs Ground Truth ============
    ax6 = fig.add_subplot(4, 2, 6)
    ax6_twin = ax6.twinx()
    
    line1 = ax6.plot(time_idx, gps_data['x_true'], 'g--', linewidth=2, 
                     label='Ground Truth X', alpha=0.8)
    line2 = ax6.plot(time_idx, gps_data['x'], 'r-', linewidth=1, 
                     label='Measured X', alpha=0.6)
    ax6.set_xlabel('Time Step')
    ax6.set_ylabel('X Position (m)', fontsize=11, color='red')
    ax6.tick_params(axis='y', labelcolor='red')
    ax6.grid(True, alpha=0.3)
    ax6.set_title('GPS: X Position Measured vs Ground Truth', fontsize=12, fontweight='bold')
    
    # Add legend
    lines = line1 + line2
    labels = [l.get_label() for l in lines]
    ax6.legend(lines, labels, loc='upper left', fontsize=9)
    
    # ============ IMU Measured vs Ground Truth ============
    ax7 = fig.add_subplot(4, 2, 7)
    heading_deg_true = np.degrees(imu_data['heading_true'])
    heading_deg_measured = np.degrees(imu_data['heading'])
    
    line1 = ax7.plot(time_idx, heading_deg_true, 'g--', linewidth=2, 
                     label='Ground Truth', alpha=0.8)
    line2 = ax7.plot(time_idx, heading_deg_measured, 'b-', linewidth=1, 
                     label='Measured', alpha=0.6)
    ax7.set_xlabel('Time Step')
    ax7.set_ylabel('Heading (degrees)', fontsize=11)
    ax7.grid(True, alpha=0.3)
    ax7.set_title('IMU: Heading Measured vs Ground Truth', fontsize=12, fontweight='bold')
    
    lines = line1 + line2
    labels = [l.get_label() for l in lines]
    ax7.legend(lines, labels, loc='best', fontsize=9)
    
    # ============ Odometer Measured vs Ground Truth ============
    ax8 = fig.add_subplot(4, 2, 8)
    line1 = ax8.plot(time_idx, odo_data['speed_true'], 'g--', linewidth=2, 
                     label='Ground Truth', alpha=0.8)
    line2 = ax8.plot(time_idx, odo_data['speed'], 'purple', linewidth=1, 
                     label='Measured', alpha=0.6)
    ax8.set_xlabel('Time Step')
    ax8.set_ylabel('Speed (m/s)', fontsize=11)
    ax8.grid(True, alpha=0.3)
    ax8.set_title('Odometer: Speed Measured vs Ground Truth', fontsize=12, fontweight='bold')
    
    lines = line1 + line2
    labels = [l.get_label() for l in lines]
    ax8.legend(lines, labels, loc='best', fontsize=9)
    
    plt.suptitle('Sensor Noise Analysis: Measured vs Ground Truth', 
                 fontsize=16, fontweight='bold', y=0.995)
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Saved sensor noise analysis to {save_path}")
    
    return fig


def main():
    """Generate all visualization plots."""
    print("=" * 50)
    print("Generating Visualization Plots")
    print("=" * 50)
    
    # Load results
    results = load_results('ukf_results.csv')
    print(f"Loaded {len(results)} data points")
    
    # Generate plots
    plot_trajectories(results, 'trajectory_comparison.png')
    plot_position_errors(results, 'position_errors.png')
    plot_rmse_comparison(results, 'rmse_comparison.png')
    plot_error_histogram(results, 'error_histogram.png')
    create_summary_figure(results, 'summary_figure.png')
    
    # Generate sensor noise analysis
    plot_sensor_noise_analysis('sensor_noise_analysis.png')
    
    print("\n" + "=" * 50)
    print("All plots generated successfully!")
    print("=" * 50)
    
    # Show plots
    plt.show()


if __name__ == '__main__':
    main()
