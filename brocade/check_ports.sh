#!/bin/bash
##############################################################################
# Brocade Switch Port & SFP Health Check Script
#
# Connects to a Brocade switch via SSH and performs:
# 1. Port status check (Online / Offline / No_Light / etc.)
# 2. SFP diagnostics (TX/RX power levels, temperature, current, voltage)
# 3. Expected-port validation (are all expected ports online?)
# 4. WWN login verification (are all aliases.txt WWNs logged in?)
#
# PREREQUISITES:
# - For Windows: use WSL, Git Bash, or Cygwin
#
# USAGE:
# chmod +x check_ports.sh
#
# # Auto-detect online ports from switchshow
# ./check_ports.sh --switch-ip 10.154.81.7
#
# # Specify expected ports (comma-separated index numbers)
# ./check_ports.sh --switch-ip 10.154.81.7 --ports 0,1,2,3,4,5,6,7,8,9,10,23
#
# # Specify expected ports from a file (one port index per line)
# ./check_ports.sh --switch-ip 10.154.81.7 --port-file expected_ports.txt
#
# # Also verify WWN logins against alias file
# ./check_ports.sh --switch-ip 10.154.81.7 --alias-file aliases.txt
#
# # Use a specific SSH private key
# ./check_ports.sh --switch-ip 10.154.81.7 --ssh-key ~/.ssh/id_ed25519
#
# # Use a dedicated known_hosts file
# ./check_ports.sh --switch-ip 10.154.81.7 --known-hosts-file ./known_hosts
#
# # Lab-only override: disable host key verification
# ./check_ports.sh --switch-ip 10.154.81.7 --insecure-hostkey
#
# # Dry run — print commands without executing
# ./check_ports.sh --switch-ip 10.154.81.7 --dry-run
##############################################################################

set -euo pipefail

# ========================= DEFAULTS ===================================
SWITCH_IP=""
SWITCH_USER="admin"
SSH_KEY=""
KNOWN_HOSTS_FILE=""
INSECURE_HOSTKEY=false
DRY_RUN=false
LOG_FILE="portcheck_$(date +%Y%m%d_%H%M%S).log"

# Port selection mode
EXPECTED_PORTS=""
PORT_FILE=""
ALIAS_FILE=""

# SFP power thresholds (dBm) — configurable
RX_WARN_DBM="-14.0"
RX_CRIT_DBM="-17.0"
TX_WARN_DBM="-8.0"
TX_CRIT_DBM="-12.0"

# Counters for summary
TOTAL_PORTS_CHECKED=0
PORTS_ONLINE=0
PORTS_OFFLINE=0
PORTS_NO_LIGHT=0
PORTS_OTHER=0
SFP_OK=0
SFP_WARN=0
SFP_CRIT=0
SFP_UNKNOWN=0
EXPECTED_MISSING=0
EXPECTED_TOTAL=0
WWN_FOUND=0
WWN_MISSING=0

# ========================= PARSE ARGUMENTS ============================
while [[ $# -gt 0 ]]; do
case "$1" in
--dry-run) DRY_RUN=true; shift ;;
--switch-ip) SWITCH_IP="$2"; shift 2 ;;
--switch-user) SWITCH_USER="$2"; shift 2 ;;
--ssh-key) SSH_KEY="$2"; shift 2 ;;
--known-hosts-file) KNOWN_HOSTS_FILE="$2"; shift 2 ;;
--insecure-hostkey) INSECURE_HOSTKEY=true; shift ;;
--ports) EXPECTED_PORTS="$2"; shift 2 ;;
--port-file) PORT_FILE="$2"; shift 2 ;;
--alias-file) ALIAS_FILE="$2"; shift 2 ;;
--rx-warn) RX_WARN_DBM="$2"; shift 2 ;;
--rx-crit) RX_CRIT_DBM="$2"; shift 2 ;;
--tx-warn) TX_WARN_DBM="$2"; shift 2 ;;
--tx-crit) TX_CRIT_DBM="$2"; shift 2 ;;
--log-file) LOG_FILE="$2"; shift 2 ;;
-h|--help)
echo "Usage: $0 [OPTIONS]"
echo ""
echo "Required:"
echo " --switch-ip IP Switch IP address"
echo ""
echo "Port Selection (choose one, or omit for auto-detect):"
echo " --ports PORTS Comma-separated port indices (e.g., 0,1,2,3,23)"
echo " --port-file FILE File with one port index per line"
echo " (none) Auto-detect from switchshow (all Online ports)"
echo ""
echo "Optional:"
echo " --dry-run Print commands without executing"
echo " --switch-user USER SSH username (default: admin)"
echo " --ssh-key FILE SSH private key file"
echo " --known-hosts-file FILE Use a dedicated known_hosts file"
echo " --insecure-hostkey Disable host key verification (lab use only)"
echo " --alias-file FILE Alias file for WWN login verification"
echo " --rx-warn DBM RX power warning threshold (default: ${RX_WARN_DBM})"
echo " --rx-crit DBM RX power critical threshold (default: ${RX_CRIT_DBM})"
echo " --tx-warn DBM TX power warning threshold (default: ${TX_WARN_DBM})"
echo " --tx-crit DBM TX power critical threshold (default: ${TX_CRIT_DBM})"
echo " --log-file FILE Log output file (default: auto-timestamped)"
echo " -h, --help Show this help"
exit 0
;;
*)
echo "Unknown option: $1 (use --help for usage)"
exit 1
;;
esac
done

# Validate required arguments
if [[ -z "$SWITCH_IP" ]]; then
echo "ERROR: --switch-ip is required. Use --help for usage."
exit 1
fi

# ========================= LOGGING ====================================
log() {
local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
echo "$msg" | tee -a "$LOG_FILE"
}

log_raw() {
echo "$1" | tee -a "$LOG_FILE"
}

# ========================= SSH HELPERS ================================
build_ssh_cmd() {
local -a ssh_cmd=(ssh
-o BatchMode=yes
-o ConnectTimeout=15
-o LogLevel=ERROR
)

if [[ "$INSECURE_HOSTKEY" == true ]]; then
ssh_cmd+=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
else
ssh_cmd+=(-o StrictHostKeyChecking=yes)
if [[ -n "$KNOWN_HOSTS_FILE" ]]; then
ssh_cmd+=(-o UserKnownHostsFile="$KNOWN_HOSTS_FILE")
fi
fi

if [[ -n "$SSH_KEY" ]]; then
ssh_cmd+=(-i "$SSH_KEY")
fi

ssh_cmd+=("${SWITCH_USER}@${SWITCH_IP}")
printf '%s\n' "${ssh_cmd[@]}"
}

run_cmd() {
local cmd="$1"
local description="${2:-}"

if [[ -n "$description" ]]; then
log "# $description"
fi
log ">>> $cmd"

if [[ "$DRY_RUN" == false ]]; then
local output
mapfile -t ssh_cmd < <(build_ssh_cmd)
output=$("${ssh_cmd[@]}" "$cmd" 2>&1) || {
log "!!! COMMAND FAILED: $cmd"
log "!!! Output: $output"
return 1
}
echo "$output"
return 0
else
echo "(dry-run: no output)"
return 0
fi
}

# ========================= UTILITY: TRIM ==============================
trim() {
local var="$1"
var="${var#"${var%%[![:space:]]*}"}"
var="${var%"${var##*[![:space:]]}"}"
echo "$var"
}

# ========================= FLOAT COMPARISON ===========================
# Bash doesn't do float math natively; use awk
float_lt() {
# Returns 0 (true) if $1 < $2
awk "BEGIN { exit !($1 < $2) }"
}

float_gte() {
# Returns 0 (true) if $1 >= $2
awk "BEGIN { exit !($1 >= $2) }"
}

# ========================= PRE-FLIGHT =================================
echo "============================================================"
if [[ "$DRY_RUN" == true ]]; then
echo " *** DRY RUN MODE — No commands will be sent ***"
else
echo " *** LIVE MODE — Commands will be sent to the switch ***"
fi
echo "============================================================"
echo " Switch : ${SWITCH_IP} (user: ${SWITCH_USER})"
echo " SSH Key : ${SSH_KEY:-default ssh agent / keychain}"
if [[ "$INSECURE_HOSTKEY" == true ]]; then
echo " Host Trust : INSECURE (host key verification disabled)"
elif [[ -n "$KNOWN_HOSTS_FILE" ]]; then
echo " Host Trust : strict verification using ${KNOWN_HOSTS_FILE}"
else
echo " Host Trust : strict verification using default known_hosts"
fi
echo " Log File : ${LOG_FILE}"
echo " RX Thresholds: WARN < ${RX_WARN_DBM} dBm, CRIT < ${RX_CRIT_DBM} dBm"
echo " TX Thresholds: WARN < ${TX_WARN_DBM} dBm, CRIT < ${TX_CRIT_DBM} dBm"
if [[ -n "$EXPECTED_PORTS" ]]; then
echo " Port Source : Command line (--ports ${EXPECTED_PORTS})"
elif [[ -n "$PORT_FILE" ]]; then
echo " Port Source : File (${PORT_FILE})"
else
echo " Port Source : Auto-detect from switchshow"
fi
if [[ -n "$ALIAS_FILE" ]]; then
echo " Alias File : ${ALIAS_FILE} (WWN verification enabled)"
fi
echo "============================================================"
echo ""

if ! command -v ssh >/dev/null 2>&1; then
echo "ERROR: ssh is not installed or not in PATH."
exit 1
fi

if [[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]]; then
echo "ERROR: SSH key file not found: ${SSH_KEY}"
exit 1
fi

if [[ -n "$KNOWN_HOSTS_FILE" && ! -f "$KNOWN_HOSTS_FILE" ]]; then
echo "ERROR: Known hosts file not found: ${KNOWN_HOSTS_FILE}"
exit 1
fi

# Verify optional input files exist
if [[ -n "$PORT_FILE" && ! -f "$PORT_FILE" ]]; then
echo "ERROR: Port file not found: ${PORT_FILE}"
exit 1
fi
if [[ -n "$ALIAS_FILE" && ! -f "$ALIAS_FILE" ]]; then
echo "ERROR: Alias file not found: ${ALIAS_FILE}"
exit 1
fi

log "========== Port & SFP Health Check Started =========="

# ======================================================================
# STEP 1: COLLECT switchshow OUTPUT
# ======================================================================
log "============ STEP 1: COLLECT switchshow ============"

SWITCHSHOW_OUTPUT=""

if [[ "$DRY_RUN" == false ]]; then
SWITCHSHOW_OUTPUT=$(run_cmd "switchshow" "Collect port status from switchshow")
if [[ -z "$SWITCHSHOW_OUTPUT" ]]; then
log "!!! ERROR: Empty switchshow output. Check connectivity."
exit 1
fi
echo "$SWITCHSHOW_OUTPUT" >> "$LOG_FILE"
log ""
else
log " (dry-run: switchshow would be collected here)"
log ""
fi

# ======================================================================
# STEP 2: DETERMINE PORT LIST
# ======================================================================
log "============ STEP 2: DETERMINE PORT LIST ============"

declare -A EXPECTED_PORT_MAP # Ports that SHOULD be online
declare -A ONLINE_PORT_MAP # Ports that ARE online (from switchshow)
declare -A PORT_WWN_MAP # Port index -> WWN (from switchshow)

# --- Parse switchshow to find currently online ports and their WWNs ---
if [[ "$DRY_RUN" == false && -n "$SWITCHSHOW_OUTPUT" ]]; then
while IFS= read -r line; do
# Match switchshow port lines like:
# 0 0 010000 id N8 Online FC F-Port 10:00:00:10:9b:33:b3:a7
if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+[0-9a-f]+[[:space:]]+(--|id|cu)[[:space:]]+(N?[0-9GKMN]*)[[:space:]]+([A-Za-z_]+) ]]; then
local_index="${BASH_REMATCH[1]}"
local_port="${BASH_REMATCH[2]}"
local_state="${BASH_REMATCH[5]}"

if [[ "$local_state" == "Online" ]]; then
ONLINE_PORT_MAP["${local_index}"]=1

# Extract WWN if present (F-Port line)
if [[ "$line" =~ ([0-9a-f]{2}(:[0-9a-f]{2}){7})[[:space:]]*$ ]]; then
PORT_WWN_MAP["${local_index}"]="${BASH_REMATCH[1]}"
fi
fi
fi
done <<< "$SWITCHSHOW_OUTPUT"

log " Online ports detected: ${!ONLINE_PORT_MAP[*]}"
log " Total online: ${#ONLINE_PORT_MAP[@]}"
fi

# --- Build expected port list based on source ---
if [[ -n "$EXPECTED_PORTS" ]]; then
# Source: command-line --ports argument
IFS=',' read -ra PORT_ARRAY <<< "$EXPECTED_PORTS"
for p in "${PORT_ARRAY[@]}"; do
p=$(trim "$p")
[[ -z "$p" ]] && continue
EXPECTED_PORT_MAP["$p"]=1
done
log " Expected ports (from --ports): ${!EXPECTED_PORT_MAP[*]}"

elif [[ -n "$PORT_FILE" ]]; then
# Source: port file
while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue
EXPECTED_PORT_MAP["$line"]=1
done < "$PORT_FILE"
log " Expected ports (from ${PORT_FILE}): ${!EXPECTED_PORT_MAP[*]}"

else
# Source: auto-detect from switchshow (all online ports)
for port_idx in "${!ONLINE_PORT_MAP[@]}"; do
EXPECTED_PORT_MAP["$port_idx"]=1
done
log " Expected ports (auto-detected from switchshow): ${!EXPECTED_PORT_MAP[*]}"
fi

EXPECTED_TOTAL=${#EXPECTED_PORT_MAP[@]}
log " Total expected ports: ${EXPECTED_TOTAL}"
log ""

# ======================================================================
# STEP 3: VALIDATE EXPECTED PORTS ARE ONLINE
# ======================================================================
log "============ STEP 3: VALIDATE EXPECTED PORTS ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log_raw " +-------+----------+-------------------+"
log_raw " | Port | Status | WWN |"
log_raw " +-------+----------+-------------------+"

# Sort port indices numerically
SORTED_EXPECTED=($(echo "${!EXPECTED_PORT_MAP[@]}" | tr ' ' '\n' | sort -n))

for port_idx in "${SORTED_EXPECTED[@]}"; do
port_display=$(printf "%-5s" "$port_idx")

if [[ -n "${ONLINE_PORT_MAP[$port_idx]+_}" ]]; then
wwn="${PORT_WWN_MAP[$port_idx]:-N/A}"
log_raw " | ${port_display} | ONLINE | ${wwn} |"
PORTS_ONLINE=$((PORTS_ONLINE + 1))
else
# Port is expected but NOT online — determine actual state
actual_state="NOT ONLINE"

# Try to find the actual state from switchshow
if [[ -n "$SWITCHSHOW_OUTPUT" ]]; then
state_line=$(echo "$SWITCHSHOW_OUTPUT" | grep -E "^[[:space:]]*${port_idx}[[:space:]]+" | head -1)
if [[ -n "$state_line" ]]; then
if [[ "$state_line" =~ No_Light ]]; then
actual_state="NO LIGHT"
PORTS_NO_LIGHT=$((PORTS_NO_LIGHT + 1))
elif [[ "$state_line" =~ No_Module ]]; then
actual_state="NO SFP"
PORTS_OTHER=$((PORTS_OTHER + 1))
elif [[ "$state_line" =~ Disabled ]]; then
actual_state="DISABLED"
PORTS_OTHER=$((PORTS_OTHER + 1))
elif [[ "$state_line" =~ Offline ]]; then
actual_state="OFFLINE"
PORTS_OFFLINE=$((PORTS_OFFLINE + 1))
elif [[ "$state_line" =~ In_Sync ]]; then
actual_state="IN SYNC"
PORTS_OTHER=$((PORTS_OTHER + 1))
elif [[ "$state_line" =~ Faulty ]]; then
actual_state="FAULTY"
PORTS_OTHER=$((PORTS_OTHER + 1))
else
PORTS_OTHER=$((PORTS_OTHER + 1))
fi
else
actual_state="NOT FOUND"
PORTS_OTHER=$((PORTS_OTHER + 1))
fi
fi

log_raw " | ${port_display} | *** ${actual_state} *** | --- EXPECTED ONLINE |"
EXPECTED_MISSING=$((EXPECTED_MISSING + 1))
fi

TOTAL_PORTS_CHECKED=$((TOTAL_PORTS_CHECKED + 1))
done

log_raw " +-------+----------+-------------------+"
log ""

if [[ $EXPECTED_MISSING -gt 0 ]]; then
log " !!! WARNING: ${EXPECTED_MISSING} of ${EXPECTED_TOTAL} expected ports are NOT online"
else
log " OK: All ${EXPECTED_TOTAL} expected ports are online"
fi
else
log " (dry-run: would validate ${EXPECTED_TOTAL} expected ports against switchshow)"
fi
log ""

# ======================================================================
# STEP 4: SFP DIAGNOSTICS
# ======================================================================
log "============ STEP 4: SFP DIAGNOSTICS (sfpshow) ============"

if [[ "$DRY_RUN" == false ]]; then
# Only run sfpshow on ports that are online (have an SFP with light)
SFPSHOW_PORTS=()
for port_idx in "${SORTED_EXPECTED[@]}"; do
if [[ -n "${ONLINE_PORT_MAP[$port_idx]+_}" ]]; then
SFPSHOW_PORTS+=("$port_idx")
fi
done

if [[ ${#SFPSHOW_PORTS[@]} -eq 0 ]]; then
log " No online ports to check SFP diagnostics on."
else
log ""
log_raw " +-------+-------------+-------------+--------+------------------+"
log_raw " | Port | RX Pwr(dBm) | TX Pwr(dBm) | Status | Detail |"
log_raw " +-------+-------------+-------------+--------+------------------+"

for port_idx in "${SFPSHOW_PORTS[@]}"; do
# Run sfpshow for this specific port
sfp_output=$(run_cmd "sfpshow ${port_idx}" "SFP diagnostics for port ${port_idx}" 2>/dev/null) || {
log " !!! Failed to get sfpshow for port ${port_idx}"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
continue
}

# Parse RX Power (dBm)
rx_dbm=""
if echo "$sfp_output" | grep -qi "RX Power"; then
rx_line=$(echo "$sfp_output" | grep -i "RX Power" | head -1)
# Match patterns like: "RX Power: -3.5 dBm" or "RX Power: -3.5 dBm 446.7 uW"
if [[ "$rx_line" =~ (-?[0-9]+\.?[0-9]*)[[:space:]]*dBm ]]; then
rx_dbm="${BASH_REMATCH[1]}"
fi
fi

# Parse TX Power (dBm)
tx_dbm=""
if echo "$sfp_output" | grep -qi "TX Power"; then
tx_line=$(echo "$sfp_output" | grep -i "TX Power" | head -1)
if [[ "$tx_line" =~ (-?[0-9]+\.?[0-9]*)[[:space:]]*dBm ]]; then
tx_dbm="${BASH_REMATCH[1]}"
fi
fi

# Determine status
port_display=$(printf "%-5s" "$port_idx")
rx_display=$(printf "%-11s" "${rx_dbm:-N/A}")
tx_display=$(printf "%-11s" "${tx_dbm:-N/A}")
status="OK"
detail=""

if [[ -z "$rx_dbm" || -z "$tx_dbm" ]]; then
status="UNKNOWN"
detail="Could not parse power"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
else
# Check RX power
if float_lt "$rx_dbm" "$RX_CRIT_DBM" 2>/dev/null; then
status="CRIT"
detail="RX below ${RX_CRIT_DBM}"
elif float_lt "$rx_dbm" "$RX_WARN_DBM" 2>/dev/null; then
if [[ "$status" != "CRIT" ]]; then
status="WARN"
detail="RX below ${RX_WARN_DBM}"
fi
fi

# Check TX power
if float_lt "$tx_dbm" "$TX_CRIT_DBM" 2>/dev/null; then
status="CRIT"
detail="${detail:+${detail}; }TX below ${TX_CRIT_DBM}"
elif float_lt "$tx_dbm" "$TX_WARN_DBM" 2>/dev/null; then
if [[ "$status" == "OK" ]]; then
status="WARN"
fi
detail="${detail:+${detail}; }TX below ${TX_WARN_DBM}"
fi

# Update counters
case "$status" in
OK) SFP_OK=$((SFP_OK + 1)) ;;
WARN) SFP_WARN=$((SFP_WARN + 1)) ;;
CRIT) SFP_CRIT=$((SFP_CRIT + 1)) ;;
esac
fi

if [[ -z "$detail" ]]; then
detail="Clean"
fi

status_display=$(printf "%-6s" "$status")
detail_display=$(printf "%-16s" "$detail")

log_raw " | ${port_display} | ${rx_display} | ${tx_display} | ${status_display} | ${detail_display} |"

# Also log the full sfpshow output for audit trail
echo "--- sfpshow ${port_idx} ---" >> "$LOG_FILE"
echo "$sfp_output" >> "$LOG_FILE"
echo "--- end sfpshow ${port_idx} ---" >> "$LOG_FILE"

sleep 1 # Delay between sfpshow calls for switch stability
done

log_raw " +-------+-------------+-------------+--------+------------------+"
log ""

if [[ $SFP_CRIT -gt 0 ]]; then
log " !!! CRITICAL: ${SFP_CRIT} port(s) with critical SFP power levels — check cables!"
fi
if [[ $SFP_WARN -gt 0 ]]; then
log " !!! WARNING: ${SFP_WARN} port(s) with marginal SFP power levels"
fi
if [[ $SFP_OK -gt 0 ]]; then
log " OK: ${SFP_OK} port(s) with clean SFP power levels"
fi
fi
else
log " (dry-run: would run sfpshow on each online expected port)"
fi
log ""

# ======================================================================
# STEP 5: porterrshow — ERROR COUNTERS
# ======================================================================
log "============ STEP 5: PORT ERROR COUNTERS (porterrshow) ============"

if [[ "$DRY_RUN" == false ]]; then
PORTERR_OUTPUT=$(run_cmd "porterrshow" "Collect port error counters")
if [[ -n "$PORTERR_OUTPUT" ]]; then
echo "$PORTERR_OUTPUT" >> "$LOG_FILE"

# Check for any non-zero error counts on expected ports
# porterrshow format has columns: frames tx/rx, enc_in, crc_err, crc_g_eof,
# too_shrt, too_long, bad_eof, enc_out, disc_c3, link_fail, loss_sync, loss_sig, etc.
PORTS_WITH_ERRORS=0

for port_idx in "${SORTED_EXPECTED[@]}"; do
if [[ -n "${ONLINE_PORT_MAP[$port_idx]+_}" ]]; then
# Find the line for this port in porterrshow
err_line=$(echo "$PORTERR_OUTPUT" | grep -E "^[[:space:]]*${port_idx}:" | head -1)
if [[ -n "$err_line" ]]; then
# Check if any error counter (columns after the port number) is non-zero
# Remove the port label, then check remaining values
err_values=$(echo "$err_line" | sed 's/^[[:space:]]*[0-9]*://')
has_errors=false
for val in $err_values; do
if [[ "$val" =~ ^[0-9]+$ && "$val" -gt 0 ]]; then
has_errors=true
break
fi
done
if [[ "$has_errors" == true ]]; then
log " !!! Port ${port_idx}: Non-zero error counters detected"
log " ${err_line}"
PORTS_WITH_ERRORS=$((PORTS_WITH_ERRORS + 1))
fi
fi
fi
done

if [[ $PORTS_WITH_ERRORS -eq 0 ]]; then
log " OK: No error counters on expected online ports"
else
log " !!! WARNING: ${PORTS_WITH_ERRORS} port(s) have non-zero error counters"
fi
fi
else
log " (dry-run: would run porterrshow)"
fi
log ""

# ======================================================================
# STEP 6: WWN LOGIN VERIFICATION (optional, if --alias-file provided)
# ======================================================================
# ======================================================================
# STEP 6: WWN LOGIN VERIFICATION via nodefind (optional, if --alias-file provided)
# ======================================================================
if [[ -n "$ALIAS_FILE" ]]; then
log "============ STEP 6: WWN LOGIN VERIFICATION via nodefind (from ${ALIAS_FILE}) ============"

# Parse aliases.txt to extract all alias->WWN mappings
declare -A ALIAS_WWNS # alias_name -> wwn
CURRENT_ALIAS=""

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue

if [[ "$line" =~ ^alias:[[:space:]]*(.+)$ ]]; then
CURRENT_ALIAS=$(trim "${BASH_REMATCH[1]}")
elif [[ "$line" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){7}$ ]]; then
if [[ -n "$CURRENT_ALIAS" ]]; then
ALIAS_WWNS["${CURRENT_ALIAS}"]="$line"
CURRENT_ALIAS=""
fi
fi
done < "$ALIAS_FILE"

TOTAL_ALIASES=${#ALIAS_WWNS[@]}
log " Aliases loaded from ${ALIAS_FILE}: ${TOTAL_ALIASES}"

if [[ "$DRY_RUN" == false ]]; then
log ""
log_raw " +----------------------------------+-------------------------+----------+-------+--------------------------------+"
log_raw " | Alias | WWN | Logged In| Port | Detail |"
log_raw " +----------------------------------+-------------------------+----------+-------+--------------------------------+"

# Sort alias names for consistent output
SORTED_ALIASES=($(echo "${!ALIAS_WWNS[@]}" | tr ' ' '\n' | sort))

for alias_name in "${SORTED_ALIASES[@]}"; do
wwn="${ALIAS_WWNS[$alias_name]}"
alias_display=$(printf "%-32s" "$alias_name")
wwn_display=$(printf "%-23s" "$wwn")

# Run nodefind for this specific WWN
nodefind_output=$(run_cmd "nodefind ${wwn}" "nodefind for alias ${alias_name} (${wwn})" 2>/dev/null) || {
log " !!! Failed to run nodefind for ${alias_name} (${wwn})"
log_raw " | ${alias_display} | ${wwn_display} | ERROR | --- | nodefind command failed |"
WWN_MISSING=$((WWN_MISSING + 1))
continue
}

# Log the full nodefind output for audit trail
echo "--- nodefind ${wwn} (${alias_name}) ---" >> "$LOG_FILE"
echo "$nodefind_output" >> "$LOG_FILE"
echo "--- end nodefind ---" >> "$LOG_FILE"

# Check if the device was found
# nodefind returns lines with "Port Index:" and PID info if found,
# or "No device found" / empty relevant output if not found
if echo "$nodefind_output" | grep -qi "No device found"; then
# Device is NOT logged in
detail_display=$(printf "%-30s" "Not logged in to fabric")
log_raw " | ${alias_display} | ${wwn_display} | *** NO ***| --- | ${detail_display} |"
WWN_MISSING=$((WWN_MISSING + 1))

elif echo "$nodefind_output" | grep -qi "Port Index"; then
# Device IS logged in — extract port index
port_found="?"
port_line=$(echo "$nodefind_output" | grep -i "Port Index" | head -1)
if [[ "$port_line" =~ Port[[:space:]]+Index:[[:space:]]*([0-9]+) ]]; then
port_found="${BASH_REMATCH[1]}"
fi

# Extract device type info if available (NodeSymb line)
device_info=""
nodesymb_line=$(echo "$nodefind_output" | grep -i "NodeSymb" | head -1)
if [[ -n "$nodesymb_line" ]]; then
# Extract hostname from NodeSymb, e.g.:
# NodeSymb: [85] "Emulex ... HN:ctlnp1-pdbsa.eu-citi.zl. OS:Linux"
if [[ "$nodesymb_line" =~ HN:([^[:space:]\.]+) ]]; then
device_info="HN:${BASH_REMATCH[1]}"
elif [[ "$nodesymb_line" =~ \"([^\"]+)\" ]]; then
# Fallback: first 28 chars of the symbol string
device_info="${BASH_REMATCH[1]:0:28}"
fi
fi

# Check link speed
speed_info=""
speed_line=$(echo "$nodefind_output" | grep -i "Device link speed" | head -1)
if [[ "$speed_line" =~ Device[[:space:]]+link[[:space:]]+speed:[[:space:]]*([0-9]+G) ]]; then
speed_info="${BASH_REMATCH[1]}"
fi

# Build detail string
detail="${device_info}"
if [[ -n "$speed_info" ]]; then
detail="${detail:+${detail} }${speed_info}"
fi
if [[ -z "$detail" ]]; then
detail="Found"
fi

port_display=$(printf "%-5s" "$port_found")
detail_display=$(printf "%-30s" "$detail")
log_raw " | ${alias_display} | ${wwn_display} | YES | ${port_display} | ${detail_display} |"
WWN_FOUND=$((WWN_FOUND + 1))

elif echo "$nodefind_output" | grep -q "$wwn"; then
# WWN appears in output but format is unexpected — likely found
# This handles variations in nodefind output across FOS versions

# Try to extract port from "Remote switch" or "Local" line
port_found="?"
if [[ "$nodefind_output" =~ Port:[[:space:]]*([0-9]+) ]]; then
port_found="${BASH_REMATCH[1]}"
fi

port_display=$(printf "%-5s" "$port_found")
detail_display=$(printf "%-30s" "Found (non-standard output)")
log_raw " | ${alias_display} | ${wwn_display} | YES | ${port_display} | ${detail_display} |"
WWN_FOUND=$((WWN_FOUND + 1))

else
# Neither "No device found" nor recognizable output — treat as missing
detail_display=$(printf "%-30s" "Unrecognized nodefind output")
log_raw " | ${alias_display} | ${wwn_display} | *** NO ***| --- | ${detail_display} |"
WWN_MISSING=$((WWN_MISSING + 1))
fi

sleep 1 # Delay between nodefind calls for switch stability
done

log_raw " +----------------------------------+-------------------------+----------+-------+--------------------------------+"
log ""

if [[ $WWN_MISSING -gt 0 ]]; then
log " !!! WARNING: ${WWN_MISSING} of ${TOTAL_ALIASES} alias WWNs are NOT logged into the fabric"
log " Possible causes:"
log " - Device is powered off"
log " - Cable not connected or connected to a different switch"
log " - HBA driver not loaded"
log " - Wrong WWN in alias file"
else
log " OK: All ${TOTAL_ALIASES} alias WWNs are logged into the fabric"
fi
else
log " (dry-run: would run nodefind for each of ${TOTAL_ALIASES} WWNs)"
log ""
log " Commands that would be executed:"
SORTED_ALIASES=($(echo "${!ALIAS_WWNS[@]}" | tr ' ' '\n' | sort))
for alias_name in "${SORTED_ALIASES[@]}"; do
wwn="${ALIAS_WWNS[$alias_name]}"
log " nodefind ${wwn} # ${alias_name}"
done
fi
log ""
fi

# ======================================================================
# SUMMARY
# ======================================================================
log "============ SUMMARY ============"
log ""
log " Switch: ${SWITCH_IP}"
log ""
log " --- Port Status ---"
log " Expected ports: ${EXPECTED_TOTAL}"
log " Online: ${PORTS_ONLINE}"
log " Missing (expected): ${EXPECTED_MISSING}"
if [[ $PORTS_NO_LIGHT -gt 0 ]]; then
log " No Light: ${PORTS_NO_LIGHT}"
fi
if [[ $PORTS_OFFLINE -gt 0 ]]; then
log " Offline: ${PORTS_OFFLINE}"
fi
if [[ $PORTS_OTHER -gt 0 ]]; then
log " Other: ${PORTS_OTHER}"
fi
log ""
log " --- SFP Health ---"
log " OK: ${SFP_OK}"
log " Warning: ${SFP_WARN}"
log " Critical: ${SFP_CRIT}"
log " Unknown: ${SFP_UNKNOWN}"
log ""

if [[ -n "$ALIAS_FILE" ]]; then
log " --- WWN Verification ---"
log " Total aliases: ${TOTAL_ALIASES:-0}"
log " Logged in: ${WWN_FOUND}"
log " Missing: ${WWN_MISSING}"
log ""
fi

# Overall result
OVERALL="PASS"
if [[ $EXPECTED_MISSING -gt 0 || $SFP_CRIT -gt 0 || $WWN_MISSING -gt 0 ]]; then
OVERALL="FAIL"
elif [[ $SFP_WARN -gt 0 ]]; then
OVERALL="WARN"
fi

log " ============================================"
log " OVERALL RESULT: *** ${OVERALL} ***"
log " ============================================"
log ""
log " Log file: ${LOG_FILE}"
log ""
log "========== Port & SFP Health Check Complete =========="