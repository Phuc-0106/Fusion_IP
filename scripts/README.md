# Scripts — AIS golden vectors & UVM CSV test

Verification uses **sensor CSVs** + **Python UKF results** from `tracking_ship`, converted offline into files under `tb/golden/` and `tb/state_mem_init.memh`. The UVM test **`fusion_csv_route_test`** (`make test-csv`) reads those outputs.

## Pipeline (overview)

```
tracking_ship (AIS → sensors → UKF)  →  ukf_results_caseN.csv, *_measurement.csv
                    ↓
scripts/generate_golden.py  (or convert_stimulus.py)
                    ↓
tb/golden/golden_stimulus.csv   — hex Q8.24 + dt_hex + floats for scoreboard
tb/golden/golden_expected.csv   — Python UKF 5-state + metrics
tb/state_mem_init.memh          — P, Q, R (Q8.24) for DUT init
                    ↓
cd sim && make test-csv
```

## Prerequisites

- **Python 3** with **NumPy** (see `requirements.txt`).
- In the **data directory** (`--datadir`, default: repo root), you must have:
  - `imu_measurement.csv`
  - `odometer_measurement.csv`
  - `ukf_results_case{N}.csv` where `N` matches `--case` (0–5).
- `gps_measurement.csv` may exist for tooling but **`generate_golden.py` does not merge it**; GPS in golden comes from `ukf_results` (`gps_x`, `gps_y`). Run `python scripts/check_golden_consistency.py --case N --datadir . --golden-dir tb/golden` to verify row counts, optional 5-state columns, `dt` vs `golden_stimulus`, and P/Q/R vs `tb/state_mem_init.memh`.

Generate the UKF file and measurements from **`tracking_ship`** (see `tracking_ship/README.md` or `QUICKSTART.md`).

## Main script: `generate_golden.py`

Builds golden stimulus, expected values, and copies `state_mem_init.memh` into `tb/`.

```bash
# From repo root (default datadir = parent of scripts/ = repo root)
python scripts/generate_golden.py --case 0

# Explicit data directory (e.g. tracking_ship output folder)
python scripts/generate_golden.py --case 5 --datadir ./tracking_ship

# Limit cycles (faster sim)
python scripts/generate_golden.py --case 0 --steps 200

# Custom output directory
python scripts/generate_golden.py --case 0 --outdir ./tb/golden
```

**Wrapper (same CLI):** `python scripts/convert_stimulus.py ...`

### Arguments

| Argument | Meaning |
|----------|---------|
| `--case N` | Tuning case 0–5; must match `ukf_results_caseN.csv` and RTL/memh tuning. |
| `--datadir DIR` | Folder containing the four CSV files above (default: repo root). |
| `--steps K` | Optional; only first K rows. |
| `--outdir DIR` | Default: `tb/golden/`. |

## Run simulation: CSV route test

From **`sim/`** (paths match `../tb/golden/...`):

```bash
cd sim
make test-csv
```

Optional plusargs (see `fusion_csv_route_vseq` in `testcases/fusion_tests.sv`):

```bash
make test-csv RUNARG="+STIM_FILE=../tb/golden/golden_stimulus.csv +EXPECT_FILE=../tb/golden/golden_expected.csv +MAX_CYCLES=100 +POLL_TO=10000"
```

## Outputs (what each file is for)

| File | Produced by | Used by |
|------|-------------|---------|
| `tb/golden/golden_stimulus.csv` | `generate_golden.py` | T8 sequence: sensor hex, `dt_hex`, GT/GPS floats |
| `tb/golden/golden_expected.csv` | `generate_golden.py` | T8: Python `est_*` for scoreboard calibration |
| `tb/state_mem_init.memh` | `generate_golden.py` (copy to `tb/`) | `$readmemh` in `tb_fusion_ip.sv` |

Re-run **`generate_golden.py`** whenever you change AIS data, UKF case, or `ukf_results_caseN.csv`.

## Other files in this folder

| File | Role |
|------|------|
| `convert_stimulus.py` | Thin wrapper; calls `generate_golden.main()`. |
| `requirements.txt` | Python dependencies for scripts. |
| `csv_processor.py`, `generate_example_csv.py`, `run_csv_test.sh` | **Legacy / optional** — generic CSV fusion; not required for the AIS golden flow above. See `CSV_PROCESSOR_README.md`. |

## More documentation

- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** — copy-paste commands
- **[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)** — UVM paths, plusargs, scoreboard
- **[CSV_PROCESSOR_README.md](CSV_PROCESSOR_README.md)** — legacy `csv_processor` only
