# SEQUENCES - UVM Stimulus Sequences

This directory contains UVM sequence classes that generate stimulus patterns for Fusion IP verification.

## Available Sequences

### CSV Route Sequence
**File:** csv_route_sequence.sv  
**Purpose:** Load real multi-sensor CSV data and drive as test stimulus  
**Features:**
- Reads CSV file with GPS/IMU/Odometry measurements
- Generates UVM items at specified rate
- Handles missing/invalid sensor data
- Supports data replication
**Usage:**
```bash
make test-csv CSV_FILE=../scripts/fused_timeline.csv CSV_HZ=25
```

### Standard Sequences (in base_sequences.sv)
**const_measurement_seq** - Constant sensor values  
**ramp_measurement_seq** - Linear ramp stimulus  
**sine_measurement_seq** - Sinusoidal patterns  
**random_measurement_seq** - Randomized values  
**burst_measurement_seq** - Burst of rapid changes  

## Creating Custom Sequences

```systemverilog
class my_sequence extends uvm_sequence #(sensor_measurement_t);
    `uvm_object_utils(my_sequence)
    
    rand int num_items;
    constraint c_num_items { num_items inside {[10:100]}; }
    
    function new(string name="my_sequence");
        super.new(name);
    endfunction
    
    task body();
        `uvm_info("SEQ", "Starting sequence", UVM_HIGH)
        repeat(num_items) begin
            `uvm_create(req)
            `uvm_rand_wait(1, 10)
            `uvm_send(req)
        end
    endtask
endclass
```

## Sequence Organization

```
sequences/
├── base_sequences.sv        # Standard sequences
├── csv_route_sequence.sv    # CSV data-driven
├── specialized/
│   ├── gps_loss_recovery_seq.sv
│   ├── multi_rate_alignment_seq.sv
│   └── ...
└── README.md                # This file
```

## Standard Patterns

### Measurement Sequence Template

```systemverilog
class measurement_sequence extends uvm_sequence #(fusion_measurement_t);
    `uvm_object_utils(measurement_sequence)
    
    rand int unsigned duration;    // Stimulus duration in cycles
    rand fusion_config cfg;        // Configuration object
    
    function new(string name="measurement_sequence");
        super.new(name);
    endfunction
    
    task body();
        repeat(duration) begin
            `uvm_create(req)
            req.randomize() with { /* constraints */ };
            `uvm_send(req)
        end
    endtask
endclass
```

## CSV Data Integration

CSV sequences read measurement files:

```
timestamp,gps_x,gps_y,imu_psi,imu_psidot,odom_v,gps_valid,imu_valid,odom_valid
0.0,0.0,0.0,0.0,0.0,5.0,1,1,1
0.04,0.2,0.0,0.0,0.0,5.0,1,1,1
...
```

Generate from Python:
```bash
python3 ../scripts/csv_processor.py \
  --gps data.csv --imu data.csv --odom data.csv \
  -o fused_timeline.csv
```

## Sequence Usage in Tests

```systemverilog
class my_test extends fusion_base_test;
    task run_phase(uvm_phase phase);
        my_sequence seq;
        phase.raise_objection(this);
        
        seq = my_sequence::type_id::create("seq");
        seq.start(env.sensor_ag.sequencer);
        
        #100; // Wait for simulation
        phase.drop_objection(this);
    endtask
endclass
```

## Recommended Practices

1. **Encapsulation** - Hide complexity in base classes
2. **Randomization** - Use constraints for coverage
3. **Reusability** - Sequences should be generic
4. **Documentation** - Comment complex logic
5. **Debugging** - Use UVM macros for tracing

## Notes

- All sequences are UVM 1.2 compliant
- CSV sequences support real-world data
- Sequences can be combined hierarchically
- Factory mechanism enables substitution

