# Lava Mainnet Node Manager

Automated script for installing and managing a Lava node on Mainnet. The script includes binary installation, Cosmovisor setup, validator creation, and management of all node operations.

## 📋 Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Main Functions](#main-functions)
- [Detailed Function Descriptions](#detailed-function-descriptions)
- [Configuration](#configuration)
- [Useful Commands](#useful-commands)
- [Troubleshooting](#troubleshooting)

## 🔧 Requirements

- **OS**: Ubuntu 20.04+ / Debian 11+ (or other Linux distributions with systemd support)
- **RAM**: minimum 8 GB (16+ GB recommended)
- **Disk**: minimum 200 GB free space (SSD recommended)
- **CPU**: minimum 4 cores
- **Internet**: stable connection
- **Permissions**: root access for installation

## 🚀 Quick Start

1. Download the script:
```bash
wget --timestamping -q --output-document=lava_manager.sh https://raw.githubusercontent.com/Danzelitos/node_testing/refs/heads/main/lava_manager.sh && sudo chmod +x lava_manager.sh && bash lava_manager.sh
chmod +x lava_manager.sh
```

2. Run the script:
```bash
sudo ./lava_manager.sh
```

3. Follow the instructions in the interactive menu.

## 📦 Installation

### Automatic Installation

The script will automatically perform the following steps when selecting "Install node":

1. **System update** and installation of required packages
2. **Go 1.23.3 installation**
3. **Cosmovisor v1.6.0 installation** for upgrade management
4. **Binary compilation** version v5.5.1 from source
5. **Systemd service creation** for automatic startup
6. **Node initialization** with your MONIKER
7. **Genesis file download** and address book
8. **Snapshot download** for fast synchronization
9. **Service startup** and RPC availability check

### What Gets Installed

- **Binaries**: version v5.5.1 (genesis and upgrade)
- **Cosmovisor**: automatic upgrade management
- **Systemd service**: `/etc/systemd/system/lava.service`
- **Node data**: `/root/.lava/`
- **Configuration**: automatically optimized for validator operation

## 📖 Main Functions

The script provides an interactive menu with the following options:

### Main Menu

1. **Install node** - Complete Lava node installation
2. **Run validator** - Create validator with manual amount input
3. **Node management** - Node management submenu
4. **View logs** - View node logs
5. **Restart node** - Restart the node
6. **Delete node** - Delete node and all data

### Management Submenu (Node management)

1. **Unjail** - Unblock validator (unjail transaction)
2. **Check fee/balance** - Simulate validator creation with fee calculation
3. **Auto self-delegation** - Automatic self-delegation of entire balance
4. **Voting** - Vote on proposals

## 🔍 Detailed Function Descriptions

### 1. Install node

**What it does:**
- Installs all required dependencies
- Builds and installs lavad binaries
- Configures Cosmovisor for automatic upgrades
- Creates and configures systemd service
- Initializes node with your MONIKER
- Downloads genesis file and address book
- Downloads snapshot for fast synchronization
- Starts node and checks RPC availability

**Requires input:**
- MONIKER (validator name)
- WALLET (wallet name)

**Note:** After installation, the node will start syncing. Wait for full synchronization before creating a validator.

---

### 2. Run validator

**What it does:**
- Checks for wallet existence (offers import if missing)
- Checks node synchronization status
- Creates validator with specified self-delegation amount
- Shows information about the created validator

**Requires input:**
- Amount of LAVA for self-delegation
- Keyring password (if required)

**Validator parameters:**
- Commission rate: 10%
- Commission max rate: 20%
- Commission max change rate: 1%
- Min self-delegation: 10,000 ulava

---

### 3. Node Management → Unjail

**What it does:**
- Sends unjail transaction to unblock the validator
- Checks validator status after unjail

**When to use:**
- If your validator was jailed for misbehavior

---

### 4. Node Management → Check fee/balance

**What it does:**
- Shows current wallet balance
- Simulates validator creation (dry-run)
- Calculates required fees
- Checks if balance is sufficient for validator creation

**Useful for:**
- Checking balance before creating validator
- Calculating fees in advance
- Determining minimum amount for self-delegation

---

### 5. Node Management → Auto self-delegation

**What it does:**
- Shows current balance
- Requests reserve amount for fees
- Automatically delegates entire remaining balance:
  - If validator not created - creates it
  - If validator already created - delegates remainder

**Requires input:**
- Reserve for fees (default 1 LAVA)

---

### 6. Node Management → Voting

**What it does:**
- Shows list of active proposals
- Allows voting on selected proposal
- Shows confirmation of your vote

**Voting options:**
- `yes` - For
- `no` - Against
- `abstain` - Abstain
- `no_with_veto` - Against with veto

---

### 7. View logs

**What it does:**
- Shows node logs in real-time (journalctl -f)
- Allows monitoring node operation

**Exit:** `Ctrl+C`

---

### 8. Restart node

**What it does:**
- Reloads systemd daemon
- Restarts lava service
- Waits for RPC to come up
- Shows synchronization status

---

### 9. Delete node

**What it does:**
- Stops and disables service
- Deletes all node files
- Deletes binaries
- Removes systemd configuration

**⚠️ WARNING:** This operation is irreversible! All data will be deleted.

---

## ⚙️ Configuration

### Environment Variables

You can modify the following variables before running the script:

```bash
# Binary version
export LAVA_GENESIS_TAG="v5.5.1"
export LAVA_UPGRADE_TAGS="v5.5.1"

# Node data path
export LAVA_HOME="/root/.lava"

# Keyring settings
export KEYRING_BACKEND="file"
export KEYRING_DIR="$HOME/.lava"

# Public RPC (if local is unavailable)
export PUBLIC_RPC="https://lava-rpc.publicnode.com:443"
```

### Validator Parameters

Validator parameters are configured in the `run_validator()` function:
- Commission rate: `0.10` (10%)
- Commission max rate: `0.20` (20%)
- Commission max change rate: `0.01` (1%)
- Min self-delegation: `10000` ulava

### Gas Parameters

Gas settings can be modified in the `GAS_FLAGS` variable:
```bash
GAS_FLAGS="--gas auto --gas-adjustment 2.0 --gas-prices 0.05ulava"
```

## 💡 Useful Commands

### Check Node Status

```bash
# Service status
systemctl status lava

# Synchronization status
lavad status --node http://127.0.0.1:26657 | jq '.sync_info'

# Check blocks
curl -s http://127.0.0.1:26657/status | jq '.result.sync_info.latest_block_height'
```

### Service Management

```bash
# Stop
systemctl stop lava

# Start
systemctl start lava

# Restart
systemctl restart lava

# View logs
journalctl -u lava -f -o cat
```

### Wallet Operations

```bash
# List wallets
lavad keys list --keyring-backend file

# Show address
lavad keys show <wallet_name> -a --keyring-backend file

# Show validator address
lavad keys show <wallet_name> --bech val -a --keyring-backend file

# Balance
lavad q bank balances $(lavad keys show <wallet_name> -a --keyring-backend file)
```

### Validator Check

```bash
# Validator information
lavad q staking validator $(lavad keys show <wallet_name> --bech val -a --keyring-backend file)

# Validator status
lavad q staking validator $(lavad keys show <wallet_name> --bech val -a --keyring-backend file) | jq '.validator.status'
```

### Cosmovisor

```bash
# Check current version
cosmovisor version

# Check installed versions
ls -la /root/.lava/cosmovisor/upgrades/
```

## 🔧 Troubleshooting

### Node Not Syncing

1. Check logs: `journalctl -u lava -f -o cat`
2. Check internet connection
3. Check disk space: `df -h`
4. Try restarting: use "Restart node" menu option

### Error Creating Validator

1. Ensure node is fully synchronized
2. Check wallet balance
3. Use "Check fee/balance" option to verify sufficient funds
4. Make sure you have reserve for fees (minimum 1-2 LAVA)

### "account not found" Error

This error occurs when the wallet is created locally but has no funds on the network. Solution:
1. Fund the wallet from another wallet
2. Use the correct wallet address for funding

### RPC Unavailable

1. Check if service is running: `systemctl status lava`
2. Check logs for errors
3. Check port: `netstat -tuln | grep 26657`
4. Try restarting the node

### Validator Jailed

1. Use "Unjail" option from management menu
2. Ensure you have sufficient funds for fees
3. Check jailing reason in blockchain explorer

## 📝 Files and Directories

```
/root/.lava/                    # Main data directory
├── config/                     # Configuration files
│   ├── genesis.json           # Genesis file
│   ├── config.toml            # Node configuration
│   └── app.toml               # Application configuration
├── data/                      # Blockchain data
├── cosmovisor/                # Cosmovisor files
│   ├── genesis/bin/           # Genesis binary
│   ├── upgrades/              # Upgrades
│   └── current/               # Current version
└── manager.env                # Script saved settings

/etc/systemd/system/lava.service  # Systemd service
```

## 📞 Support

If you encounter issues:
1. Check the "Troubleshooting" section
2. Review node logs
3. Check Lava Network documentation: https://docs.lavanet.xyz/

## 📄 License

This script is provided "as is" without warranties of any kind.

## 🔄 Version

- **Script version**: 1.0
- **Lava version**: v5.5.1
- **Cosmovisor version**: v1.6.0
- **Go version**: 1.23.3

---

**Important:** Always backup your keys and seed phrases before any operations!

