"""
Unscented Kalman Filter (UKF) Implementation for Ship Tracking

Implements UKF with Constant Turn Rate and Velocity (CTRV) motion model.

State vector: x = [x_pos, y_pos, speed, heading, yaw_rate]
- x_pos: East position (meters)
- y_pos: North position (meters)  
- speed: Speed over ground (m/s)
- heading: Heading angle (radians)
- yaw_rate: Yaw rate (rad/s)

Author: Ship Tracking UKF Project
"""

import numpy as np
from scipy.linalg import cholesky, block_diag


class UnscentedKalmanFilter:
    """
    Unscented Kalman Filter with CTRV motion model for ship tracking.
    """
    
    def __init__(self, dim_x: int = 5, alpha: float = 0.001, 
                 beta: float = 2.0, kappa: float = 0.0):
        """
        Initialize UKF.
        
        Args:
            dim_x: State dimension (default 5 for CTRV)
            alpha: Spread of sigma points (small positive, e.g., 1e-3)
            beta: Prior knowledge of distribution (2 is optimal for Gaussian)
            kappa: Secondary scaling parameter (usually 0 or 3-n)
        """
        self.dim_x = dim_x
        self.alpha = alpha
        self.beta = beta
        self.kappa = kappa
        
        # Compute lambda and weights
        self.lambda_ = alpha**2 * (dim_x + kappa) - dim_x
        self.n_sigma = 2 * dim_x + 1
        
        # Weights for mean and covariance
        self.Wm = np.zeros(self.n_sigma)
        self.Wc = np.zeros(self.n_sigma)
        
        self.Wm[0] = self.lambda_ / (dim_x + self.lambda_)
        self.Wc[0] = self.Wm[0] + (1 - alpha**2 + beta)
        
        for i in range(1, self.n_sigma):
            self.Wm[i] = 1.0 / (2 * (dim_x + self.lambda_))
            self.Wc[i] = self.Wm[i]
        
        # State and covariance
        self.x = np.zeros(dim_x)
        self.P = np.eye(dim_x)
        
        # Process noise covariance
        self.Q = np.eye(dim_x) * 0.1
        
        # Sigma points storage
        self.sigma_points = np.zeros((self.n_sigma, dim_x))
    
    def set_initial_state(self, x0: np.ndarray, P0: np.ndarray):
        """Set initial state and covariance."""
        self.x = x0.copy()
        self.P = P0.copy()
    
    def set_process_noise(self, Q: np.ndarray):
        """Set process noise covariance matrix."""
        self.Q = Q.copy()
    
    def _generate_sigma_points(self) -> np.ndarray:
        """Generate sigma points using Cholesky decomposition."""
        n = self.dim_x
        sigma_pts = np.zeros((self.n_sigma, n))
        
        # Compute square root of (n + lambda) * P
        try:
            sqrt_matrix = cholesky((n + self.lambda_) * self.P, lower=True)
        except np.linalg.LinAlgError:
            # If Cholesky fails, use eigenvalue decomposition
            eigvals, eigvecs = np.linalg.eigh(self.P)
            eigvals = np.maximum(eigvals, 1e-10)
            sqrt_matrix = eigvecs @ np.diag(np.sqrt((n + self.lambda_) * eigvals))
        
        # First sigma point is the mean
        sigma_pts[0] = self.x
        
        # Remaining sigma points
        for i in range(n):
            sigma_pts[i + 1] = self.x + sqrt_matrix[:, i]
            sigma_pts[n + i + 1] = self.x - sqrt_matrix[:, i]
        
        return sigma_pts
    
    def _ctrv_motion_model(self, x: np.ndarray, dt: float) -> np.ndarray:
        """
        Constant Turn Rate and Velocity (CTRV) motion model.
        
        State: [x_pos, y_pos, speed, heading, yaw_rate]
        """
        px, py, v, psi, psi_dot = x
        
        # Avoid division by zero for straight motion
        if abs(psi_dot) < 1e-6:
            # Straight line motion
            px_new = px + v * np.cos(psi) * dt
            py_new = py + v * np.sin(psi) * dt
        else:
            # Curved motion
            px_new = px + (v / psi_dot) * (np.sin(psi + psi_dot * dt) - np.sin(psi))
            py_new = py + (v / psi_dot) * (-np.cos(psi + psi_dot * dt) + np.cos(psi))
        
        v_new = v  # Constant velocity assumption
        psi_new = psi + psi_dot * dt
        psi_dot_new = psi_dot  # Constant turn rate assumption
        
        # Normalize heading to [-pi, pi]
        psi_new = self._normalize_angle(psi_new)
        
        return np.array([px_new, py_new, v_new, psi_new, psi_dot_new])
    
    @staticmethod
    def _normalize_angle(angle: float) -> float:
        """Normalize angle to [-pi, pi]."""
        # Handle NaN and inf
        if not np.isfinite(angle):
            return 0.0  # Default to 0 for invalid angles
        
        # Normalize to [-pi, pi] using arctan2 for efficiency and stability
        angle = np.arctan2(np.sin(angle), np.cos(angle))
        return angle
    
    def predict(self, dt: float):
        """
        UKF prediction step.
        
        Args:
            dt: Time step in seconds
        """
        # Generate sigma points
        sigma_pts = self._generate_sigma_points()
        
        # Propagate sigma points through motion model
        sigma_pts_pred = np.zeros_like(sigma_pts)
        for i in range(self.n_sigma):
            sigma_pts_pred[i] = self._ctrv_motion_model(sigma_pts[i], dt)
        
        # Compute predicted mean
        x_pred = np.zeros(self.dim_x)
        for i in range(self.n_sigma):
            x_pred += self.Wm[i] * sigma_pts_pred[i]
        
        # Normalize heading in mean
        x_pred[3] = self._normalize_angle(x_pred[3])
        
        # Compute predicted covariance
        P_pred = self.Q.copy()
        for i in range(self.n_sigma):
            diff = sigma_pts_pred[i] - x_pred
            diff[3] = self._normalize_angle(diff[3])
            P_pred += self.Wc[i] * np.outer(diff, diff)
        
        self.x = x_pred
        self.P = P_pred
        self.sigma_points = sigma_pts_pred
    
    def update_gps(self, z: np.ndarray, R: np.ndarray):
        """
        Update step for GPS measurement (position only).
        
        Args:
            z: Measurement [x, y]
            R: Measurement noise covariance (2x2)
        """
        dim_z = 2
        
        # Regenerate sigma points from current state
        sigma_pts = self._generate_sigma_points()
        
        # Transform sigma points to measurement space
        Z_sigma = np.zeros((self.n_sigma, dim_z))
        for i in range(self.n_sigma):
            Z_sigma[i] = sigma_pts[i, :2]  # Extract [x, y]
        
        # Predicted measurement mean
        z_pred = np.zeros(dim_z)
        for i in range(self.n_sigma):
            z_pred += self.Wm[i] * Z_sigma[i]
        
        # Innovation covariance
        S = R.copy()
        for i in range(self.n_sigma):
            diff_z = Z_sigma[i] - z_pred
            S += self.Wc[i] * np.outer(diff_z, diff_z)
        
        # Cross-correlation matrix
        T = np.zeros((self.dim_x, dim_z))
        for i in range(self.n_sigma):
            diff_x = sigma_pts[i] - self.x
            diff_x[3] = self._normalize_angle(diff_x[3])
            diff_z = Z_sigma[i] - z_pred
            T += self.Wc[i] * np.outer(diff_x, diff_z)
        
        # Kalman gain
        K = T @ np.linalg.inv(S)
        
        # Update state and covariance
        innovation = z - z_pred
        self.x = self.x + K @ innovation
        self.x[3] = self._normalize_angle(self.x[3])
        self.P = self.P - K @ S @ K.T
    
    def update_imu(self, z: np.ndarray, R: np.ndarray):
        """
        Update step for IMU measurement (heading and yaw rate).
        
        Args:
            z: Measurement [heading, yaw_rate]
            R: Measurement noise covariance (2x2)
        """
        dim_z = 2
        
        sigma_pts = self._generate_sigma_points()
        
        # Transform to measurement space [heading, yaw_rate]
        Z_sigma = np.zeros((self.n_sigma, dim_z))
        for i in range(self.n_sigma):
            Z_sigma[i] = sigma_pts[i, 3:5]  # [heading, yaw_rate]
        
        # Predicted measurement mean
        z_pred = np.zeros(dim_z)
        for i in range(self.n_sigma):
            z_pred += self.Wm[i] * Z_sigma[i]
        z_pred[0] = self._normalize_angle(z_pred[0])
        
        # Innovation covariance
        S = R.copy()
        for i in range(self.n_sigma):
            diff_z = Z_sigma[i] - z_pred
            diff_z[0] = self._normalize_angle(diff_z[0])
            S += self.Wc[i] * np.outer(diff_z, diff_z)
        
        # Cross-correlation
        T = np.zeros((self.dim_x, dim_z))
        for i in range(self.n_sigma):
            diff_x = sigma_pts[i] - self.x
            diff_x[3] = self._normalize_angle(diff_x[3])
            diff_z = Z_sigma[i] - z_pred
            diff_z[0] = self._normalize_angle(diff_z[0])
            T += self.Wc[i] * np.outer(diff_x, diff_z)
        
        K = T @ np.linalg.inv(S)
        
        innovation = z - z_pred
        innovation[0] = self._normalize_angle(innovation[0])
        
        self.x = self.x + K @ innovation
        self.x[3] = self._normalize_angle(self.x[3])
        self.P = self.P - K @ S @ K.T
    
    def update_odometer(self, z: float, R: float):
        """
        Update step for odometer measurement (speed only).
        
        Args:
            z: Speed measurement (m/s)
            R: Measurement noise variance (scalar)
        """
        sigma_pts = self._generate_sigma_points()
        
        # Transform to measurement space [speed]
        Z_sigma = sigma_pts[:, 2]  # Speed is index 2
        
        # Predicted measurement mean
        z_pred = np.sum(self.Wm * Z_sigma)
        
        # Innovation covariance
        S = R
        for i in range(self.n_sigma):
            diff_z = Z_sigma[i] - z_pred
            S += self.Wc[i] * diff_z**2
        
        # Cross-correlation
        T = np.zeros(self.dim_x)
        for i in range(self.n_sigma):
            diff_x = sigma_pts[i] - self.x
            diff_x[3] = self._normalize_angle(diff_x[3])
            diff_z = Z_sigma[i] - z_pred
            T += self.Wc[i] * diff_x * diff_z
        
        K = T / S
        
        innovation = z - z_pred
        self.x = self.x + K * innovation
        self.x[3] = self._normalize_angle(self.x[3])
        self.P = self.P - np.outer(K, K) * S
    
    def get_state(self) -> np.ndarray:
        """Return current state estimate."""
        return self.x.copy()
    
    def get_covariance(self) -> np.ndarray:
        """Return current state covariance."""
        return self.P.copy()
