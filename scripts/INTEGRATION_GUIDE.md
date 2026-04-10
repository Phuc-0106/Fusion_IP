# UVM integration — CSV route test (AIS golden)

## Test and sequence

- **Test:** `fusion_csv_route_test` (`fusion_tests_pkg` in `testcases/fusion_tests.sv`).
- **Virtual sequence:** `fusion_csv_route_vseq` reads CSVs via classes in `sequences/csv_route_sequence.sv` (`golden_stimulus_reader`, `golden_expected_reader`).

## Default files (relative to `sim/`)

| Variable | Default |
|----------|---------|
| Stimulus | `../tb/golden/golden_stimulus.csv` |
| Expected | `../tb/golden/golden_expected.csv` |

Override with plusargs:

```text
+STIM_FILE=<path>
+EXPECT_FILE=<path>
```

Other plusargs: `+POLL_TO=<cycles>`, `+MAX_CYCLES=<N>` (0 = all rows).

## DUT initialization

`tb/tb_fusion_ip.sv` loads **`../tb/state_mem_init.memh`** at time 0. It must be regenerated with **`generate_golden.py`** for the same **`--case`** as `ukf_results_caseN.csv`, or P/Q/R will not match the Python tuning case.

## Per-cycle behavior (T8)

1. Write **DT** register `0x1C` (Q8.24 `dt` from golden row).
2. Call scoreboard **`set_dt()`** so the SV predictor uses the same `dt`.
3. **`push_golden()`** — GT, GPS, and Python `est_*` (5-state) for scoreboard tiers.
4. Drive **sensor_vif** (GPS / IMU / odom).
5. Start UKF, poll status, read outputs `0x20`–`0x30`, clear IRQ.

## Scoreboard

Configured in the environment as **`fusion_scoreboard`** (`tb/fusion_scoreboard.sv`): primary DUT vs predictor, optional calibration vs golden CSV, quality vs GT.

## Makefile note

`sim/Makefile` may pass `RUNARG` with legacy `+CSV_FILE=...`; the **current** T8 sequence uses **`STIM_FILE` / `EXPECT_FILE`** as above. Prefer generating golden files and running `make test-csv` without relying on `CSV_FILE`.

## Related RTL

- **REG_DT** at `0x1C` — sample period in Q8.24 (see `rtl/fusion_ip_top.sv`).
