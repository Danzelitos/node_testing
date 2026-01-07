#!/usr/bin/env bash
set -Eeuo pipefail

# ---------------------- Constants ----------------------
CHAIN_ID="lava-mainnet-1"
LAVA_VERSION="v5.5.1"
GENESIS_URL="https://snapshots.kjnodes.com/lava/genesis.json"
ADDRBOOK_URL="https://snapshots.kjnodes.com/lava/addrbook.json"
SEEDS="400f3d9e30b69e78a7fb891f60d76fa3c73f0ecc@lava.rpc.kjnodes.com:14459"
SNAPSHOT_STREAM="https://snapshots.kjnodes.com/lava/snapshot_latest.tar.lz4"
GAS_FLAGS="--gas auto --gas-adjustment 2.0 --gas-prices 0.05ulava"
KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
KEYRING_DIR="${KEYRING_DIR:-$HOME/.lava}"
HOME_DIR="$HOME"
LAVA_HOME="${LAVA_HOME:-/root/.lava}"
COMMON_KR_FLAGS=(--home "$LAVA_HOME" --keyring-backend "$KEYRING_BACKEND" --keyring-dir "$KEYRING_DIR")
SERVICE_FILE="/etc/systemd/system/lava.service"
STATE_FILE="$LAVA_HOME/manager.env"
PUBLIC_RPC="${PUBLIC_RPC:-https://lava-rpc.publicnode.com:443}"

# ---------------------- Colors ----------------------
CLR_ERROR='\033[0;31m'
CLR_SUCCESS='\033[0;32m'
CLR_WARNING='\033[0;33m'
CLR_INFO='\033[0;36m'
CLR_RESET='\033[0m'

msg(){ echo -e "${CLR_INFO}▶${CLR_RESET} $*"; }
ok(){  echo -e "${CLR_SUCCESS}✓${CLR_RESET} $*"; }
err(){ echo -e "${CLR_ERROR}✗${CLR_RESET} $*" >&2; }
warn(){ echo -e "${CLR_WARNING}⚠${CLR_RESET} $*"; }
pause(){ read -r -p "Press [Enter] to continue..."; }
need_cmd(){ command -v "$1" >/dev/null 2>&1; }

show_logo() {
    echo -e "${CLR_SUCCESS}===========================================================${CLR_RESET}"
    echo -e "${CLR_SUCCESS}          Lava mainnet node & validator Installer           ${CLR_RESET}"
    echo -e "${CLR_SUCCESS}===========================================================${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

rpc_url(){
  # return local RPC if alive, otherwise public
  if curl -sS --max-time 1 http://127.0.0.1:26657/status >/dev/null; then
    echo "http://127.0.0.1:26657"
  else
    echo "$PUBLIC_RPC"
  fi
}

wait_rpc() {
  local url="${1:-http://127.0.0.1:26657/status}"
  local tries=60
  msg "Waiting for RPC to come up (${url})..."
  for i in $(seq 1 $tries); do
    if curl -sS "$url" >/dev/null 2>&1; then
      ok "RPC is available"
      return 0
    fi
    sleep 2
  done
  err "RPC did not come up within $((tries*2)) sec — check logs: journalctl -u lava -f -o cat"
  return 1
}

ensure_vars(){
  mkdir -p "$LAVA_HOME"
  [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" || true
  if [[ -z "${MONIKER:-}" ]]; then
    read -r -p "Enter MONIKER (validator name): " MONIKER
  fi
  if [[ -z "${WALLET:-}" ]]; then
    read -r -p "Enter wallet name (WALLET): " WALLET
  fi
  cat > "$STATE_FILE" <<EOF
MONIKER="$MONIKER"
WALLET="$WALLET"
EOF
  ok "Settings saved: $STATE_FILE"
  echo ""
}

get_address(){
  lavad keys show "$WALLET" -a "${COMMON_KR_FLAGS[@]}"
}

get_valoper(){
  lavad keys show "$WALLET" --bech val -a "${COMMON_KR_FLAGS[@]}"
}

get_pubkey(){
  lavad tendermint show-validator --home "$LAVA_HOME"
}

is_synced(){
  local RPC; RPC=$(rpc_url)
  [[ "$(curl -s "$RPC/status" | jq -r '.result.sync_info.catching_up')" == "false" ]]
}

ulava_to_lava(){
  awk 'BEGIN{printf "%.6f\n",'$1'/1000000}'
}

lava_to_ulava(){
  awk 'BEGIN{printf "%.0f",'$1'*1000000}'
}

balance_ulava(){
  local RPC; RPC=$(rpc_url)
  local ADDR; ADDR=$(get_address)
  lavad q bank balances "$ADDR" --node "$RPC" -o json \
    | jq -r '.balances[]? | select(.denom=="ulava") | .amount' | head -n1 || true
}

# --- version settings (you can change if needed) ---
LAVA_GENESIS_TAG="${LAVA_GENESIS_TAG:-v5.5.1}"   # binary for startup (genesis)
LAVA_UPGRADE_TAGS=(${LAVA_UPGRADE_TAGS:-v5.5.1}) # binary(ies) for future upgrades

lava_build_version() {
  local tag="$1"
  msg "Building lavad ${tag}..."
  rm -rf /root/lava
  git clone -q https://github.com/lavanet/lava.git /root/lava
  cd /root/lava
  git fetch --tags -q && git checkout -q "$tag"
  export LAVA_BINARY=lavad
  # Suppress stdout, logs to stderr (or /dev/null), and check for binary
  if ! make build >/dev/null 2>&1; then
    err "make build failed for ${tag}"
    return 1
  fi
  if [ ! -x /root/lava/build/lavad ]; then
    err "build/lavad not found after building ${tag}"
    return 1
  fi
  # Only path in stdout!
  echo "/root/lava/build/lavad"
}

lava_install_genesis() {
  local tag="$1"
  local bin
  bin="$(lava_build_version "${tag}")"
  mkdir -p /root/.lava/cosmovisor/genesis/bin
  install -m 0755 "${bin}" /root/.lava/cosmovisor/genesis/bin/lavad
  rm -rf /root/lava/build
  ok "Genesis binary ${tag} installed"
}

lava_install_upgrade() {
  local tag="$1"
  # if already exists — skip
  if [ -x "/root/.lava/cosmovisor/upgrades/${tag}/bin/lavad" ]; then
    warn "Upgrade binary ${tag} already installed — skipping"
    return 0
  fi
  local bin
  bin="$(lava_build_version "${tag}")"
  mkdir -p "/root/.lava/cosmovisor/upgrades/${tag}/bin"
  install -m 0755 "${bin}" "/root/.lava/cosmovisor/upgrades/${tag}/bin/lavad"
  rm -rf /root/lava/build
  ok "Upgrade binary ${tag} installed"
}

lava_prepare_binaries() {
  lava_install_genesis "${LAVA_GENESIS_TAG}"
  for tag in "${LAVA_UPGRADE_TAGS[@]}"; do
    lava_install_upgrade "${tag}"
  done
  if [ -f /root/.lava/data/upgrade-info.json ]; then
    mkdir -p /root/.lava/cosmovisor/current
    cp /root/.lava/data/upgrade-info.json /root/.lava/cosmovisor/current/upgrade-info.json || true
  fi
}

install_node(){
  ensure_vars
  msg "Updating packages"
  apt update -y
  apt install -y unzip logrotate git jq lz4 sed wget curl make gcc tar coreutils

  msg "Go 1.23.3"
  if ! need_cmd go || ! go version | grep -q 'go1.23.3'; then
    wget -q https://go.dev/dl/go1.23.3.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.3.linux-amd64.tar.gz
    grep -q '/usr/local/go/bin' ~/.profile || echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    grep -q '$HOME/go/bin' ~/.profile || echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.profile
    : # skip sourcing profile in non-interactive run
  fi
  ok "Go: $(go version)"

  msg "Cosmovisor v1.6.0"
  need_cmd cosmovisor || go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.6.0

  msg "Systemd service"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=lava node service
After=network-online.target

[Service]
User=root
Environment="DAEMON_HOME=/root/.lava"
Environment="DAEMON_NAME=lavad"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/go/bin"
ExecStart=/root/go/bin/cosmovisor run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable lava.service
  
  lava_prepare_binaries
  ln -sfn "$LAVA_HOME/cosmovisor/genesis" "$LAVA_HOME/cosmovisor/current"
  ln -sf "$LAVA_HOME/cosmovisor/current/bin/lavad" /usr/local/bin/lavad

  msg "Initialization"
  lavad init "$MONIKER" --chain-id "$CHAIN_ID"
  curl -Ls "$GENESIS_URL" > "$LAVA_HOME/config/genesis.json"
  curl -Ls "$ADDRBOOK_URL" > "$LAVA_HOME/config/addrbook.json"
  sed -i -E "s|^seeds *=.*|seeds = \"${SEEDS}\"|" "$LAVA_HOME/config/config.toml"
  sed -i -E 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.000000001ulava"|' "$LAVA_HOME/config/app.toml"
  sed -i \
    -e 's|^pruning *=.*|pruning = "custom"|' \
    -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
    -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
    -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
    "$LAVA_HOME/config/app.toml"
  sed -i \
    -e 's/timeout_commit = ".*"/timeout_commit = "30s"/g' \
    -e 's/timeout_propose = ".*"/timeout_propose = "1s"/g' \
    -e 's/timeout_precommit = ".*"/timeout_precommit = "1s"/g' \
    -e 's/timeout_precommit_delta = ".*"/timeout_precommit_delta = "500ms"/g' \
    -e 's/timeout_prevote = ".*"/timeout_prevote = "1s"/g' \
    -e 's/timeout_prevote_delta = ".*"/timeout_prevote_delta = "500ms"/g' \
    -e 's/timeout_propose_delta = ".*"/timeout_propose_delta = "500ms"/g' \
    -e 's/skip_timeout_commit = .*/skip_timeout_commit = false/g' \
    "$LAVA_HOME/config/config.toml"

  msg "Snapshot (stream)"
  systemctl stop lava || true
  lavad tendermint unsafe-reset-all --home "$LAVA_HOME" --keep-addr-book
  curl -L "$SNAPSHOT_STREAM" | tar -I lz4 -xf - -C "$LAVA_HOME"
  [[ -f "$LAVA_HOME/data/upgrade-info.json" ]] && cp "$LAVA_HOME/data/upgrade-info.json" "$LAVA_HOME/cosmovisor/genesis/upgrade-info.json"

  msg "Starting service"
  systemctl start lava
  wait_rpc "http://127.0.0.1:26657/status" || true
  curl -s "http://127.0.0.1:26657/status" | jq '.result.sync_info | {catching_up, latest_block_height}' || true
  sleep 2
  ok "Installation completed"
}

# --- Keyring (common flags for all commands) ---

wallet_exists() {
  lavad keys show "$1" "${COMMON_KR_FLAGS[@]}" >/dev/null 2>&1
}

import_wallet_menu() {
  msg "Import wallet '$WALLET':"
  echo "  1) Seed phrase (recover)"
  echo "  2) Keystore file (keys import)"
  echo "  3) Ledger"
  echo ""
  read -rp "Choice [1/2/3]: " mode
  echo ""
  case "$mode" in
    1) 
      msg "Recovering wallet from seed phrase..."
      msg "You will be prompted for:"
      msg "  1. Keyring passphrase (create new or enter existing)"
      msg "  2. BIP39 mnemonic phrase"
      echo ""
      lavad keys add "$WALLET" --recover "${COMMON_KR_FLAGS[@]}" 2>&1
      echo ""
      ;;
    2) 
      read -rp "Path to export file: " FILE
      [ -f "$FILE" ] || { err "File not found"; return 1; }
      echo ""
      msg "Importing wallet from keystore file..."
      lavad keys import "$WALLET" "$FILE" "${COMMON_KR_FLAGS[@]}" 2>&1
      echo ""
      ;;
    3) 
      msg "Adding wallet from Ledger..."
      lavad keys add "$WALLET" --ledger "${COMMON_KR_FLAGS[@]}" 2>&1
      echo ""
      ;;
    *) err "Invalid choice"; return 1 ;;
  esac
}

ensure_wallet_imported() {
  if wallet_exists "$WALLET"; then
    ok "Key '$WALLET' found"
  else
    warn "Key '$WALLET' not found — importing"
    import_wallet_menu || return 1
    wallet_exists "$WALLET" || { err "Import failed"; return 1; }
  fi
  # show addresses
  echo ""
  msg "Showing wallet addresses (enter passphrase when prompted)"
  echo ""
  echo -n "Account:  "
  lavad keys show "$WALLET" -a "${COMMON_KR_FLAGS[@]}" 2>&1
  echo -n "ValOper:  "
  lavad keys show "$WALLET" --bech val -a "${COMMON_KR_FLAGS[@]}" 2>&1
  echo ""
}



run_validator(){
  ensure_vars
  ensure_wallet_imported || return 1

  if ! is_synced; then err "Node is still syncing (catching_up=true)"; return 1; fi

  local AMOUNT_LAVA AMOUNT_ULAVA
  read -r -p "How much LAVA to delegate when creating? (example: 4600): " AMOUNT_LAVA
  AMOUNT_ULAVA=$(lava_to_ulava "$AMOUNT_LAVA")
  lavad tx staking create-validator \
    --amount "${AMOUNT_ULAVA}ulava" \
    --pubkey "$(get_pubkey)" \
    --moniker "$MONIKER" \
    --chain-id "$CHAIN_ID" \
    --commission-rate "0.10" \
    --commission-max-rate "0.20" \
    --commission-max-change-rate "0.01" \
    --min-self-delegation "10000" \
    --from "$WALLET" \
    "${COMMON_KR_FLAGS[@]}" ${GAS_FLAGS} -y
  local VALOPER; VALOPER=$(get_valoper)
  lavad q staking validator "$VALOPER" -o json "${COMMON_KR_FLAGS[@]}" | jq '.validator | {jailed,status,tokens,delegator_shares}' || true
}

unjail_validator(){
  ensure_vars
  local RPC; RPC=$(rpc_url)
  msg "Sending unjail via $RPC"
  if lavad tx slashing unjail \
       --from "$WALLET" --chain-id "$CHAIN_ID" --node "$RPC" \
       "${COMMON_KR_FLAGS[@]}" ${GAS_FLAGS} -y; then
    ok "Tx sent. Checking status:"
    local VALOPER; VALOPER=$(get_valoper)
    lavad q staking validator "$VALOPER" --node "$RPC" -o json "${COMMON_KR_FLAGS[@]}" \
      | jq '.validator | {jailed,status}' || true
  else
    err "Failed to execute unjail (check balance and gas)"
  fi
}

simulate_create_val(){
  ensure_vars
  if ! is_synced; then err "catching_up=true — wait for full sync"; return 1; fi
  local RPC; RPC=$(rpc_url)
  local bal_ulava; bal_ulava=$(balance_ulava); bal_ulava=${bal_ulava:-0}
  local bal_lava; bal_lava=$(ulava_to_lava "${bal_ulava:-0}")
  msg "Balance: ${bal_lava} LAVA"

  local AMOUNT_LAVA; read -r -p "Planned self-delegation (LAVA): " AMOUNT_LAVA
  local AMOUNT_ULAVA; AMOUNT_ULAVA=$(lava_to_ulava "$AMOUNT_LAVA")

  msg "Simulating create-validator (dry-run)"
  set +e
  local out; out=$(lavad tx staking create-validator \
    --amount "${AMOUNT_ULAVA}ulava" \
    --pubkey "$(get_pubkey)" \
    --moniker "$MONIKER" \
    --chain-id "$CHAIN_ID" \
    --commission-rate "0.10" \
    --commission-max-rate "0.20" \
    --commission-max-change-rate "0.01" \
    --min-self-delegation "10000" \
    --from "$WALLET" "${COMMON_KR_FLAGS[@]}" ${GAS_FLAGS} --dry-run 2>&1)
  set -e
  echo "$out" | tail -n 5
  local gas; gas=$(echo "$out" | grep -Po 'gas estimate:\s*\K[0-9]+' || echo 0)
  local gp="0.05"
  local fee_ulava; fee_ulava=$(awk -v g="$gas" -v p="$gp" 'BEGIN{printf "%.0f", g*(p*1000000)}')
  local fee_lava; fee_lava=$(ulava_to_lava "$fee_ulava")
  ok "Gas estimate: $gas; Fee estimate ≈ ${fee_lava} LAVA"

  local reserve_ulava=$(lava_to_ulava 1)
  local need_ulava=$(( AMOUNT_ULAVA + fee_ulava + reserve_ulava ))
  if (( bal_ulava >= need_ulava )); then
    ok "Balance sufficient: self-delegation + fees + 1 LAVA reserve"
  else
    err "Insufficient balance. Required ≥ $(ulava_to_lava "$need_ulava") LAVA"
  fi
}

auto_self_amount(){
  ensure_vars
  if ! is_synced; then err "catching_up=true — wait for full sync"; return 1; fi
  local bal_ulava; bal_ulava=$(balance_ulava); bal_ulava=${bal_ulava:-0}
  local bal_lava; bal_lava=$(ulava_to_lava "$bal_ulava")
  msg "Current balance: ${bal_lava} LAVA"

  local reserve_lava; read -r -p "Reserve for fees (LAVA, default 1): " reserve_lava
  reserve_lava=${reserve_lava:-1}
  local reserve_ulava; reserve_ulava=$(lava_to_ulava "$reserve_lava")

  if (( bal_ulava <= reserve_ulava )); then
    err "Balance ≤ reserve. Nothing to delegate."
    return 1
  fi

  local amount_ulava=$(( bal_ulava - reserve_ulava ))
  local amount_lava; amount_lava=$(ulava_to_lava "$amount_ulava")
  msg "Will be used for delegation: ${amount_lava} LAVA"

  local RPC; RPC=$(rpc_url)
  local VALOPER; VALOPER=$(get_valoper || true)
  local status; status=$(lavad q staking validator "$VALOPER" --node "$RPC" -o json "${COMMON_KR_FLAGS[@]}" 2>/dev/null | jq -r '.validator.status // empty')
  if [[ -z "$status" || "$status" == "null" ]]; then
    msg "Validator not created yet — executing create-validator"
    lavad tx staking create-validator \
      --amount "${amount_ulava}ulava" \
      --pubkey "$(get_pubkey)" \
      --moniker "$MONIKER" \
      --chain-id "$CHAIN_ID" \
      --commission-rate "0.10" \
      --commission-max-rate "0.20" \
      --commission-max-change-rate "0.01" \
      --min-self-delegation "10000" \
      --from "$WALLET" "${COMMON_KR_FLAGS[@]}" ${GAS_FLAGS} -y
  else
    msg "Validator found (status=$status) — delegating remainder"
    lavad tx staking delegate "$VALOPER" "${amount_ulava}ulava" \
      --from "$WALLET" --chain-id "$CHAIN_ID" "${COMMON_KR_FLAGS[@]}" ${GAS_FLAGS} -y
  fi
}

list_and_vote(){
  ensure_vars
  local RPC; RPC=$(rpc_url)
  msg "Active proposals (Voting period):"
  lavad q gov proposals --status voting_period --node "$RPC" -o json "${COMMON_KR_FLAGS[@]}" 2>/dev/null \
    | jq -r '.proposals[]? | [.id,(.title//.metadata//"n/a"),.status,(.voting_end_time//.voting_end||"")] | @tsv' \
    | awk -F'\t' 'BEGIN{printf "ID\tSTATUS\tVOTING_END\tTITLE\n"}{printf "%s\t%s\t%s\t%s\n",$1,$3,$4,$2}' || warn "No active proposals"

  read -r -p "Proposal ID to vote: " PID
  echo "Options: yes / no / abstain / no_with_veto"
  read -r -p "Your vote: " VOTE
  VOTE=$(echo "$VOTE" | tr '[:upper:]' '[:lower:]')
  case "$VOTE" in
    yes|no|abstain|no_with_veto) ;;
    *) err "Invalid option"; return 1 ;;
  esac

  lavad tx gov vote "$PID" "$VOTE" \
    --from "$WALLET" --chain-id "$CHAIN_ID" --node "$RPC" "${COMMON_KR_FLAGS[@]}" ${GAS_FLAGS} -y

  ok "Sent. Checking vote record:"
  local ADDR; ADDR=$(get_address)
  lavad q gov vote "$PID" "$ADDR" --node "$RPC" -o json "${COMMON_KR_FLAGS[@]}" 2>/dev/null \
    | jq '{proposal_id, voter, options}' || true
}

check_sync_status(){
  local LOCAL_RPC="http://127.0.0.1:26657"
  local local_status public_status local_height public_height catching_up sync_percent
  
  msg "Checking node synchronization status..."
  echo ""
  
  # Check local node
  if curl -sS --max-time 2 "$LOCAL_RPC/status" >/dev/null 2>&1; then
    local_status=$(curl -sS "$LOCAL_RPC/status" 2>/dev/null)
    if [ -n "$local_status" ]; then
      local_height=$(echo "$local_status" | jq -r '.result.sync_info.latest_block_height // "N/A"' 2>/dev/null)
      catching_up=$(echo "$local_status" | jq -r '.result.sync_info.catching_up // "N/A"' 2>/dev/null)
      
      echo -e "${CLR_INFO}Local Node:${CLR_RESET}"
      echo "  Block Height: $local_height"
      echo "  Catching Up: $catching_up"
      echo ""
    else
      warn "Could not get local node status"
    fi
  else
    warn "Local RPC is not available (node may be stopped)"
    echo ""
  fi
  
  # Check public network
  if curl -sS --max-time 5 "$PUBLIC_RPC/status" >/dev/null 2>&1; then
    public_status=$(curl -sS "$PUBLIC_RPC/status" 2>/dev/null)
    if [ -n "$public_status" ]; then
      public_height=$(echo "$public_status" | jq -r '.result.sync_info.latest_block_height // "N/A"' 2>/dev/null)
      
      echo -e "${CLR_INFO}Network (Public RPC):${CLR_RESET}"
      echo "  Block Height: $public_height"
      echo ""
      
      # Calculate sync percentage if both heights are available
      if [ "$local_height" != "N/A" ] && [ "$public_height" != "N/A" ] && [ -n "$local_height" ] && [ -n "$public_height" ]; then
        if [ "$public_height" -gt 0 ] 2>/dev/null; then
          sync_percent=$(awk -v local="$local_height" -v public="$public_height" 'BEGIN {
            if (public > 0) {
              percent = (local / public) * 100
              printf "%.2f", percent
            } else {
              print "0.00"
            }
          }')
          echo -e "${CLR_INFO}Sync Status:${CLR_RESET}"
          echo "  Progress: ${sync_percent}%"
          echo "  Blocks behind: $((public_height - local_height))"
          echo ""
          
          if [ "$catching_up" = "false" ]; then
            ok "Node is fully synchronized"
          elif [ "$catching_up" = "true" ]; then
            warn "Node is still syncing"
          fi
        fi
      fi
    else
      warn "Could not get network status from public RPC"
    fi
  else
    warn "Public RPC is not available"
  fi
  
  echo ""
  msg "Additional Info:"
  if [ "$catching_up" = "false" ]; then
    ok "Node is ready for validator operations"
  elif [ "$catching_up" = "true" ]; then
    warn "Wait for full synchronization before creating validator"
  fi
}


show_logs(){ 
  journalctl -u lava -f -o cat || true
  }

restart_node(){ 
  systemctl daemon-reload
  systemctl restart lava
  wait_rpc "http://127.0.0.1:26657/status" || true
  sleep 1
  curl -s "$(rpc_url)/status" | jq -r '.result.sync_info | {catching_up, latest_block_height}' || true
  }

delete_node(){
  systemctl stop lava || true
  systemctl disable lava || true
  rm -f "$SERVICE_FILE"; systemctl daemon-reload
  rm -rf "$LAVA_HOME" "$HOME_DIR/lava" /usr/local/bin/lavad
  ok "Deleted"
}

submenu_manage(){
  while true; do
    echo ""
    echo "---- Node Management ----"
    echo -e "${CLR_INFO}1) Unjail${CLR_RESET}"
    echo -e "${CLR_INFO}2) Check fee/balance before create-validator (simulation)${CLR_RESET}"
    echo -e "${CLR_INFO}3) Auto self-delegation from balance (will create validator or delegate remainder)${CLR_RESET}"
    echo -e "${CLR_INFO}4) Voting (Proposals)${CLR_RESET}"
    echo -e "${CLR_INFO}5) Check sync status and block height${CLR_RESET}"
    echo -e "${CLR_INFO}0) Back${CLR_RESET}"
    echo -ne "${CLR_INFO}Choice: ${CLR_RESET}"
    read -r x
    case "$x" in
      1) unjail_validator; pause ;;
      2) simulate_create_val; pause ;;
      3) auto_self_amount; pause ;;
      4) list_and_vote; pause ;;
      5) check_sync_status; pause ;;
      0) break ;;
      *) warn "Invalid choice" ; pause ;;
    esac
  done
}

menu(){
  show_logo
  echo ""
  echo -e "${CLR_INFO}1) Install node${CLR_RESET}"
  echo -e "${CLR_INFO}2) Run validator (manual amount input)${CLR_RESET}"
  echo -e "${CLR_INFO}3) Node management → (unjail / fee-check / auto self-delegation / voting)${CLR_RESET}"
  echo -e "${CLR_INFO}4) View logs${CLR_RESET}"
  echo -e "${CLR_INFO}5) Restart node${CLR_RESET}"
  echo -e "${CLR_INFO}6) Delete node${CLR_RESET}"
  echo -e "${CLR_INFO}0) Exit${CLR_RESET}"
  echo ""
  echo -ne "${CLR_INFO}Choice: ${CLR_RESET}"
  read -r ch
  case "$ch" in
    1) install_node; pause ;;
    2) run_validator; pause ;;
    3) submenu_manage ;;
    4) show_logs ;;
    5) restart_node; pause ;;
    6) delete_node; pause ;;
    0) exit 0 ;;
    *) warn "Unknown option"; pause ;;
  esac
}

while true; do menu; done
