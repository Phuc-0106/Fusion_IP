

interface fusion_sensor_vif(
    input bit clk,
    input bit rst_n
);
    // GPS Interface (2D position)
    logic [63:0] gps_data;
    logic        gps_valid;
    logic [95:0] imu_data;
    logic        imu_valid;
    logic [31:0] odom_data;
    logic        odom_valid;

endinterface : fusion_sensor_vif

