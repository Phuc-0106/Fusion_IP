# Installation Guide - Fusion IP UVM Verification on Linux

Step-by-step hướng dẫn cài đặt Fusion IP verification environment trên Linux.

## Prerequisites

### 1. Linux Distribution
- Ubuntu 20.04 LTS / 22.04 LTS (recommended)
- Or any Debian-based distro
- Or RHEL/CentOS compatible

### 2. Base Tools
```bash
# Update package manager
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    build-essential \
    make \
    perl \
    git \
    wget \
    curl \
    python3 \
    python3-pip \
    dos2unix
```

### 3. Simulator (Questa/ModelSim)

#### Option A: Download from Mentor (Intel Quartus Bundle)
1. Download from: https://www.intel.com/content/www/us/en/software/programmable/quartus/download.html
   - Or: Mentor EDA (requires license/trial)
2. Extract to /opt (or your preferred path)
3. Add to PATH

#### Option B: Install from System Package
```bash
# Ubuntu/Debian (if available in repos)
sudo apt install -y questasim
# or
sudo apt install -y modelsim
```

### 4. Verify Installation
```bash
vlog --version
vsim --version
perl --version

# Output should show tool versions
```

## Step 1: Clone/Extract Fusion IP

```bash
# Option A: Clone from git
git clone <repo_url> /path/to/Fusion_IP
cd /path/to/Fusion_IP

# Option B: Extract from archive
tar -xzf Fusion_IP.tar.gz
cd Fusion_IP
```

## Step 2: Setup UVM Library

### Option A: Use Questa Built-in UVM
Default UVM locations:
- Questa 2021.2: `/opt/questasim/verilog_src/uvm-1.2`
- Questa 10.8b: `/opt/questasim_10.8b/verilog_src/uvm-1.2`

### Option B: Download UVM Separately
```bash
# Create UVM directory
mkdir -p ~/tools
cd ~/tools

# Download UVM (from accellera.org or mentor mirrors)
wget https://www.accellera.org/images/downloads/standards/uvm/uvm-1.2.tar.gz
tar -xzf uvm-1.2.tar.gz

# Set path
export UVM_HOME=~/tools/uvm-1.2
```

## Step 3: Configure Environment

### 1. Edit project_env.bash

```bash
cd /path/to/Fusion_IP/sim
vi project_env.bash
```

Find this line (around line 17):
```bash
export UVM_HOME=${UVM_HOME:-/opt/questasim/verilog_src/uvm-1.2}
```

Change to your actual UVM path:
```bash
export UVM_HOME=/opt/questasim_10.8b/verilog_src/uvm-1.2
# or
export UVM_HOME=~/tools/uvm-1.2
```

Save and verify:
```bash
source ./project_env.bash
ls $UVM_HOME/src/uvm.sv    # Should exist
```

### 2. Add Questa to PATH (if not already)

```bash
# Find Questa installation
which vlog

# If not found, add to ~/.bashrc
nano ~/.bashrc
```

Add this line:
```bash
export PATH="/opt/questasim_10.8b/bin:$PATH"
```

Or for Quartus Questa:
```bash
export PATH="/home/user/intelquartus/modelsim_ase/bin:$PATH"
```

Apply:
```bash
source ~/.bashrc
vlog --version    # Should work now
```

## Step 4: Initial Setup

### Run Setup Script

```bash
cd /path/to/Fusion_IP/sim
bash setup.sh
```

Script will:
- ✓ Check for required tools
- ✓ Find UVM library
- ✓ Create necessary directories
- ✓ Make scripts executable
- ✓ Update project_env.bash

### Manual Verification

```bash
# 1. Check tools
which vlog vsim perl make
# Should show paths to all

# 2. Check UVM
ls $UVM_HOME/src/uvm.sv
# Should exist

# 3. Check directories
cd sim && ls -la log/ waves/ coverage/
# Should exist
```

## Step 5: First Compilation & Run

### Setup Shell

```bash
cd sim
source ./project_env.bash
```

### Compile Only

```bash
make clean
make build
```

Expected output:
```
[BUILD] Compiling with questa...
[VLOG] Compiling RTL and TB sources from compile.f...
[BUILD] Compilation successful
```

### Run Sanity Test

```bash
make test-sanity
```

Expected output:
```
[RUN] Starting simulation: fusion_sanity_test with SEED=1
...
[RUN] Simulation complete - log: log/fusion_sanity_test_1_*.log
```

Check log:
```bash
cat log/run.log
# Should end with: TEST PASSED or similar
```

## Troubleshooting Installation

### Issue 1: `vlog: command not found`

```bash
# Solution: Add Questa to PATH
export PATH="/opt/questasim_10.8b/bin:$PATH"

# Verify
which vlog
vlog --version
```

### Issue 2: `Cannot find UVM home`

```bash
# List UVM locations
find /opt -name "uvm.sv" 2>/dev/null
find ~ -name "uvm.sv" 2>/dev/null

# Update UVM_HOME in project_env.bash with correct path
```

### Issue 3: Permission Denied on .sh Files

```bash
chmod +x ~/Fusion_IP/sim/*.sh
chmod +x ~/Fusion_IP/sim/regress.pl
```

### Issue 4: Compilation Errors

```bash
# Check file permissions
ls -la rtl.f tb.f compile.f

# Check for DOS line endings (common from Windows)
file rtl.f
# If shows "CRLF", convert:
dos2unix rtl.f tb.f compile.f *.bash

# Retry compile
make clean
make build
```

### Issue 5: Variable Expand Error in TB Files

```bash
# Example error: "Cannot expand ${FUSION_IP_RTL_PATH}"

# Solution: Ensure environment is sourced
source ./project_env.bash

# Verify
echo $FUSION_IP_RTL_PATH
# Should print path, not be empty
```

## Optional: Advanced Setup

### Setup for Multiple Users

Create shared UVM library:
```bash
sudo mkdir -p /opt/shared_uvm
sudo tar -xzf uvm-1.2.tar.gz -C /opt/shared_uvm
sudo chown -R root:users /opt/shared_uvm
chmod g+rx /opt/shared_uvm
```

Then in project_env.bash:
```bash
export UVM_HOME=/opt/shared_uvm/uvm-1.2
```

### Setup for CI/CD (GitHub Actions, GitLab CI, etc.)

Create `.github/workflows/sim.yml`:
```yaml
name: Simulation
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup dependencies
        run: sudo apt install -y questasim perl
      - name: Setup UVM
        run: |
          export UVM_HOME=/opt/questasim/verilog_src/uvm-1.2
      - name: Run tests
        run: |
          cd sim
          source ./project_env.bash
          make test-all
```

### Docker Setup (Optional)

Create `Dockerfile`:
```dockerfile
FROM ubuntu:22.04

RUN apt update && apt install -y \
    questasim \
    perl \
    make \
    git

WORKDIR /fusion_ip
COPY . .

RUN cd sim && bash setup.sh

CMD ["bash", "-c", "cd sim && source ./project_env.bash && make test-all"]
```

Build and run:
```bash
docker build -t fusion-ip-sim .
docker run fusion-ip-sim
```

## Verification Checklist

- [ ] Linux OS installed and updated
- [ ] Questa/ModelSim installed
- [ ] Tools (make, perl) installed
- [ ] UVM library located
- [ ] `project_env.bash` edited with correct UVM_HOME
- [ ] `source ./project_env.bash` works without errors
- [ ] `make build` compiles successfully
- [ ] `make test-sanity` runs and passes
- [ ] Log files created in `sim/log/`

## Next Steps After Installation

1. **Quick Start:**
   ```bash
   cd sim
   source ./project_env.bash
   make test-all              # Run all tests
   ```

2. **Learn More:**
   - Read `README.md` for detailed usage
   - Read `QUICK_START.md` for common commands
   - Check `Makefile` for all available targets

3. **Run Regression:**
   ```bash
   perl regress.pl            # Full regression
   cat regress.rpt            # View report
   ```

4. **Customize:**
   - Edit `rtl.f` to add RTL files
   - Edit `tb.f` to add TB files
   - Edit `regress.cfg` to customize test list

## Support

If issues persist:

1. Check logs:
   ```bash
   tail -50 log/run.log
   ```

2. Run with verbose output:
   ```bash
   make debug TESTNAME=fusion_sanity_test
   ```

3. Verify environment:
   ```bash
   source ./project_env.bash
   env | grep FUSION_IP
   env | grep UVM_HOME
   ```

4. Check file permissions:
   ```bash
   ls -la *.f *.bash
   # Should have read permissions
   ```

---

**Installation Complete!** Ready to simulate. 🚀

