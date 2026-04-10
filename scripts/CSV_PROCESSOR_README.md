# Legacy: `csv_processor.py` (optional)

The **recommended** path for the Fusion IP CSV route test is:

1. **`tracking_ship`** — AIS pipeline and UKF → `ukf_results_case{N}.csv` + measurement CSVs.
2. **`scripts/generate_golden.py`** — builds `tb/golden/*.csv` and `tb/state_mem_init.memh`.
3. **`make test-csv`** — UVM reads `golden_stimulus.csv` / `golden_expected.csv`.

The scripts **`csv_processor.py`**, **`generate_example_csv.py`**, and **`run_csv_test.sh`** are **not** part of that flow. They were intended for a generic “fuse arbitrary GPS/IMU/odom CSVs into one timeline” workflow. You may still use them for ad-hoc experiments; see **`python csv_processor.py --help`** and `config_template.yaml`.

**Current documentation for verification:** [README.md](README.md), [QUICK_REFERENCE.md](QUICK_REFERENCE.md), [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md).
