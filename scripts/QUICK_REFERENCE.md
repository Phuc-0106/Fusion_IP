# Quick reference — AIS golden + `test-csv`

## One-time

```bash
pip install -r scripts/requirements.txt
```

## Before `make test-csv`

```bash
# 1) (If needed) Run tracking_ship to create ukf_results_caseN.csv + measurement CSVs
#    See tracking_ship/README.md

# 2) Generate golden + memh (N = case id, match ukf_results_caseN.csv)
python scripts/generate_golden.py --case 0 --datadir .

# Same as:
python scripts/convert_stimulus.py --case 0 --datadir .
```

Optional: `--steps 200` to shorten the run.

## Run test

```bash
cd sim
make test-csv
```

## Optional plusargs

```text
+STIM_FILE=../tb/golden/golden_stimulus.csv
+EXPECT_FILE=../tb/golden/golden_expected.csv
+MAX_CYCLES=100
+POLL_TO=10000
```

## Inputs `generate_golden.py` expects in `--datadir`

- `gps_measurement.csv`
- `imu_measurement.csv`
- `odometer_measurement.csv`
- `ukf_results_case{N}.csv` (`N` = `--case`)

## Outputs

- `tb/golden/golden_stimulus.csv`
- `tb/golden/golden_expected.csv`
- `tb/golden/state_mem_init.memh` and copy at `tb/state_mem_init.memh`
