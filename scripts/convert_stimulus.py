#!/usr/bin/env python3
"""
Stimulus Converter: sensor CSVs → UVM-friendly hex stimulus + memh

Thin wrapper around generate_golden.py — use this as the primary entry
point for generating UVM simulation inputs from AIS-based tracking data.

Usage:
  python convert_stimulus.py                        # case 0, all steps
  python convert_stimulus.py --case 3 --steps 200   # case 3, 200 steps
  python convert_stimulus.py --datadir ../tracking_ship --outdir ../tb/golden
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_golden import main

if __name__ == "__main__":
    main()
