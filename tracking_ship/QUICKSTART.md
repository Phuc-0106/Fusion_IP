# Quick Start Guide

## One-Command Execution

```bash
# Step 1: Run the complete UKF pipeline
python main.py

# Step 2: Generate visualizations
python visualize.py
```

## What Happens

### main.py (5-10 minutes)
- ✅ Loads AIS data (first 1000 records)
- ✅ Generates synthetic sensor measurements (GPS, IMU, Odometer)
- ✅ Initializes Unscented Kalman Filter
- ✅ Runs prediction & update for each measurement
- ✅ Computes RMSE improvement metrics
- ✅ Saves results to `ukf_results.csv`

### visualize.py (1-2 minutes)
- ✅ Plots trajectory comparison
- ✅ Shows position error time-series
- ✅ Creates error statistics plots
- ✅ Displays state estimates over time
- ✅ Generates improvement summary

## Output Files

```
✓ gps_measurement.csv           - Noisy GPS positions
✓ imu_measurement.csv           - Heading and yaw rate
✓ odometer_measurement.csv      - Speed measurements
✓ ground_truth.csv              - True AIS trajectory
✓ ukf_results.csv               - UKF estimates and errors
✓ trajectory_comparison.png     - 2D trajectory plot
✓ position_errors_timeseries.png - X, Y, total error over time
✓ error_statistics.png          - Error distributions & metrics
✓ state_estimates.png           - Speed, heading, position plots
✓ improvement_summary.png       - RMSE comparison & improvement %
```

## Expected Results

```
RMSE Improvement: 40-50%
Processing Time: ~5 minutes
Memory Usage: ~500 MB
```

## Troubleshooting

### Issue: "File not found"
- Ensure `AIS_2024_01_01.csv` is in `d:/tracking_ship/`

### Issue: "ModuleNotFoundError"
```bash
pip install numpy scipy pandas matplotlib
```

### Issue: Slow execution
- Reduce sample_size in main.py:
```python
processor.read_ais_csv(sample_size=500)  # Use 500 records instead
```

### Issue: Memory error
- Reduce sample_size further (use 100-200 records)

## Customization

### Use Different Noise Levels
Edit `data_processing.py`:
```python
processor.gps_position_noise_std = 20.0  # Higher noise
processor.imu_heading_noise_std = np.radians(10.0)  # More noisy IMU
```

### Adjust UKF Filter Parameters
Edit `main.py`:
```python
process_noise_std = np.array([1.0, 1.0, 0.2, 0.1, 0.02])  # Higher process noise
measurement_noise_std = np.array([5, 5, np.radians(2), np.radians(1), 0.2])  # Lower measurement noise
```

### Process More Records
Edit `main.py`:
```python
processor.read_ais_csv(sample_size=5000)  # Use first 5000 records
```

## Next Steps

1. **Analyze Results**
   - Open `ukf_results.csv` in Excel/pandas
   - Compare UKF vs GPS error columns

2. **Modify Parameters**
   - Experiment with different noise levels
   - Try different process noise covariances
   - Adjust UKF alpha parameter for tighter sigma points

3. **Extend System**
   - Add more sensor types
   - Implement adaptive noise estimation
   - Add maneuver detection

4. **Research Applications**
   - Compare with other filters (EKF, particle filter)
   - Test on different ship types
   - Evaluate in various sea conditions

---

For detailed documentation, see `README.md`
