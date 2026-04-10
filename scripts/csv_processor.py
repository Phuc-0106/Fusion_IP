#!/usr/bin/env python3
"""
Fusion IP CSV Processor - Convert multi-sensor CSV logs to UKF test sequences

This script processes 3 CSV files (GPS, IMU, Odometry) with different timestamps
and frequencies, normalizes them to a unified timeline, and generates test data
for the UVM route_csv test.

Usage:
    python csv_processor.py --config config.yaml --output fused_timeline.csv
    python csv_processor.py --gps gps.csv --imu imu.csv --odom odom.csv \\
                            --output fused_timeline.csv --hz 25
"""

import argparse
import yaml
import csv
import sys
import math
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict
from datetime import datetime
import json

import numpy as np
from scipy.interpolate import interp1d


@dataclass
class Point2D:
    """Represents a 2D point (x, y in meters)."""
    x: float
    y: float


@dataclass
class IMUData:
    """IMU measurement: heading (rad) and yaw rate (rad/s)."""
    psi: float      # Heading in radians
    psi_dot: float  # Yaw rate in rad/s


@dataclass
class OdomData:
    """Odometry measurement: velocity in m/s."""
    v: float        # Velocity in m/s


@dataclass
class FusedMeasurement:
    """Complete measurement at a single timestamp."""
    timestamp: float
    gps_pos: Optional[Point2D]
    imu: Optional[IMUData]
    odom: Optional[OdomData]
    gps_valid: bool
    imu_valid: bool
    odom_valid: bool

    def to_dict(self):
        """Convert to dictionary for CSV output."""
        return {
            'timestamp_s': self.timestamp,
            'gps_x_m': self.gps_pos.x if self.gps_pos and self.gps_valid else None,
            'gps_y_m': self.gps_pos.y if self.gps_pos and self.gps_valid else None,
            'imu_psi_rad': self.imu.psi if self.imu and self.imu_valid else None,
            'imu_psidot_radps': self.imu.psi_dot if self.imu and self.imu_valid else None,
            'odom_v_mps': self.odom.v if self.odom and self.odom_valid else None,
            'gps_valid': int(self.gps_valid),
            'imu_valid': int(self.imu_valid),
            'odom_valid': int(self.odom_valid),
        }


class CoordinateConverter:
    """Handle coordinate system conversions."""

    def __init__(self, ref_lat: float = 0.0, ref_lon: float = 0.0, 
                 zone_number: int = 33):
        """
        Initialize coordinate converter.
        
        Args:
            ref_lat: Reference latitude for local tangent plane (degrees)
            ref_lon: Reference longitude for local tangent plane (degrees)
            zone_number: UTM zone for conversion (1-60)
        """
        self.ref_lat = ref_lat
        self.ref_lon = ref_lon
        self.zone_number = zone_number
        
        # Pre-compute conversion constants
        self.earth_radius = 6371000.0  # meters
        self.ref_x, self.ref_y = self.latlon_to_utm_local(ref_lat, ref_lon)

    @staticmethod
    def degrees_to_radians(degrees: float) -> float:
        """Convert degrees to radians."""
        return degrees * math.pi / 180.0

    @staticmethod
    def radians_to_degrees(radians: float) -> float:
        """Convert radians to degrees."""
        return radians * 180.0 / math.pi

    @staticmethod
    def heading_to_vector_angle(heading_deg: float) -> float:
        """
        Convert compass heading (0° = North, 90° = East) to math angle 
        (0° = East, 90° = North).
        
        Args:
            heading_deg: Compass heading in degrees (0-360)
            
        Returns:
            Math angle in radians
        """
        # heading_deg: [0=N, 90=E, 180=S, 270=W]
        # math angle: [0=E, π/2=N, π=W, 3π/2=S]
        # Conversion: atan2(N, E) where N = cos(heading), E = sin(heading)
        heading_rad = math.pi / 2.0 - CoordinateConverter.degrees_to_radians(heading_deg)
        return heading_rad

    @staticmethod
    def vector_angle_to_heading(angle_rad: float) -> float:
        """
        Convert math angle to compass heading.
        
        Args:
            angle_rad: Math angle in radians
            
        Returns:
            Compass heading in degrees
        """
        heading_rad = math.pi / 2.0 - angle_rad
        heading_deg = CoordinateConverter.radians_to_degrees(heading_rad)
        # Normalize to [0, 360)
        heading_deg = heading_deg % 360.0
        return heading_deg

    def latlon_to_utm_local(self, lat: float, lon: float) -> Tuple[float, float]:
        """
        Convert lat/lon to local tangent plane coordinates (x, y in meters).
        
        Args:
            lat: Latitude in degrees
            lon: Longitude in degrees
            
        Returns:
            Tuple of (x_m, y_m) in local tangent plane
        """
        # Simple local tangent plane approximation
        # Good for small areas (<10 km)
        lat_rad = self.degrees_to_radians(lat)
        lon_rad = self.degrees_to_radians(lon)
        ref_lat_rad = self.degrees_to_radians(self.ref_lat)
        ref_lon_rad = self.degrees_to_radians(self.ref_lon)

        # Scale factors
        meters_per_degree_lat = 111320.0  # roughly constant
        meters_per_degree_lon = 111320.0 * math.cos(ref_lat_rad)

        x = (lat - self.ref_lat) * meters_per_degree_lat
        y = (lon - self.ref_lon) * meters_per_degree_lon

        return (x, y)

    def latlon_to_utm_local_deg(self, lat_deg: float, lon_deg: float) -> Point2D:
        """Convert lat/lon (degrees) to Point2D in meters."""
        x, y = self.latlon_to_utm_local(lat_deg, lon_deg)
        return Point2D(x, y)


class CSVReader:
    """Read and parse CSV files."""

    @staticmethod
    def read_csv(filepath: str, encoding: str = 'utf-8') -> List[Dict]:
        """Read CSV file and return list of dicts."""
        with open(filepath, 'r', encoding=encoding) as f:
            reader = csv.DictReader(f)
            return list(reader)

    @staticmethod
    def parse_timestamp(timestamp_str: str, format_str: str = None) -> float:
        """
        Parse timestamp string to float (seconds since epoch).
        
        Args:
            timestamp_str: Timestamp string
            format_str: datetime format (if None, try auto-detect)
            
        Returns:
            Seconds since epoch (as float)
        """
        # Try common formats
        formats = [
            '%Y-%m-%dT%H:%M:%S.%f',     # ISO 8601 with microseconds
            '%Y-%m-%dT%H:%M:%S',         # ISO 8601 without microseconds
            '%Y-%m-%d %H:%M:%S.%f',      # Space instead of T
            '%Y-%m-%d %H:%M:%S',
            '%Y/%m/%d %H:%M:%S.%f',
            '%Y/%m/%d %H:%M:%S',
            '%d-%m-%Y %H:%M:%S.%f',
            '%d-%m-%Y %H:%M:%S',
            format_str,
        ]
        
        for fmt in formats:
            if fmt is None:
                continue
            try:
                dt = datetime.strptime(timestamp_str, fmt)
                return dt.timestamp()
            except ValueError:
                continue
        
        # Try parsing as float directly (already in seconds)
        try:
            return float(timestamp_str)
        except ValueError:
            raise ValueError(f"Cannot parse timestamp: {timestamp_str}")


class SensorFusion:
    """Fuse multiple sensor streams."""

    def __init__(self, base_hz: float = 25.0, coord_converter: Optional[CoordinateConverter] = None):
        """
        Initialize fusion.
        
        Args:
            base_hz: Base sampling frequency (Hz) for output timeline
            coord_converter: Coordinate converter for lat/lon → x,y conversion
        """
        self.base_hz = base_hz
        self.ts = 1.0 / base_hz  # Sampling period
        self.coord_converter = coord_converter or CoordinateConverter()
        
        self.gps_times = []
        self.gps_positions = []
        
        self.imu_times = []
        self.imu_psi = []
        self.imu_psi_dot = []
        
        self.odom_times = []
        self.odom_v = []
        
        self.t_min = None
        self.t_max = None

    def add_gps_data(self, times: List[float], positions: List[Point2D]):
        """Add GPS measurements."""
        self.gps_times = times
        self.gps_positions = positions
        if times:
            self.t_min = min(self.t_min or times[0], times[0])
            self.t_max = max(self.t_max or times[-1], times[-1])

    def add_imu_data(self, times: List[float], psi: List[float], psi_dot: List[float]):
        """Add IMU measurements."""
        self.imu_times = times
        self.imu_psi = psi
        self.imu_psi_dot = psi_dot
        if times:
            self.t_min = min(self.t_min or times[0], times[0])
            self.t_max = max(self.t_max or times[-1], times[-1])

    def add_odom_data(self, times: List[float], v: List[float]):
        """Add odometry measurements."""
        self.odom_times = times
        self.odom_v = v
        if times:
            self.t_min = min(self.t_min or times[0], times[0])
            self.t_max = max(self.t_max or times[-1], times[-1])

    def _interpolate_value(self, t: float, times: List[float], 
                          values: List[float], kind: str = 'linear',
                          fill_value: str = 'extrapolate') -> Optional[float]:
        """
        Interpolate value at time t.
        
        Args:
            t: Target time
            times: List of timestamps
            values: List of values
            kind: Interpolation type ('linear', 'nearest', etc.)
            fill_value: How to handle out-of-bounds ('extrapolate', 'nan', etc.)
            
        Returns:
            Interpolated value or None if no data
        """
        if not times or len(times) != len(values):
            return None
        
        if len(times) == 1:
            # Only one point: return it if close enough, else None
            if abs(t - times[0]) < 1.0:  # 1 second tolerance
                return values[0]
            return None
        
        try:
            f = interp1d(times, values, kind=kind, fill_value=fill_value,
                        bounds_error=False)
            return float(f(t))
        except Exception as e:
            print(f"Warning: Interpolation failed at t={t}: {e}", file=sys.stderr)
            return None

    def _interpolate_angle(self, t: float, times: List[float], 
                          angles_rad: List[float]) -> Optional[float]:
        """
        Interpolate angle with proper unwrapping.
        
        Args:
            t: Target time
            times: List of timestamps
            angles_rad: List of angles in radians
            
        Returns:
            Interpolated angle in radians or None
        """
        if not times or len(times) < 2:
            # For single point, return directly
            if times and len(times) == 1:
                return angles_rad[0]
            return None
        
        # Unwrap angles before interpolation
        unwrapped = np.unwrap(angles_rad)
        
        try:
            f = interp1d(times, unwrapped, kind='linear', 
                        fill_value='extrapolate', bounds_error=False)
            result = float(f(t))
            # Normalize result to [-π, π)
            result = result % (2 * math.pi)
            if result > math.pi:
                result -= 2 * math.pi
            return result
        except Exception as e:
            print(f"Warning: Angle interpolation failed at t={t}: {e}", file=sys.stderr)
            return None

    def fuse(self) -> List[FusedMeasurement]:
        """
        Fuse sensor data on unified timeline.
        
        Returns:
            List of FusedMeasurement objects
        """
        if self.t_min is None or self.t_max is None:
            raise ValueError("No sensor data loaded")
        
        # Create timeline
        n_samples = int((self.t_max - self.t_min) / self.ts) + 1
        timeline = np.linspace(self.t_min, self.t_max, n_samples)
        
        measurements = []
        
        for t in timeline:
            # Interpolate each sensor
            gps_pos = None
            gps_valid = False
            if self.gps_times and len(self.gps_times) >= 2:
                try:
                    f_x = interp1d(self.gps_times, [p.x for p in self.gps_positions],
                                  kind='linear', bounds_error=True)
                    f_y = interp1d(self.gps_times, [p.y for p in self.gps_positions],
                                  kind='linear', bounds_error=True)
                    x = float(f_x(t))
                    y = float(f_y(t))
                    gps_pos = Point2D(x, y)
                    gps_valid = True
                except:
                    pass
            
            imu = None
            imu_valid = False
            if self.imu_times and len(self.imu_times) >= 2:
                psi = self._interpolate_angle(t, self.imu_times, self.imu_psi)
                psi_dot = self._interpolate_value(t, self.imu_times, self.imu_psi_dot)
                if psi is not None and psi_dot is not None:
                    imu = IMUData(psi, psi_dot)
                    imu_valid = True
            
            odom = None
            odom_valid = False
            if self.odom_times and len(self.odom_times) >= 2:
                v = self._interpolate_value(t, self.odom_times, self.odom_v)
                if v is not None:
                    odom = OdomData(v)
                    odom_valid = True
            
            measurements.append(FusedMeasurement(
                timestamp=t,
                gps_pos=gps_pos,
                imu=imu,
                odom=odom,
                gps_valid=gps_valid,
                imu_valid=imu_valid,
                odom_valid=odom_valid,
            ))
        
        return measurements


class CSVProcessor:
    """Main processor connecting everything."""

    def __init__(self, config: Dict):
        """
        Initialize processor with configuration.
        
        Args:
            config: Configuration dictionary with keys:
                - base_hz: Output frequency (Hz)
                - gps_file: GPS CSV file path
                - imu_file: IMU CSV file path
                - odom_file: Odometry CSV file path
                - column_map: Dict mapping CSV columns to standard names
                - ref_lat, ref_lon: Reference coordinates for local tangent plane
        """
        self.config = config
        self.coord_converter = CoordinateConverter(
            ref_lat=config.get('ref_lat', 0.0),
            ref_lon=config.get('ref_lon', 0.0),
        )
        self.fusion = SensorFusion(
            base_hz=config.get('base_hz', 25.0),
            coord_converter=self.coord_converter
        )

    def process_gps(self, filepath: str, col_map: Dict) -> Tuple[List[float], List[Point2D]]:
        """
        Process GPS CSV file.
        
        Args:
            filepath: Path to GPS CSV
            col_map: Column mapping {'timestamp': 't_col', 'lat': 'lat_col', ...}
            
        Returns:
            Tuple of (times, positions)
        """
        print(f"Processing GPS: {filepath}")
        data = CSVReader.read_csv(filepath)
        
        times = []
        positions = []
        
        t_col = col_map.get('timestamp', 'timestamp')
        lat_col = col_map.get('lat', 'latitude')
        lon_col = col_map.get('lon', 'longitude')
        
        for i, row in enumerate(data):
            try:
                t = CSVReader.parse_timestamp(row[t_col])
                lat = float(row[lat_col])
                lon = float(row[lon_col])
                
                times.append(t)
                pos = self.coord_converter.latlon_to_utm_local_deg(lat, lon)
                positions.append(pos)
            except Exception as e:
                print(f"Warning: GPS row {i} skipped: {e}", file=sys.stderr)
        
        print(f"  Loaded {len(times)} GPS points (t: {min(times) if times else 'N/A'} → {max(times) if times else 'N/A'})")
        return times, positions

    def process_imu(self, filepath: str, col_map: Dict) -> Tuple[List[float], List[float], List[float]]:
        """
        Process IMU CSV file.
        
        Args:
            filepath: Path to IMU CSV
            col_map: Column mapping
            
        Returns:
            Tuple of (times, heading_rad, yaw_rate_rad_s)
        """
        print(f"Processing IMU: {filepath}")
        data = CSVReader.read_csv(filepath)
        
        times = []
        headings = []
        yaw_rates = []
        
        t_col = col_map.get('timestamp', 'timestamp')
        heading_col = col_map.get('heading', 'heading_deg')
        heading_unit = col_map.get('heading_unit', 'degrees')
        yaw_col = col_map.get('yaw_rate', 'yaw_rate')
        yaw_unit = col_map.get('yaw_unit', 'degrees_per_second')
        
        for i, row in enumerate(data):
            try:
                t = CSVReader.parse_timestamp(row[t_col])
                heading_val = float(row[heading_col])
                yaw_val = float(row[yaw_col])
                
                # Convert heading to radians
                if heading_unit.lower() in ['degrees', 'deg']:
                    heading_rad = CoordinateConverter.heading_to_vector_angle(heading_val)
                else:  # radians
                    heading_rad = heading_val
                
                # Convert yaw rate to rad/s
                if 'degree' in yaw_unit.lower():
                    yaw_rad_s = CoordinateConverter.degrees_to_radians(yaw_val)
                else:  # already radians
                    yaw_rad_s = yaw_val
                
                times.append(t)
                headings.append(heading_rad)
                yaw_rates.append(yaw_rad_s)
            except Exception as e:
                print(f"Warning: IMU row {i} skipped: {e}", file=sys.stderr)
        
        print(f"  Loaded {len(times)} IMU points (t: {min(times) if times else 'N/A'} → {max(times) if times else 'N/A'})")
        return times, headings, yaw_rates

    def process_odom(self, filepath: str, col_map: Dict) -> Tuple[List[float], List[float]]:
        """
        Process Odometry CSV file.
        
        Args:
            filepath: Path to Odometry CSV
            col_map: Column mapping
            
        Returns:
            Tuple of (times, velocity_m_s)
        """
        print(f"Processing Odometry: {filepath}")
        data = CSVReader.read_csv(filepath)
        
        times = []
        velocities = []
        
        t_col = col_map.get('timestamp', 'timestamp')
        vel_col = col_map.get('velocity', 'speed')
        vel_unit = col_map.get('velocity_unit', 'mps')
        
        for i, row in enumerate(data):
            try:
                t = CSVReader.parse_timestamp(row[t_col])
                vel = float(row[vel_col])
                
                # Convert velocity to m/s
                if vel_unit.lower() == 'kmph':
                    vel_mps = vel / 3.6
                elif vel_unit.lower() == 'knots':
                    vel_mps = vel * 0.51444
                else:  # m/s
                    vel_mps = vel
                
                times.append(t)
                velocities.append(vel_mps)
            except Exception as e:
                print(f"Warning: Odom row {i} skipped: {e}", file=sys.stderr)
        
        print(f"  Loaded {len(times)} Odom points (t: {min(times) if times else 'N/A'} → {max(times) if times else 'N/A'})")
        return times, velocities

    def process_all(self, gps_file: str, imu_file: str, odom_file: str,
                   col_map: Dict) -> List[FusedMeasurement]:
        """
        Process all three sensor files and fuse.
        
        Args:
            gps_file: GPS CSV path
            imu_file: IMU CSV path
            odom_file: Odometry CSV path
            col_map: Column mapping
            
        Returns:
            List of fused measurements
        """
        gps_map = col_map.get('gps', {})
        imu_map = col_map.get('imu', {})
        odom_map = col_map.get('odom', {})
        
        if gps_file:
            times, positions = self.process_gps(gps_file, gps_map)
            self.fusion.add_gps_data(times, positions)
        
        if imu_file:
            times, headings, yaw_rates = self.process_imu(imu_file, imu_map)
            self.fusion.add_imu_data(times, headings, yaw_rates)
        
        if odom_file:
            times, velocities = self.process_odom(odom_file, odom_map)
            self.fusion.add_odom_data(times, velocities)
        
        print("\nFusing sensors...")
        measurements = self.fusion.fuse()
        print(f"Generated {len(measurements)} fused measurements")
        
        return measurements

    @staticmethod
    def save_csv(measurements: List[FusedMeasurement], output_file: str):
        """Save fused measurements to CSV."""
        fieldnames = ['timestamp_s', 'gps_x_m', 'gps_y_m', 'imu_psi_rad', 
                     'imu_psidot_radps', 'odom_v_mps', 'gps_valid', 'imu_valid', 'odom_valid']
        
        with open(output_file, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for m in measurements:
                writer.writerow(m.to_dict())
        
        print(f"Saved fused timeline to: {output_file}")

    @staticmethod
    def save_hex(measurements: List[FusedMeasurement], output_file: str,
                fixed_point_bits: int = 24):
        """
        Save fused measurements to .hex format for TestBench.
        
        Each line: t_us gps_x gps_y psi psidot v gps_v imu_v odom_v
        
        Where:
        - t_us: timestamp in microseconds (hex)
        - Values in Q8.24 fixed-point format (hex)
        """
        with open(output_file, 'w') as f:
            f.write("// Fused sensor timeline for CSV route test\n")
            f.write("// Format: t_us gps_x gps_y psi psidot v gps_valid imu_valid odom_valid\n")
            f.write("// All values in Q8.24 fixed-point\n\n")
            
            for i, m in enumerate(measurements):
                t_us = int(m.timestamp * 1e6)
                
                # Convert values to Q8.24
                gps_x = int((m.gps_pos.x if m.gps_pos else 0.0) * (1 << fixed_point_bits)) & 0xFFFFFFFF
                gps_y = int((m.gps_pos.y if m.gps_pos else 0.0) * (1 << fixed_point_bits)) & 0xFFFFFFFF
                psi = int((m.imu.psi if m.imu else 0.0) * (1 << fixed_point_bits)) & 0xFFFFFFFF
                psidot = int((m.imu.psi_dot if m.imu else 0.0) * (1 << fixed_point_bits)) & 0xFFFFFFFF
                v = int((m.odom.v if m.odom else 0.0) * (1 << fixed_point_bits)) & 0xFFFFFFFF
                
                gps_v = int(m.gps_valid)
                imu_v = int(m.imu_valid)
                odom_v = int(m.odom_valid)
                
                # Write as hex
                f.write(f"{t_us:08x} {gps_x:08x} {gps_y:08x} {psi:08x} {psidot:08x} {v:08x} "
                       f"{gps_v:01d} {imu_v:01d} {odom_v:01d}\n")
        
        print(f"Saved hex timeline to: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Fusion IP CSV Processor - fuse multi-sensor logs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Using individual files
  python csv_processor.py --gps gps.csv --imu imu.csv --odom odom.csv -o fused.csv -hz 25
  
  # Using config file
  python csv_processor.py --config config.yaml -o fused.csv
  
  # With hex output
  python csv_processor.py --gps gps.csv --imu imu.csv --odom odom.csv \\
    -o fused.csv --hex fused.hex
        """)
    
    # Input options
    parser.add_argument('--config', help='YAML config file (for advanced usage)')
    parser.add_argument('--gps', help='GPS CSV file')
    parser.add_argument('--imu', help='IMU CSV file')
    parser.add_argument('--odom', help='Odometry CSV file')
    
    # Output options
    parser.add_argument('-o', '--output', required=True, help='Output CSV file')
    parser.add_argument('--hex', help='Optional output .hex file')
    
    # Processing options
    parser.add_argument('--hz', type=float, default=25.0, 
                       help='Output frequency in Hz (default: 25)')
    parser.add_argument('--ref-lat', type=float, default=0.0,
                       help='Reference latitude for local tangent plane (degrees)')
    parser.add_argument('--ref-lon', type=float, default=0.0,
                       help='Reference longitude for local tangent plane (degrees)')
    
    # Column mapping (advanced)
    parser.add_argument('--gps-time', default='timestamp', help='GPS timestamp column')
    parser.add_argument('--gps-lat', default='latitude', help='GPS latitude column')
    parser.add_argument('--gps-lon', default='longitude', help='GPS longitude column')
    
    parser.add_argument('--imu-time', default='timestamp', help='IMU timestamp column')
    parser.add_argument('--imu-heading', default='heading_deg', help='IMU heading column')
    parser.add_argument('--imu-yaw-rate', default='yaw_rate', help='IMU yaw rate column')
    
    parser.add_argument('--odom-time', default='timestamp', help='Odom timestamp column')
    parser.add_argument('--odom-vel', default='speed', help='Odom velocity column')
    
    args = parser.parse_args()
    
    # Build configuration
    if args.config:
        with open(args.config, 'r') as f:
            config = yaml.safe_load(f)
    else:
        config = {
            'base_hz': args.hz,
            'ref_lat': args.ref_lat,
            'ref_lon': args.ref_lon,
        }
    
    # Build column maps
    col_map = {
        'gps': {
            'timestamp': args.gps_time,
            'lat': args.gps_lat,
            'lon': args.gps_lon,
        },
        'imu': {
            'timestamp': args.imu_time,
            'heading': args.imu_heading,
            'yaw_rate': args.imu_yaw_rate,
        },
        'odom': {
            'timestamp': args.odom_time,
            'velocity': args.odom_vel,
        },
    }
    
    # Process
    try:
        processor = CSVProcessor(config)
        measurements = processor.process_all(args.gps, args.imu, args.odom, col_map)
        
        # Save outputs
        CSVProcessor.save_csv(measurements, args.output)
        if args.hex:
            CSVProcessor.save_hex(measurements, args.hex)
        
        print("\n✓ Processing complete!")
        
    except Exception as e:
        print(f"\n✗ Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
