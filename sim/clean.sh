#!/bin/bash
# Quick Clean Script for Fusion IP UVM Testbench

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
CLEAN_TYPE="all"  # "all", "logs", "work", "waves"
FORCE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all)
            CLEAN_TYPE="all"
            shift
            ;;
        -l|--logs)
            CLEAN_TYPE="logs"
            shift
            ;;
        -w|--work)
            CLEAN_TYPE="work"
            shift
            ;;
        --waves)
            CLEAN_TYPE="waves"
            shift
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        -h|--help)
            echo "Fusion IP UVM Quick Clean"
            echo ""
            echo "Usage: ./clean.sh [option]"
            echo ""
            echo "Options:"
            echo "  -a, --all      Clean everything (default)"
            echo "  -l, --logs     Remove log files only"
            echo "  -w, --work     Remove work directory only"
            echo "  --waves        Remove waveform files only"
            echo "  -f, --force    No confirmation"
            echo "  -h, --help     Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Confirm
if [ $FORCE -eq 0 ]; then
    case $CLEAN_TYPE in
        all)
            echo "Remove: work/, log/, waves/, *.wlf, *.ucdb, transcript, modelsim.ini?"
            ;;
        logs)
            echo "Remove log/ directory?"
            ;;
        work)
            echo "Remove work/ directory?"
            ;;
        waves)
            echo "Remove waveform files?"
            ;;
    esac
    
    read -p "Confirm (y/n)? " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
fi

# Clean
case $CLEAN_TYPE in
    all)
        echo "Cleaning everything..."
        rm -rf work/ log/ waves/ *.wlf *.shm *.fsdb *.ucdb transcript modelsim.ini
        rm -rf *.o *.so xsim_* work_*
        echo "Clean complete"
        ;;
    logs)
        echo "Removing logs..."
        rm -rf log/
        echo "Logs removed"
        ;;
    work)
        echo "Removing work directory..."
        rm -rf work/
        echo "Work directory removed"
        ;;
    waves)
        echo "Removing waveforms..."
        rm -rf waves/ *.wlf *.shm *.fsdb
        echo "Waveforms removed"
        ;;
esac

