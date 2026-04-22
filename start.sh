#!/bin/bash

set -e

HP_NODE_DIR="${HOME}/hp-node"
CONFIG_DIR="${HP_NODE_DIR}/configs"

# ─────────────────────────────────────────
# Network configuration (set via --network flag, default: testnet)
# ─────────────────────────────────────────
NETWORK="testnet"

set_network_config() {
  case "$NETWORK" in
    mainnet)
      IMAGE_NAME="ghcr.io/humanity-org/hp-verification-node-plugin:latest"
      RPC_URL="https://humanity-mainnet.g.alchemy.com/public"
      DELEGATION_HUB="0x2cD43813903c48E0BDb6699E992eB8216dCEf48D"
      LICENSE_NFT="0x7a888bF4ec4FA9653B79B089736647024Ff0Aa30"
      ;;
    testnet|*)
      IMAGE_NAME="ghcr.io/humanity-org/hp-verification-node-plugin:testnet"
      RPC_URL="https://humanity-testnet.g.alchemy.com/public"
      DELEGATION_HUB="0x1aEbB36b9A6B33E377319a7E2d928BE54d0cB68e"
      LICENSE_NFT="0xF04f1062D70432d167EB9f342b98063228c6b496"
      ;;
  esac
}
# Function selectors (keccak256 first 4 bytes)
SEL_GET_INCOMING_DELEGATIONS="0xe2ae2879"        # getIncomingDelegations(address,uint256,uint256)
SEL_GET_INCOMING_DELEGATION_OFFERS="0x49ceece3"  # getIncomingDelegationOffers(address,uint256,uint256)
SEL_OWNER_OF="0x6352211e"                        # ownerOf(uint256)
POLL_INTERVAL=10

# ─────────────────────────────────────────
# Parse CLI arguments
# ─────────────────────────────────────────
show_help() {
  echo "Usage: ./start.sh [options]"
  echo ""
  echo "Options:"
  echo "  --owner-address <address>      License NFT holder's Ethereum address"
  echo "  --private-key <private_key>    Private key for transaction signing (without 0x prefix)"
  echo "  --container-name <name>        Custom container name (default: hp-verification-node-plugin)"
  echo "  --network <testnet|mainnet>    Select network (default: testnet)"
  echo "  --rpc <url>                    Override default RPC URL for the selected network"
  echo "  --node-version <version>       Override node version from config (e.g. 1.2.0)"
  echo "  --restart                      Restart using saved config (skip interactive wizard)"
  echo "  -v, --verbose                  Enable debug-level logging in the node"
  echo "  -h, --help                     Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./start.sh                                                          # Full interactive wizard"
  echo "  ./start.sh --restart                                                # Restart with saved config"
  echo "  ./start.sh --restart --container-name my-node                       # Restart a specific node"
  echo "  ./start.sh --owner-address 0x1234...abcd                            # Skip owner address step"
  echo "  ./start.sh --owner-address 0x1234... --private-key abcd1234...      # Skip owner & key steps"
  echo "  ./start.sh --owner-address 0x1234... --container-name my-node       # Skip owner & name steps"
  echo "  ./start.sh --restart --node-version 1.2.0                           # Restart with specific node version"
  echo ""
  echo "One-liner (curl):"
  echo "  curl -sSL https://raw.githubusercontent.com/humanity-org/hp-verification-node-plugin/main/start.sh | bash -s -- --owner-address 0x1234..."
  exit 0
}

ARG_OWNER=""
ARG_KEY=""
ARG_NAME=""
ARG_RPC=""
ARG_NODE_VERSION=""
DEFAULT_OWNER=""
DEFAULT_KEY=""
DEFAULT_NAME=""
VERBOSE="false"
LOG_LEVEL="info"
RESTART="false"
FORCE_NEW_WALLET="false"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    --owner-address)
      ARG_OWNER="$2"
      shift 2
      ;;
    --private-key)
      ARG_KEY="$2"
      shift 2
      ;;
    --container-name)
      ARG_NAME="$2"
      shift 2
      ;;
    --network)
      NETWORK="$2"
      shift 2
      ;;
    --rpc)
      ARG_RPC="$2"
      shift 2
      ;;
    --node-version)
      ARG_NODE_VERSION="$2"
      shift 2
      ;;
    --restart)
      RESTART="true"
      shift
      ;;
    -v|--verbose)
      VERBOSE="true"
      LOG_LEVEL="debug"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run './start.sh --help' for usage."
      exit 1
      ;;
  esac
done

# Apply network configuration based on --network flag
set_network_config

# Override RPC URL if user supplied --rpc
if [ -n "$ARG_RPC" ]; then
  RPC_URL="$ARG_RPC"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

print_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}=========================================${NC}"
  echo -e "${CYAN}${BOLD}  Humanity Protocol - Node Setup Wizard  ${NC}"
  echo -e "${CYAN}${BOLD}=========================================${NC}"
  echo ""
}

print_step() {
  local step=$1
  local total=$2
  local title=$3
  local show_back=${4:-true}
  echo ""
  echo -e "${GREEN}${BOLD}[Step ${step}/${total}] ${title}${NC}"
  echo -e "${DIM}─────────────────────────────────────────${NC}"
  if [ "$show_back" = "true" ] && [ "$step" -gt 1 ] && [ "$step" -le "$total" ]; then
    echo -e "${DIM}  Type 'b' to go back to the previous step.${NC}"
  fi
}

print_info() {
  echo -e "${CYAN}  ℹ  ${NC}$1"
}

print_warn() {
  echo -e "${YELLOW}  ⚠  ${NC}$1"
}

print_error() {
  echo -e "${RED}  ✗  ${NC}$1"
}

print_success() {
  echo -e "${GREEN}  ✓  ${NC}$1"
}

# Save configuration for a container
save_config() {
  mkdir -p "$CONFIG_DIR"
  local config_file="${CONFIG_DIR}/${CONTAINER_NAME}.conf"
  cat > "$config_file" << EOF
# HP Verification Node configuration (auto-generated)
# Container: ${CONTAINER_NAME}
OWNER_ADDRESS=${OWNER_ADDRESS}
CONTAINER_NAME=${CONTAINER_NAME}
HAS_CUSTOM_KEY=${HAS_CUSTOM_KEY}
ETH_PRIVATE_KEY=${ETH_PRIVATE_KEY}
LOG_LEVEL=${LOG_LEVEL}
EOF
  chmod 600 "$config_file"
}

# Load configuration for a container
load_config() {
  local name=$1
  local config_file="${CONFIG_DIR}/${name}.conf"
  if [ -f "$config_file" ]; then
    source "$config_file"
    return 0
  fi
  return 1
}

# List saved configurations
list_configs() {
  if [ -d "$CONFIG_DIR" ] && ls "$CONFIG_DIR"/*.conf &>/dev/null; then
    return 0
  fi
  return 1
}

# ─────────────────────────────────────────
# Ethereum address derivation (openssl)
# ─────────────────────────────────────────

# Derive Ethereum address from a hex private key (without 0x prefix).
# Requires openssl 3.x with keccak-256 support.
# Prints the checksumless 0x-prefixed address on success, returns 1 on failure.
derive_eth_address() {
  local privkey_hex="$1"

  # Run the entire derivation in a subshell with errexit disabled,
  # so failures here never kill the main script under set -e.
  local _addr
  _addr=$(
    set +e
    # Sanity: need openssl with keccak-256
    if ! openssl dgst -keccak-256 /dev/null >/dev/null 2>&1; then
      exit 1
    fi

    # Build minimal DER-encoded secp256k1 EC private key:
    #   SEQUENCE { INTEGER(1), OCTET_STRING(32-byte key), [0] OID(secp256k1) }
    der_hex="302e0201010420${privkey_hex}a00706052b8104000a"

    # Extract uncompressed public key (65 bytes: 04 || x || y)
    pub_der=$(echo "$der_hex" | xxd -r -p | openssl ec -inform DER -pubout -outform DER 2>/dev/null | xxd -p | tr -d '\n')
    if [ -z "$pub_der" ]; then
      exit 1
    fi

    # Last 130 hex chars = 65 bytes uncompressed key; drop first 2 chars (0x04 prefix) → 128 hex = 64 bytes
    pub_xy="${pub_der: -128}"

    # Keccak-256 hash of the 64-byte public key
    keccak=$(echo "$pub_xy" | xxd -r -p | openssl dgst -keccak-256 -hex 2>/dev/null | sed 's/.*= //')
    if [ -z "$keccak" ]; then
      exit 1
    fi

    # Ethereum address = last 20 bytes (40 hex chars)
    echo "0x${keccak: -40}"
  ) || true

  if [ -n "$_addr" ]; then
    echo "$_addr"
    return 0
  fi
  return 1
}

# Write flohive-cache.json with the given private key and (optionally) derived address.
# If openssl can derive the address, writes both; otherwise writes key only (easeflow fills address).
# Prints the derived address on stdout if available, empty string otherwise.
# Usage: write_wallet_cache <data_dir> <privkey_hex_no_0x>
write_wallet_cache() {
  local data_dir="$1"
  local privkey_hex="$2"
  local address

  address=$(derive_eth_address "$privkey_hex" 2>/dev/null) || address=""

  mkdir -p "$data_dir"
  if [ -n "$address" ]; then
    cat > "${data_dir}/flohive-cache.json" << EOF
{"burnerWallet":{"privateKey":"${privkey_hex}","address":"${address}"}}
EOF
  else
    # Fallback: write key only — easeflow will read it from cache and derive the address
    cat > "${data_dir}/flohive-cache.json" << EOF
{"burnerWallet":{"privateKey":"${privkey_hex}","address":""}}
EOF
  fi
  echo "$address"
}

# ─────────────────────────────────────────
# RPC helper functions (pure bash + curl)
# ─────────────────────────────────────────

# Make a JSON-RPC call and return the result field
rpc_call() {
  local payload="$1"
  local response
  response=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)
  # Extract "result" field without jq
  echo "$response" | grep -o '"result":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Check gas balance. Prints the balance hex to stdout. Returns 0 if funded, 1 if zero.
check_gas_funded() {
  local address="$1"
  local result
  result=$(rpc_call "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"${address}\",\"latest\"],\"id\":1}")

  echo "$result"  # always output the raw hex for display

  if [ -z "$result" ] || [ "$result" = "0x0" ] || [ "$result" = "0x" ]; then
    return 1
  fi
  return 0
}

# Convert hex balance (wei, 18 decimals) to human-readable "X.XXX HP"
hex_to_display_balance() {
  local hex="${1#0x}"
  if [ -z "$hex" ] || [ "$hex" = "0" ]; then
    echo "0 HP"
    return
  fi

  # Convert hex to decimal string using bc (available on macOS/Linux)
  local dec
  dec=$(echo "ibase=16; $(echo "$hex" | tr 'a-f' 'A-F')" | bc 2>/dev/null)

  if [ -z "$dec" ] || [ "$dec" = "0" ]; then
    echo "< 0.001 HP"
    return
  fi

  # Pad to at least 19 chars so we can split at 18 decimals
  while [ "${#dec}" -le 18 ]; do
    dec="0${dec}"
  done

  local int_part="${dec:0:${#dec}-18}"
  local frac_part="${dec:${#dec}-18:3}"  # first 3 decimal places

  # Remove leading zeros from integer part
  int_part=$(echo "$int_part" | sed 's/^0*//')
  [ -z "$int_part" ] && int_part="0"

  if [ "$int_part" = "0" ] && [ "$frac_part" = "000" ]; then
    echo "< 0.001 HP"
  else
    echo "${int_part}.${frac_part} HP"
  fi
}

# Make an eth_call and return the hex result (without 0x prefix)
eth_call() {
  local to="$1"
  local data="$2"
  local result
  result=$(rpc_call "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"${to}\",\"data\":\"${data}\"},\"latest\"],\"id\":1}")
  # Strip 0x prefix
  echo "${result#0x}"
}

# Check delegation: getIncomingDelegations(burnerAddress) on DelegationHub,
# then for each enabled delegation, check ownerOf(tokenId) on NFT contract.
# Returns 0 if owner delegation found, 1 otherwise.
check_delegation() {
  local burner_address="$1"
  local owner_address="$2"

  # Normalize addresses to lowercase for comparison
  local owner_lower
  owner_lower=$(echo "$owner_address" | tr '[:upper:]' '[:lower:]')

  # ABI encode: selector + address(32) + offset=0(32) + limit=100(32)
  local addr_no_prefix="${burner_address#0x}"
  local padded_addr
  padded_addr=$(printf '%064s' "$addr_no_prefix" | tr ' ' '0')
  local padded_offset="0000000000000000000000000000000000000000000000000000000000000000"
  local padded_limit="0000000000000000000000000000000000000000000000000000000000000064"  # 100
  local calldata="${SEL_GET_INCOMING_DELEGATIONS}${padded_addr}${padded_offset}${padded_limit}"

  local hex_result
  hex_result=$(eth_call "$DELEGATION_HUB" "$calldata")

  if [ -z "$hex_result" ]; then
    return 1
  fi

  # Parse ABI-encoded Delegation[] response
  # Layout: offset (32 bytes) | length (32 bytes) | N structs
  # Each struct: hash(32) + to(32) + tokenId(32) + commissionPercentage(32) + enabled(32) = 160 bytes = 320 hex chars

  # Get array length (at position 64..128 in hex, i.e. bytes 32..63)
  local array_len_hex="${hex_result:64:64}"
  local array_len
  array_len=$(printf "%d" "0x${array_len_hex}" 2>/dev/null) || array_len=0

  if [ "$array_len" -eq 0 ]; then
    return 1
  fi

  # Parse each delegation struct
  local struct_start=128  # hex offset where first struct begins (after offset + length = 64+64=128 hex chars)
  local struct_size=320   # 5 * 64 hex chars

  local i=0
  while [ "$i" -lt "$array_len" ]; do
    local offset=$((struct_start + i * struct_size))

    # Extract fields (each 64 hex chars)
    # local d_hash="${hex_result:$offset:64}"             # bytes32 hash
    # local d_to="${hex_result:$((offset + 64)):64}"      # address to
    local d_token_id="${hex_result:$((offset + 128)):64}"  # uint256 tokenId
    # local d_commission="${hex_result:$((offset + 192)):64}" # uint32 commissionPercentage
    local d_enabled="${hex_result:$((offset + 256)):64}"   # bool enabled

    # Check if enabled (last byte != 0)
    local enabled_val
    enabled_val=$(printf "%d" "0x${d_enabled}" 2>/dev/null) || enabled_val=0

    if [ "$enabled_val" -ne 0 ]; then
      # Call ownerOf(tokenId) on NFT contract
      local owner_calldata="${SEL_OWNER_OF}${d_token_id}"
      local owner_result
      owner_result=$(eth_call "$LICENSE_NFT" "$owner_calldata")

      if [ -n "$owner_result" ]; then
        # Extract address from 32-byte response (last 40 hex chars)
        local nft_owner="0x${owner_result:24:40}"
        local nft_owner_lower
        nft_owner_lower=$(echo "$nft_owner" | tr '[:upper:]' '[:lower:]')

        if [ "$nft_owner_lower" = "$owner_lower" ]; then
          return 0
        fi
      fi
    fi

    i=$((i + 1))
  done

  return 1
}

# Check if there is a pending delegation offer from the owner.
# getIncomingDelegationOffers(address to, uint256 offset, uint256 limit)
# DelegationOffer struct: hash(32) + to(32) + from(32) + tokenId(32) + commissionPercentage(32) + enabled(32) = 192 bytes = 384 hex chars
# Returns 0 if a matching offer found, 1 otherwise.
check_delegation_offer() {
  local burner_address="$1"
  local owner_address="$2"

  local owner_lower
  owner_lower=$(echo "$owner_address" | tr '[:upper:]' '[:lower:]')

  # ABI encode: selector + address(32) + offset=0(32) + limit=100(32)
  local addr_no_prefix="${burner_address#0x}"
  local padded_addr
  padded_addr=$(printf '%064s' "$addr_no_prefix" | tr ' ' '0')
  local padded_offset="0000000000000000000000000000000000000000000000000000000000000000"
  local padded_limit="0000000000000000000000000000000000000000000000000000000000000064"  # 100
  local calldata="${SEL_GET_INCOMING_DELEGATION_OFFERS}${padded_addr}${padded_offset}${padded_limit}"

  local hex_result
  hex_result=$(eth_call "$DELEGATION_HUB" "$calldata")

  if [ -z "$hex_result" ]; then
    return 1
  fi

  # Parse ABI-encoded DelegationOffer[] response
  # Layout: offset (32 bytes) | length (32 bytes) | N structs
  local array_len_hex="${hex_result:64:64}"
  local array_len
  array_len=$(printf "%d" "0x${array_len_hex}" 2>/dev/null) || array_len=0

  if [ "$array_len" -eq 0 ]; then
    return 1
  fi

  # Each struct: 6 fields x 64 hex = 384 hex chars
  local struct_start=128
  local struct_size=384

  local i=0
  while [ "$i" -lt "$array_len" ]; do
    local offset=$((struct_start + i * struct_size))

    # DelegationOffer fields:
    # hash(64) + to(64) + from(64) + tokenId(64) + commissionPercentage(64) + enabled(64)
    local d_from="${hex_result:$((offset + 128)):64}"    # address from (3rd field)
    local d_enabled="${hex_result:$((offset + 320)):64}"  # bool enabled (6th field)

    local enabled_val
    enabled_val=$(printf "%d" "0x${d_enabled}" 2>/dev/null) || enabled_val=0

    if [ "$enabled_val" -ne 0 ]; then
      # Extract from address (last 40 hex chars of the 32-byte field)
      local offer_from="0x${d_from:24:40}"
      local offer_from_lower
      offer_from_lower=$(echo "$offer_from" | tr '[:upper:]' '[:lower:]')

      if [ "$offer_from_lower" = "$owner_lower" ]; then
        return 0
      fi
    fi

    i=$((i + 1))
  done

  return 1
}

# Read burner wallet address from cache file
# Waits up to 30 seconds for the file to appear, showing a spinner
get_burner_address() {
  local cache_file="${HP_NODE_DIR}/data/${CONTAINER_NAME}/flohive-cache.json"
  local attempts=0
  local max_attempts=15  # 15 * 2s = 30s
  local spin_chars='|/-\'

  while [ "$attempts" -lt "$max_attempts" ]; do
    if [ -f "$cache_file" ]; then
      local address
      address=$(grep -o '"address"[[:space:]]*:[[:space:]]*"[^"]*"' "$cache_file" | head -1 | cut -d'"' -f4)
      if [ -n "$address" ]; then
        # Clear spinner line
        echo -ne "\r\033[K" >&2
        echo "$address"
        return 0
      fi
    fi
    # Show spinner on stderr so it doesn't pollute the address output
    local spin_idx=$((attempts % 4))
    echo -ne "\r  ${DIM}${spin_chars:$spin_idx:1} Generating wallet...${NC}  " >&2
    sleep 2
    attempts=$((attempts + 1))
  done
  # Clear spinner line
  echo -ne "\r\033[K" >&2

  # Fallback 1: try docker logs
  local log_address
  log_address=$(docker logs "${CONTAINER_NAME}" 2>&1 | grep -o 'Address: 0x[0-9a-fA-F]*' | head -1 | cut -d' ' -f2)
  if [ -n "$log_address" ]; then
    echo "$log_address"
    return 0
  fi

  # Fallback 2: derive from ETH_PRIVATE_KEY if set
  if [ -n "$ETH_PRIVATE_KEY" ]; then
    local derived
    derived=$(derive_eth_address "$ETH_PRIVATE_KEY" 2>/dev/null || true)
    if [ -n "$derived" ]; then
      echo "$derived"
      return 0
    fi
  fi

  return 1
}

# Display wallet address prominently
display_wallet() {
  local address="$1"
  echo ""
  echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║                                                    ║${NC}"
  echo -e "${GREEN}${BOLD}║  Your Node's Burner Wallet Address:              ║${NC}"
  echo -e "${GREEN}${BOLD}║                                                    ║${NC}"
  echo -e "${GREEN}${BOLD}║  ${CYAN}${address}${GREEN}      ║${NC}"
  echo -e "${GREEN}${BOLD}║                                                    ║${NC}"
  echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${YELLOW}${BOLD}Almost there! Complete these 2 steps to activate your node:${NC}"
  echo ""
  echo -e "  ${BOLD}Step A — Bind your License to this node:${NC}"
  echo -e "     1. Open ${CYAN}https://node.hptestingsite.com/licenses${NC} in your browser"
  echo -e "     2. Connect with your ${BOLD}owner wallet${NC} (the one holding the License NFT)"
  echo -e "     3. Bind the license to this node address: ${CYAN}${address}${NC}"
  echo ""
  echo -e "  ${BOLD}Step B — Fund this node with gas:${NC}"
  echo -e "     Send a small amount of tokens to this node's address: ${CYAN}${address}${NC}"
  echo -e "     ${DIM}(Your node needs gas to submit transactions on-chain — like fuel for a car)${NC}"
  echo -e "     ${YELLOW}To ensure your node operates continuously for 1 year without interruption,${NC}"
  echo -e "     ${YELLOW}we recommend depositing at least 5 HP.${NC}"
  echo ""
  echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"
  echo -e "  ${DIM}The script will automatically detect when both steps are done.${NC}"
  echo ""
}

# Print instructions shown when user presses Ctrl+C or after polling completes
print_manage_instructions() {
  echo ""
  echo -e "${BOLD}Useful commands:${NC}"
  echo -e "  See what your node is doing:  ${CYAN}docker logs -f ${CONTAINER_NAME}${NC}"
  echo -e "  Stop your node:               ${CYAN}docker stop ${CONTAINER_NAME}${NC}"
  echo -e "  Start/restart your node:      ${CYAN}./start.sh${NC}"
  echo ""
}

# Polling loop: wait for gas + license binding (offer → accept → bound)
run_polling() {
  local burner_address="$1"

  local gas_ok="false"
  local delegation_ok="false"
  local offer_pending="false"

  # Count how many status lines we print per iteration (for cursor cleanup)
  local status_lines=2

  # Trap Ctrl+C during polling
  trap 'echo ""; echo ""; print_info "No worries — your node is still running in the background!"; print_info "Come back and re-run this script anytime to check your setup status."; print_manage_instructions; exit 0' INT

  echo -e "  ${CYAN}${BOLD}Checking your setup status...${NC}"
  echo -e "  ${DIM}(Press Ctrl+C to exit — your node keeps running either way)${NC}"
  echo ""

  while true; do
    status_lines=0

    # ── Check 1: Balance ──
    local balance_hex
    balance_hex=$(check_gas_funded "$burner_address") || true
    local display_bal
    display_bal=$(hex_to_display_balance "$balance_hex")

    if [ -n "$balance_hex" ] && [ "$balance_hex" != "0x0" ] && [ "$balance_hex" != "0x" ] && [ "$balance_hex" != "" ]; then
      gas_ok="true"
      echo -e "  ${GREEN}[✓] Balance: ${BOLD}${display_bal}${NC}"
    else
      echo -e "  ${DIM}[ ] Balance: 0 HP${NC}         — Send tokens to ${CYAN}${burner_address}${NC}"
    fi
    status_lines=$((status_lines + 1))

    # ── Check 2: License binding ──
    # Two-phase: owner sends an offer → node accepts → delegation is bound
    if [ "$delegation_ok" = "false" ]; then
      if check_delegation "$burner_address" "$OWNER_ADDRESS"; then
        delegation_ok="true"
        offer_pending="false"
        local owner_short="${OWNER_ADDRESS:0:6}...${OWNER_ADDRESS: -4}"
        echo -e "  ${GREEN}[✓] License bound${NC}        — Owner ${BOLD}${owner_short}${NC} confirmed"
      elif check_delegation_offer "$burner_address" "$OWNER_ADDRESS"; then
        offer_pending="true"
        echo -e "  ${YELLOW}[~] Offer received${NC}       — Waiting for your node to accept automatically..."
      else
        offer_pending="false"
        echo -e "  ${DIM}[ ] Waiting for license${NC}   — Bind at ${CYAN}https://node.hptestingsite.com/licenses${NC}"
      fi
    else
      echo -e "  ${GREEN}[✓] License bound${NC}"
    fi
    status_lines=$((status_lines + 1))

    # Both done?
    if [ "$gas_ok" = "true" ] && [ "$delegation_ok" = "true" ]; then
      echo ""
      echo -e "  ${GREEN}${BOLD}=========================================${NC}"
      echo -e "  ${GREEN}${BOLD}  All done! Your node is fully active!   ${NC}"
      echo -e "  ${GREEN}${BOLD}=========================================${NC}"
      echo ""
      echo -e "  Your node will now automatically process verification"
      echo -e "  tasks and earn rewards. No further action needed."
      print_manage_instructions
      trap - INT
      return
    fi

    echo ""
    status_lines=$((status_lines + 1))  # blank line

    echo -ne "  ${DIM}Next check in ${POLL_INTERVAL}s...${NC}"
    status_lines=$((status_lines + 1))  # countdown line

    # Sleep with countdown (interruptible by Ctrl+C)
    local remaining=$POLL_INTERVAL
    while [ "$remaining" -gt 0 ]; do
      sleep 1
      remaining=$((remaining - 1))
      echo -ne "\r  ${DIM}Next check in ${remaining}s...  ${NC}"
    done

    # Move cursor up to overwrite previous status lines
    echo -ne "\r\033[K"
    local lines_to_clear=$((status_lines - 1))
    while [ "$lines_to_clear" -gt 0 ]; do
      echo -ne "\033[1A\033[K"
      lines_to_clear=$((lines_to_clear - 1))
    done
  done
}

# Launch a container with current variables
launch_container() {
  # Check Docker
  if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed!"
    echo -e "  Your node runs inside Docker. Please install it first:"
    echo -e "  ${CYAN}https://docs.docker.com/get-docker/${NC}"
    echo ""
    echo -e "  After installing Docker, run this script again."
    exit 1
  fi
  if ! docker info &> /dev/null 2>&1; then
    print_error "Docker is installed but not running!"
    echo -e "  Please open the Docker Desktop app and wait for it to start,"
    echo -e "  then run this script again."
    exit 1
  fi

  local data_dir="${HP_NODE_DIR}/data/${CONTAINER_NAME}"
  mkdir -p "$data_dir"

  echo ""
  echo -e "${CYAN}${BOLD}Downloading the latest node software...${NC}"
  if ! docker pull "${IMAGE_NAME}"; then
    print_warn "Could not download the latest version. Using previously downloaded version."
  fi
  local latest_image_id
  latest_image_id=$(docker inspect --format '{{.Id}}' "${IMAGE_NAME}" 2>/dev/null || true)
  if [ -z "$latest_image_id" ]; then
    print_error "Could not download the node software."
    echo -e "  Please check your internet connection and try again."
    exit 1
  fi

  # Check if container already exists and is running with the same image & config
  local current_image_id=""
  local container_running="false"
  local config_changed="false"
  if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
    current_image_id=$(docker inspect --format '{{.Image}}' "${CONTAINER_NAME}" 2>/dev/null)
    if docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q "true"; then
      container_running="true"
    fi
    # Check if configuration has changed
    local running_env
    running_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null)
    local running_owner running_key running_log_level running_node_version
    running_owner=$(echo "$running_env" | grep "^OWNERS_ALLOWLIST=" | cut -d= -f2)
    running_key=$(echo "$running_env" | grep "^ETH_PRIVATE_KEY=" | cut -d= -f2)
    running_log_level=$(echo "$running_env" | grep "^LOG_LEVEL=" | cut -d= -f2)
    running_node_version=$(echo "$running_env" | grep "^NODE_VERSION=" | cut -d= -f2)
    if [ "$running_owner" != "$OWNER_ADDRESS" ] || [ "$running_key" != "$ETH_PRIVATE_KEY" ] || [ "$running_log_level" != "$LOG_LEVEL" ] || { [ -n "$ARG_NODE_VERSION" ] && [ "$running_node_version" != "$ARG_NODE_VERSION" ]; }; then
      config_changed="true"
    fi
  fi

  # Force restart if user chose "Generate new wallet" and a cache exists
  if [ "$FORCE_NEW_WALLET" = "true" ] && [ "$config_changed" = "false" ]; then
    local cache_file="${data_dir}/flohive-cache.json"
    if [ -f "$cache_file" ]; then
      config_changed="true"
    fi
  fi

  # Also check if the cached wallet differs from the desired private key
  # (easeflow reads cache first, ignoring env vars if cache exists)
  if [ -n "$ETH_PRIVATE_KEY" ] && [ "$config_changed" = "false" ]; then
    local cache_file="${data_dir}/flohive-cache.json"
    if [ -f "$cache_file" ]; then
      local cached_key
      cached_key=$(grep -o '"privateKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$cache_file" | head -1 | sed 's/.*"privateKey"[[:space:]]*:[[:space:]]*"//;s/"//')
      cached_key="${cached_key#0x}"
      if [ -n "$cached_key" ] && [ "$cached_key" != "$ETH_PRIVATE_KEY" ]; then
        config_changed="true"
      fi
    fi
  fi

  if [ "$container_running" = "true" ] && [ "$current_image_id" = "$latest_image_id" ] && [ "$config_changed" = "false" ]; then
    save_config
    echo ""
    echo -e "${GREEN}${BOLD}=========================================${NC}"
    echo -e "${GREEN}${BOLD}  Your node is already running!          ${NC}"
    echo -e "${GREEN}${BOLD}=========================================${NC}"
    echo ""
    echo -e "  Everything is up to date. Checking your setup status..."
    echo ""
    post_launch_flow "$data_dir"
    return
  fi

  if [ "$container_running" = "true" ] && [ "$config_changed" = "true" ]; then
    echo -e "${YELLOW}  Settings changed. Restarting your node with the new settings...${NC}"
  elif [ "$container_running" = "true" ]; then
    echo -e "${YELLOW}  A newer version is available. Updating your node...${NC}"
  else
    echo -e "${CYAN}  Starting your node...${NC}"
  fi
  echo ""

  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

  # Manage wallet cache:
  # 1. FORCE_NEW_WALLET → delete cache, let easeflow generate a new wallet
  # 2. ETH_PRIVATE_KEY set → write/update cache with key + derived address
  #    (easeflow reads cache first; when given only env var it doesn't write cache)
  # 3. No key → leave cache alone (easeflow will generate and cache a new wallet)
  local cache_file="${data_dir}/flohive-cache.json"
  if [ "$FORCE_NEW_WALLET" = "true" ]; then
    echo -e "  ${DIM}Clearing wallet cache (generating new wallet)...${NC}"
    rm -f "$cache_file"
  elif [ -n "$ETH_PRIVATE_KEY" ]; then
    # Check if cache already has the correct key
    local needs_write="false"
    if [ -f "$cache_file" ]; then
      local cached_key
      cached_key=$(grep -o '"privateKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$cache_file" | head -1 | sed 's/.*"privateKey"[[:space:]]*:[[:space:]]*"//;s/"//')
      cached_key="${cached_key#0x}"
      if [ "$cached_key" != "$ETH_PRIVATE_KEY" ]; then
        needs_write="true"
      fi
    else
      needs_write="true"
    fi
    if [ "$needs_write" = "true" ]; then
      local derived_addr
      derived_addr=$(write_wallet_cache "$data_dir" "$ETH_PRIVATE_KEY")
      if [ -n "$derived_addr" ]; then
        echo -e "  ${DIM}Wallet cache updated (${derived_addr})${NC}"
      else
        echo -e "  ${DIM}Wallet cache updated (address will be derived on startup)${NC}"
      fi
    fi
  fi

  local node_version_env=()
  if [ -n "$ARG_NODE_VERSION" ]; then
    node_version_env=(-e "NODE_VERSION=$ARG_NODE_VERSION")
  fi

  if ! docker run -d \
    -e OWNERS_ALLOWLIST="$OWNER_ADDRESS" \
    -e ETH_PRIVATE_KEY="$ETH_PRIVATE_KEY" \
    -e LOG_LEVEL="$LOG_LEVEL" \
    "${node_version_env[@]}" \
    -e HTTP_PROXY= \
    -e HTTPS_PROXY= \
    -e http_proxy= \
    -e https_proxy= \
    -v "${data_dir}:/app/cache" \
    --name "${CONTAINER_NAME}" \
    "${IMAGE_NAME}" >/dev/null; then
    echo ""
    print_error "Failed to start the node."
    echo -e "  Please check the error message above."
    echo -e "  Common fixes:"
    echo -e "    - Make sure Docker Desktop is running"
    echo -e "    - Try restarting Docker and running this script again"
    echo -e "    - If the problem persists, ask for help in the community"
    exit 1
  fi

  save_config

  echo ""
  echo -e "${GREEN}${BOLD}=========================================${NC}"
  echo -e "${GREEN}${BOLD}  Node started successfully!             ${NC}"
  echo -e "${GREEN}${BOLD}=========================================${NC}"
  echo ""
  echo -e "  Your node is now running. Let's get it fully set up."
  echo ""

  post_launch_flow "$data_dir"
}

# Post-launch: display wallet, poll for gas & delegation
post_launch_flow() {
  local data_dir="$1"

  echo -e "  ${CYAN}Reading your node's wallet address...${NC}"
  echo -e "  ${DIM}(This may take a few seconds on first start while the wallet is generated)${NC}"
  echo ""

  local burner_address
  burner_address=$(get_burner_address)

  if [ -z "$burner_address" ]; then
    print_warn "Could not read wallet address automatically."
    echo ""
    echo -e "  This sometimes happens on first start. You can find it manually:"
    echo -e "  Run: ${CYAN}docker logs ${CONTAINER_NAME} 2>&1 | head -20${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}After you find the wallet address, do these two things:${NC}"
    echo ""
    echo -e "  ${BOLD}1.${NC} Go to ${CYAN}https://node.hptestingsite.com/licenses${NC}"
    echo -e "     and bind your license to that node wallet address"
    echo ""
    echo -e "  ${BOLD}2.${NC} Send some gas (tokens) to that node wallet address"
    echo -e "     ${DIM}(Your node needs gas to submit transactions on-chain)${NC}"
    echo ""
    echo -e "  Then re-run this script — it will detect everything and confirm your setup."
    print_manage_instructions
    return
  fi

  display_wallet "$burner_address"
  run_polling "$burner_address"
}

# ─────────────────────────────────────────
# Detect pipe mode (curl | bash)
# ─────────────────────────────────────────
PIPE_MODE="false"
if [ ! -t 0 ]; then
  if [ -e /dev/tty ]; then
    # Running via curl | bash but terminal is available, allow interactive mode
    PIPE_MODE="false"
  else
    PIPE_MODE="true"
  fi
fi

# ─────────────────────────────────────────
# Non-interactive mode: if OWNER_ADDRESS is set via env or pipe mode
# ─────────────────────────────────────────
if [ -n "$OWNER_ADDRESS" ] && [ -z "$ARG_OWNER" ]; then
  # OWNER_ADDRESS set via env var directly
  if [[ ! "$OWNER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    print_error "Invalid OWNER_ADDRESS env var. Expected 0x followed by 40 hex characters."
    exit 1
  fi
  CONTAINER_NAME="${CONTAINER_NAME:-hp-verification-node-plugin}"
  HAS_CUSTOM_KEY="false"

  if [ -n "$ETH_PRIVATE_KEY" ]; then
    ETH_PRIVATE_KEY="${ETH_PRIVATE_KEY#0[xX]}"
    HAS_CUSTOM_KEY="true"
  fi

  launch_container
  exit 0
fi

# In pipe mode, require --owner-address
if [ "$PIPE_MODE" = "true" ]; then
  if [ -z "$ARG_OWNER" ]; then
    print_error "Missing required option: --owner-address"
    echo ""
    echo -e "  When running via curl, you need to specify your owner wallet address."
    echo ""
    echo -e "  ${BOLD}Copy and paste this, replacing the address with yours:${NC}"
    echo -e "  ${CYAN}curl -sSL <url> | bash -s -- --owner-address 0xYOUR_ADDRESS_HERE${NC}"
    echo ""
    exit 1
  fi

  # Set values from args
  OWNER_ADDRESS="$ARG_OWNER"
  if [[ ! "$OWNER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    print_error "Invalid address format. Expected 0x followed by 40 hex characters."
    exit 1
  fi

  CONTAINER_NAME="${ARG_NAME:-hp-verification-node-plugin}"
  HAS_CUSTOM_KEY="false"

  if [ -n "$ARG_KEY" ]; then
    ETH_PRIVATE_KEY="${ARG_KEY#0[xX]}"
    if [[ ! "$ETH_PRIVATE_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
      print_error "Invalid private key. Expected 64 hex characters."
      exit 1
    fi
    HAS_CUSTOM_KEY="true"
  fi

  print_banner
  launch_container
  exit 0
fi

# ─────────────────────────────────────────
# Restart mode: reuse saved config, skip wizard
# ─────────────────────────────────────────
if [ "$RESTART" = "true" ]; then
  print_banner

  target_name="${ARG_NAME:-}"

  if [ -n "$target_name" ]; then
    # Specific node requested
    if load_config "$target_name"; then
      echo -e "  Loaded config for: ${BOLD}${CONTAINER_NAME}${NC}"
    else
      print_error "No saved config found for '${target_name}'."
      echo -e "  Available configs are in: ${CYAN}${CONFIG_DIR}/${NC}"
      echo -e "  Run ${CYAN}./start.sh${NC} to set up a new node."
      exit 1
    fi
  elif [ -d "$CONFIG_DIR" ] && ls "$CONFIG_DIR"/*.conf &>/dev/null; then
    # No name specified — auto-pick
    local_configs=("$CONFIG_DIR"/*.conf)
    if [ "${#local_configs[@]}" -eq 1 ]; then
      # Only one config — use it
      local_name=$(basename "${local_configs[0]}" .conf)
      load_config "$local_name"
      echo -e "  Loaded config for: ${BOLD}${CONTAINER_NAME}${NC}"
    else
      # Multiple configs — list them and ask user to specify
      print_error "Multiple nodes found. Please specify which one to restart."
      echo ""
      for f in "$CONFIG_DIR"/*.conf; do
        local_name=$(basename "$f" .conf)
        echo -e "  - ${BOLD}${local_name}${NC}"
      done
      echo ""
      echo -e "  Usage: ${CYAN}./start.sh --restart --container-name <name>${NC}"
      exit 1
    fi
  else
    print_error "No saved configuration found."
    echo -e "  Run ${CYAN}./start.sh${NC} to set up a new node first."
    exit 1
  fi

  # CLI args override saved config values
  if [ -n "$ARG_OWNER" ]; then
    if [[ ! "$ARG_OWNER" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
      print_error "Invalid address format. Expected 0x followed by 40 hex characters."
      exit 1
    fi
    OWNER_ADDRESS="$ARG_OWNER"
  fi
  if [ -n "$ARG_KEY" ]; then
    ETH_PRIVATE_KEY="${ARG_KEY#0[xX]}"
    if [[ ! "$ETH_PRIVATE_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
      print_error "Invalid private key. Expected 64 hex characters."
      exit 1
    fi
    HAS_CUSTOM_KEY="true"
  fi
  # --verbose flag overrides saved LOG_LEVEL
  if [ "$VERBOSE" = "true" ]; then
    LOG_LEVEL="debug"
  fi

  launch_container
  exit 0
fi

# ─────────────────────────────────────────
# Interactive Setup Wizard
# ─────────────────────────────────────────

print_banner

# If CLI args provided, skip saved config selection and go straight to wizard
HAS_CLI_ARGS="false"
if [ -n "$ARG_OWNER" ] || [ -n "$ARG_KEY" ] || [ -n "$ARG_NAME" ]; then
  HAS_CLI_ARGS="true"
fi

IS_EXISTING_NODE="false"

# Check for saved configurations (skip if CLI args provided)
if [ "$HAS_CLI_ARGS" = "false" ] && list_configs; then
  echo -e "  Found previously configured nodes:"
  echo ""

  configs=()
  i=1
  for f in "$CONFIG_DIR"/*.conf; do
    name=$(basename "$f" .conf)
    cfg_owner=$(grep "^OWNER_ADDRESS=" "$f" | cut -d= -f2)
    echo -e "  ${BOLD}${i})${NC} ${name}  ${DIM}(${cfg_owner})${NC}"
    configs+=("$name")
    i=$((i + 1))
  done

  echo -e "  ${BOLD}${i})${NC} Set up a new node"
  echo ""

  while true; do
    read -p "  Select an option [1] (press Enter for 1): " SELECTION < /dev/tty
    SELECTION=$(echo "$SELECTION" | xargs)

    if [ -z "$SELECTION" ]; then
      SELECTION=1
    fi

    if [ "$SELECTION" = "$i" ]; then
      break
    fi

    if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -lt "$i" ]; then
      selected_name="${configs[$((SELECTION-1))]}"
      if load_config "$selected_name"; then
        DEFAULT_OWNER="$OWNER_ADDRESS"
        if [ "$HAS_CUSTOM_KEY" = "true" ]; then
          DEFAULT_KEY="$ETH_PRIVATE_KEY"
        else
          # Try to read cached wallet key from flohive-cache.json
          _cache_file="${HP_NODE_DIR}/data/${CONTAINER_NAME}/flohive-cache.json"
          if [ -f "$_cache_file" ]; then
            _cached_key=$(grep -o '"privateKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$_cache_file" | head -1 | sed 's/.*"privateKey"[[:space:]]*:[[:space:]]*"//;s/"//')
            _cached_key="${_cached_key#0x}"
            if [ -n "$_cached_key" ] && [[ "$_cached_key" =~ ^[0-9a-fA-F]{64}$ ]]; then
              DEFAULT_KEY="$_cached_key"
            fi
            unset _cached_key
          fi
          unset _cache_file
        fi
        DEFAULT_NAME="$CONTAINER_NAME"
        # Restore -v flag (load_config may overwrite LOG_LEVEL)
        if [ "$VERBOSE" = "true" ]; then
          LOG_LEVEL="debug"
        fi
        IS_EXISTING_NODE="true"
        print_success "Loaded config: ${selected_name}"
        break
      fi
    fi

    print_error "Invalid selection. Please enter a number between 1 and ${i}."
  done
elif [ "$HAS_CLI_ARGS" = "false" ]; then
  echo -e "  This wizard will guide you through setting up your"
  echo -e "  Humanity Protocol verification node step by step."
fi

echo ""
echo -e "${DIM}  Press Ctrl+C at any time to cancel.${NC}"

TOTAL_STEPS=5

# ── Step 1: Check Docker (non-navigable) ──

print_step 1 $TOTAL_STEPS "Checking Prerequisites"

if ! command -v docker &> /dev/null; then
  print_error "Docker is not installed."
  echo ""
  echo -e "  Your node runs inside Docker — it's a free tool that only takes a minute to install."
  echo -e "  Download it here: ${CYAN}https://docs.docker.com/get-docker/${NC}"
  echo ""
  echo -e "  After installing, run this script again."
  exit 1
fi

if ! docker info &> /dev/null 2>&1; then
  print_error "Docker is installed but not running."
  echo ""
  echo -e "  Please open the ${BOLD}Docker Desktop${NC} app and wait until it says \"running\","
  echo -e "  then run this script again."
  exit 1
fi

print_success "Docker is ready."

# Also check curl (needed for polling)
if ! command -v curl &> /dev/null; then
  print_warn "curl is not installed."
  print_info "Without curl, the script cannot auto-check your gas and delegation status."
  print_info "You can install it with: ${CYAN}sudo apt install curl${NC} (Linux) or ${CYAN}brew install curl${NC} (Mac)"
fi

# ── Helper: check if input is a "back" command ──
is_back() {
  local input
  input=$(echo "$1" | xargs | tr '[:upper:]' '[:lower:]')
  [ "$input" = "b" ] || [ "$input" = "back" ]
}

# ── Navigable Steps 2-5 ──────────────────

CURRENT_STEP=2

while [ $CURRENT_STEP -le 5 ]; do

  # ── Step 2: Node Name ────────────────────
  if [ $CURRENT_STEP -eq 2 ]; then
    print_step 2 $TOTAL_STEPS "Name Your Node" false

    # Existing node or CLI arg: name is locked
    if [ "$IS_EXISTING_NODE" = "true" ]; then
      CONTAINER_NAME="$DEFAULT_NAME"
      print_success "Node name: ${CONTAINER_NAME} ${DIM}(existing node)${NC}"
      CURRENT_STEP=3
      continue
    fi

    if [ -n "$ARG_NAME" ]; then
      CONTAINER_NAME="$ARG_NAME"
      print_success "Node name: ${CONTAINER_NAME}"
      CURRENT_STEP=3
      continue
    fi

    DEFAULT_CONTAINER="${CONTAINER_NAME:-hp-verification-node-plugin}"
    echo -e "  Give your node a name to identify it."
    echo -e "  ${DIM}(Only letters, numbers, hyphens, underscores, and dots are allowed)${NC}"
    echo ""

    STEP2_BACK="false"
    while true; do
      read -p "  Node name (press Enter for ${DEFAULT_CONTAINER}): " CUSTOM_NAME < /dev/tty

      if is_back "$CUSTOM_NAME"; then
        print_info "This is the first step."
        STEP2_BACK="true"
        break
      fi

      CUSTOM_NAME=$(echo "$CUSTOM_NAME" | xargs)

      if [ -z "$CUSTOM_NAME" ]; then
        CONTAINER_NAME="$DEFAULT_CONTAINER"
        break
      fi

      if [[ ! "$CUSTOM_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        print_error "Invalid name. Use only letters, numbers, hyphens, underscores, and dots."
        continue
      fi

      CONTAINER_NAME="$CUSTOM_NAME"
      break
    done

    if [ "$STEP2_BACK" = "true" ]; then
      continue
    fi

    print_success "Node name: ${CONTAINER_NAME}"
    CURRENT_STEP=3
    continue
  fi

  # ── Step 3: License Owner ─────────────────
  if [ $CURRENT_STEP -eq 3 ]; then
    STEP3_BACK="true"
    if [ "$IS_EXISTING_NODE" = "true" ] || [ -n "$ARG_NAME" ]; then
      STEP3_BACK="false"
    fi
    print_step 3 $TOTAL_STEPS "License Owner Address" "$STEP3_BACK"

    if [ -n "$ARG_OWNER" ]; then
      OWNER_ADDRESS="$ARG_OWNER"
      if [[ ! "$OWNER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        print_error "Invalid address format. Expected 0x followed by 40 hex characters."
        print_info "Example: 0x1234567890abcdef1234567890abcdef12345678"
        exit 1
      fi
      print_success "Owner Address: ${OWNER_ADDRESS}"
      CURRENT_STEP=4
      continue
    fi

    echo -e "  This is the wallet address where you own (or will own) the License NFT."
    echo -e "  ${DIM}It starts with 0x and is 42 characters long.${NC}"
    echo ""
    echo -e "  ${DIM}Don't have a License NFT yet? Purchase one at:${NC}"
    echo -e "  ${CYAN}https://sale.staging.humanity.org/${NC}"
    echo ""

    STEP3_DEFAULT="${OWNER_ADDRESS:-$DEFAULT_OWNER}"

    while true; do
      if [ -n "$STEP3_DEFAULT" ]; then
        read -p "  Owner Address (press Enter for ${STEP3_DEFAULT}): " INPUT_OWNER < /dev/tty
      else
        read -p "  Owner Address: " INPUT_OWNER < /dev/tty
      fi

      if is_back "$INPUT_OWNER"; then
        if [ "$IS_EXISTING_NODE" = "true" ] || [ -n "$ARG_NAME" ]; then
          print_info "This is the first editable step."
          continue
        fi
        CURRENT_STEP=2
        break
      fi

      INPUT_OWNER=$(echo "$INPUT_OWNER" | xargs)

      if [ -z "$INPUT_OWNER" ] && [ -n "$STEP3_DEFAULT" ]; then
        OWNER_ADDRESS="$STEP3_DEFAULT"
        break
      fi

      if [ -z "$INPUT_OWNER" ]; then
        print_error "Owner Address cannot be empty."
        continue
      fi

      if [[ ! "$INPUT_OWNER" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        print_error "Invalid format. It should start with 0x followed by 40 hex characters."
        print_info "Example: 0x1234567890abcdef1234567890abcdef12345678"
        continue
      fi

      OWNER_ADDRESS="$INPUT_OWNER"
      break
    done

    # If we broke out via "back", loop again
    if [ $CURRENT_STEP -eq 2 ]; then
      continue
    fi

    print_success "Owner Address: ${OWNER_ADDRESS}"
    CURRENT_STEP=4
    continue
  fi

  # ── Step 4: Node's Burner Wallet ──────────────────
  if [ $CURRENT_STEP -eq 4 ]; then
    print_step 4 $TOTAL_STEPS "Node's Burner Wallet"

    if [ -n "$ARG_KEY" ]; then
      ETH_PRIVATE_KEY="${ARG_KEY#0[xX]}"
      if [[ ! "$ETH_PRIVATE_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
        print_error "Invalid private key. Expected 64 hex characters (without 0x prefix)."
        exit 1
      fi
      HAS_CUSTOM_KEY="true"
      _derived=$(derive_eth_address "$ETH_PRIVATE_KEY" 2>/dev/null || true)
      if [ -n "$_derived" ]; then
        print_success "Private key accepted.  Address: ${_derived}"
      else
        print_success "Private key accepted.  (address will be derived on startup)"
      fi
      unset _derived
      CURRENT_STEP=5
      continue
    fi

    EXISTING_KEY="${ETH_PRIVATE_KEY:-$DEFAULT_KEY}"

    if [ -n "$EXISTING_KEY" ]; then
      MASKED_EXISTING="${EXISTING_KEY:0:6}...${EXISTING_KEY: -4}"
      echo -e "  Your node's wallet key: ${BOLD}${MASKED_EXISTING}${NC}"
      echo ""
      echo -e "  ${BOLD}1)${NC} Keep current wallet ${DIM}(default)${NC}"
      echo -e "  ${BOLD}2)${NC} Use a different wallet"
      echo -e "  ${BOLD}3)${NC} Generate a new wallet"
      echo ""

      while true; do
        read -p "  Select (press Enter for 1 = Keep current): " KEY_CHOICE < /dev/tty
        KEY_CHOICE_TRIMMED=$(echo "$KEY_CHOICE" | xargs)

        if is_back "$KEY_CHOICE_TRIMMED"; then
          CURRENT_STEP=3
          break
        fi

        if [ -z "$KEY_CHOICE_TRIMMED" ] || [ "$KEY_CHOICE_TRIMMED" = "1" ]; then
          ETH_PRIVATE_KEY="$EXISTING_KEY"
          HAS_CUSTOM_KEY="true"
          print_success "Keeping current wallet."
          break
        elif [ "$KEY_CHOICE_TRIMMED" = "2" ]; then
          echo ""
          echo -e "  Enter your wallet's private key (64 hex characters, without 0x)."
          echo -e "  ${DIM}(Input is hidden for security. Press Enter to go back.)${NC}"
          echo ""

          ENTERED_KEY=""
          while true; do
            read -s -p "  Private Key: " ENTERED_KEY < /dev/tty
            echo ""
            ENTERED_KEY=$(echo "$ENTERED_KEY" | xargs)
            ENTERED_KEY="${ENTERED_KEY#0[xX]}"

            if [ -z "$ENTERED_KEY" ]; then
              break
            fi

            if [[ ! "$ENTERED_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
              print_error "Invalid format. Expected 64 hex characters."
              continue
            fi

            break
          done

          if [ -z "$ENTERED_KEY" ]; then
            continue
          fi
          ETH_PRIVATE_KEY="$ENTERED_KEY"
          HAS_CUSTOM_KEY="true"
          _derived=$(derive_eth_address "$ETH_PRIVATE_KEY" 2>/dev/null || true)
          if [ -n "$_derived" ]; then
            print_success "Private key accepted.  Address: ${_derived}"
          else
            print_success "Private key accepted.  (address will be derived on startup)"
          fi
          unset _derived
          break
        elif [ "$KEY_CHOICE_TRIMMED" = "3" ]; then
          ETH_PRIVATE_KEY=""
          HAS_CUSTOM_KEY="false"
          FORCE_NEW_WALLET="true"
          print_info "A new wallet will be created when the node starts."
          print_warn "You will need to fund it with HP tokens for gas fees."
          break
        else
          print_error "Please enter 1, 2, or 3."
        fi
      done

      if [ $CURRENT_STEP -eq 3 ]; then
        continue
      fi
    else
      echo -e "  Your node needs its own wallet to operate on the network."
      echo -e "  Most users let the node create a new one automatically."
      echo ""
      echo -e "  ${BOLD}1)${NC} Generate a new wallet automatically ${DIM}(recommended for new users)${NC}"
      echo -e "  ${BOLD}2)${NC} Use my own wallet ${DIM}(I already have a funded wallet)${NC}"
      echo ""

      while true; do
        read -p "  Select (press Enter for 1 = Generate new): " WALLET_CHOICE < /dev/tty
        WALLET_CHOICE_TRIMMED=$(echo "$WALLET_CHOICE" | xargs)

        if is_back "$WALLET_CHOICE_TRIMMED"; then
          CURRENT_STEP=3
          break
        fi

        if [ -z "$WALLET_CHOICE_TRIMMED" ] || [ "$WALLET_CHOICE_TRIMMED" = "1" ]; then
          ETH_PRIVATE_KEY=""
          HAS_CUSTOM_KEY="false"
          print_info "A new wallet will be created when the node starts."
          print_warn "You will need to fund it with HP tokens for gas fees."
          break
        elif [ "$WALLET_CHOICE_TRIMMED" = "2" ]; then
          echo ""
          echo -e "  Enter your wallet's private key (64 hex characters, without 0x)."
          echo -e "  ${DIM}(Input is hidden for security. Press Enter to go back.)${NC}"
          echo ""

          ENTERED_KEY=""
          while true; do
            read -s -p "  Private Key: " ENTERED_KEY < /dev/tty
            echo ""
            ENTERED_KEY=$(echo "$ENTERED_KEY" | xargs)
            ENTERED_KEY="${ENTERED_KEY#0[xX]}"

            if [ -z "$ENTERED_KEY" ]; then
              break
            fi

            if [[ ! "$ENTERED_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
              print_error "Invalid format. Expected 64 hex characters."
              continue
            fi

            break
          done

          if [ -z "$ENTERED_KEY" ]; then
            continue
          fi
          ETH_PRIVATE_KEY="$ENTERED_KEY"
          HAS_CUSTOM_KEY="true"
          _derived=$(derive_eth_address "$ETH_PRIVATE_KEY" 2>/dev/null || true)
          if [ -n "$_derived" ]; then
            print_success "Private key accepted.  Address: ${_derived}"
          else
            print_success "Private key accepted.  (address will be derived on startup)"
          fi
          unset _derived
          break
        else
          print_error "Please enter 1 or 2."
        fi
      done

      if [ $CURRENT_STEP -eq 3 ]; then
        continue
      fi
    fi

    CURRENT_STEP=5
    continue
  fi

  # ── Step 5: Review & Launch ──────────────
  if [ $CURRENT_STEP -eq 5 ]; then
    print_step 5 $TOTAL_STEPS "Review & Launch"

    echo -e "  Please review your settings before starting:"
    echo ""
    echo -e "  ${BOLD}Node Name      :${NC} ${CONTAINER_NAME}"
    echo -e "  ${BOLD}License Owner  :${NC} ${OWNER_ADDRESS}"
    if [ "$HAS_CUSTOM_KEY" = "true" ]; then
      REVIEW_ADDR=$(derive_eth_address "$ETH_PRIVATE_KEY" 2>/dev/null || true)
      if [ -n "$REVIEW_ADDR" ]; then
        echo -e "  ${BOLD}Node's Burner Wallet    :${NC} ${REVIEW_ADDR}"
      else
        MASKED_KEY="${ETH_PRIVATE_KEY:0:6}...${ETH_PRIVATE_KEY: -4}"
        echo -e "  ${BOLD}Node's Burner Wallet    :${NC} ${MASKED_KEY} (key; address derived on startup)"
      fi
    else
      echo -e "  ${BOLD}Node's Burner Wallet    :${NC} (will be generated on first start)"
    fi
    echo -e "  ${BOLD}Log Level      :${NC} ${LOG_LEVEL}"
    echo ""
    echo -e "  ${BOLD}Data stored at :${NC} ${CYAN}${HP_NODE_DIR}/data/${CONTAINER_NAME}${NC}"
    echo -e "  ${BOLD}Config saved to:${NC} ${CYAN}${CONFIG_DIR}/${CONTAINER_NAME}.conf${NC}"
    echo ""

    while true; do
      read -p "  Start your node? (press Enter for Yes / n to cancel): " CONFIRM < /dev/tty
      CONFIRM_TRIMMED=$(echo "$CONFIRM" | xargs | tr '[:upper:]' '[:lower:]')

      if is_back "$CONFIRM_TRIMMED"; then
        CURRENT_STEP=4
        break
      fi

      if [ -z "$CONFIRM_TRIMMED" ] || [ "$CONFIRM_TRIMMED" = "y" ] || [ "$CONFIRM_TRIMMED" = "yes" ]; then
        CURRENT_STEP=6  # exit loop
        break
      elif [ "$CONFIRM_TRIMMED" = "n" ] || [ "$CONFIRM_TRIMMED" = "no" ]; then
        echo ""
        print_info "Setup cancelled. Run ./start.sh again when you're ready."
        exit 0
      else
        print_error "Please enter 'y', 'n', or 'b'."
      fi
    done

    continue
  fi

done

launch_container
