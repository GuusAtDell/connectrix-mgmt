#!/bin/bash
##############################################################################
# Cisco MDS Switch Port & SFP Health Check Script (SSH key only)
#
# Cisco NX-OS equivalent of check_ports.sh (Brocade). Connects to a
# Cisco MDS switch via SSH and performs:
# 1. Port status check (up / down / sfpAbsent / etc.)
# 2. SFP diagnostics (TX/RX power levels from transceiver details)
# 3. Expected-port validation (are all expected ports online?)
# 4. Port error counter check
# 5. WWN login verification via flogi database (optional)
#
# AUTHENTICATION:
# - SSH key only. Password authentication is intentionally disabled.
# - Supports an optional identity file via --ssh-key.
#
# USAGE:
# chmod +x check_ports.sh
#
# # Auto-detect up ports from show interface brief
# ./check_ports.sh --switch-ip 10.154.81.7
#
# # Specify SSH key explicitly
# ./check_ports.sh --switch-ip 10.154.81.7 --ssh-key ~/.ssh/id_ed25519
#
# # Use a dedicated known_hosts file
# ./check_ports.sh --switch-ip 10.154.81.7 --known-hosts-file ./known_hosts
#
# # Lab-only override: disable host key verification
# ./check_ports.sh --switch-ip 10.154.81.7 --insecure-hostkey
#
# # Specify expected ports (comma-separated, Cisco format)
# ./check_ports.sh --switch-ip 10.154.81.7 \
# --ports fc1/1,fc1/2,fc1/3,fc1/4
#
# # Specify expected ports from a file (one interface per line)
# ./check_ports.sh --switch-ip 10.154.81.7 \
# --port-file expected_ports.txt
#
# # Also verify WWN logins against alias file
# ./check_ports.sh --switch-ip 10.154.81.7 \
# --alias-file aliases.txt --vsan 100
#
# # Dry run
# ./check_ports.sh --switch-ip 10.154.81.7 --dry-run
#
# PORT FILE FORMAT (expected_ports.txt):
# One Cisco interface name per line. Comments (#) and blank lines ignored.
# fc1/1
# fc1/2
# # Storage ports
# fc1/23
# fc1/24
#
# SFP POWER THRESHOLDS:
# Defaults based on typical SWL 8G/16G/32G SFP specs:
# RX Power: WARN < -14.0 dBm, CRIT < -17.0 dBm
# TX Power: WARN < -8.0 dBm, CRIT < -12.0 dBm
##############################################################################

set -euo pipefail

# ========================= DEFAULTS ===================================
SWITCH_IP=""
SWITCH_USER="admin"
SSH_KEY=""
KNOWN_HOSTS_FILE=""
INSECURE_HOSTKEY=false
VSAN="1"
DRY_RUN=false
LOG_FILE="portcheck_$(date +%Y%m%d_%H%M%S).log"

EXPECTED_PORTS=""
PORT_FILE=""
ALIAS_FILE=""

RX_WARN_DBM="-14.0"
RX_CRIT_DBM="-17.0"
TX_WARN_DBM="-8.0"
TX_CRIT_DBM="-12.0"

TOTAL_PORTS_CHECKED=0
PORTS_UP=0
PORTS_DOWN=0
PORTS_NO_SFP=0
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
--vsan) VSAN="$2"; shift 2 ;;
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
echo " --ports PORTS Comma-separated interface names (e.g., fc1/1,fc1/2,fc1/3)"
echo " --port-file FILE File with one interface per line"
echo " (none) Auto-detect from 'show interface brief' (all up ports)"
echo ""
echo "Optional:"
echo " --dry-run Print commands without executing"
echo " --switch-user USER SSH username (default: ${SWITCH_USER})"
echo " --ssh-key FILE SSH private key file"
echo " --known-hosts-file FILE Use a dedicated known_hosts file"
echo " --insecure-hostkey Disable host key verification (lab use only)"
echo " --vsan VSAN VSAN for flogi lookup (default: ${VSAN})"
echo " --alias-file FILE Alias file for WWN verification"
echo " --rx-warn DBM RX warning threshold (default: ${RX_WARN_DBM})"
echo " --rx-crit DBM RX critical threshold (default: ${RX_CRIT_DBM})"
echo " --tx-warn DBM TX warning threshold (default: ${TX_WARN_DBM})"
echo " --tx-crit DBM TX critical threshold (default: ${TX_CRIT_DBM})"
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
output=$("${ssh_cmd[@]}" "terminal length 0 ; ${cmd}" 2>&1) || {
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

run_cmd_confirm() {
local cmd="$1"
local description="${2:-}"

if [[ -n "$description" ]]; then
log "# $description"
fi
log ">>> $cmd (with auto-confirm)"

if [[ "$DRY_RUN" == false ]]; then
local output
mapfile -t ssh_cmd < <(build_ssh_cmd)
output=$(printf 'y\n' | "${ssh_cmd[@]}" "terminal length 0 ; ${cmd}" 2>&1) || {
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

# ========================= UTILITY ====================================
trim() {
local var="$1"
var="${var#"${var%%[![:space:]]*}"}"
var="${var%"${var##*[![:space:]]}"}"
echo "$var"
}

float_lt() {
awk "BEGIN { exit !($1 < $2) }"
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
echo " VSAN : ${VSAN}"
echo " Log File : ${LOG_FILE}"
echo " RX Thresholds: WARN < ${RX_WARN_DBM} dBm, CRIT < ${RX_CRIT_DBM} dBm"
echo " TX Thresholds: WARN < ${TX_WARN_DBM} dBm, CRIT < ${TX_CRIT_DBM} dBm"
if [[ -n "$EXPECTED_PORTS" ]]; then
echo " Port Source : Command line (--ports ${EXPECTED_PORTS})"
elif [[ -n "$PORT_FILE" ]]; then
echo " Port Source : File (${PORT_FILE})"
else
echo " Port Source : Auto-detect from show interface brief"
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

if [[ -n "$PORT_FILE" && ! -f "$PORT_FILE" ]]; then
echo "ERROR: Port file not found: ${PORT_FILE}"
exit 1
fi
if [[ -n "$ALIAS_FILE" && ! -f "$ALIAS_FILE" ]]; then
echo "ERROR: Alias file not found: ${ALIAS_FILE}"
exit 1
fi

log "========== Cisco MDS Port & SFP Health Check Started =========="

# ======================================================================
# STEP 1: COLLECT show interface brief OUTPUT
# ======================================================================
log "============ STEP 1: COLLECT INTERFACE STATUS ============"

INTF_BRIEF_OUTPUT=""

if [[ "$DRY_RUN" == false ]]; then
INTF_BRIEF_OUTPUT=$(run_cmd "show interface brief" "Collect port status")
if [[ -z "$INTF_BRIEF_OUTPUT" ]]; then
log "!!! ERROR: Empty 'show interface brief' output. Check connectivity."
exit 1
fi
echo "$INTF_BRIEF_OUTPUT" >> "$LOG_FILE"
log ""
else
log " (dry-run: show interface brief would be collected here)"
log ""
fi

# ======================================================================
# STEP 2: DETERMINE PORT LIST
# ======================================================================
log "============ STEP 2: DETERMINE PORT LIST ============"

declare -A EXPECTED_PORT_MAP
declare -A UP_PORT_MAP
declare -A PORT_VSAN_MAP

if [[ "$DRY_RUN" == false && -n "$INTF_BRIEF_OUTPUT" ]]; then
while IFS= read -r line; do
if [[ "$line" =~ ^[[:space:]]*(fc[0-9]+/[0-9]+)[[:space:]]+([0-9-]+)[[:space:]]+([A-Za-z_-]+)[[:space:]]+([a-zA-Z0-9]+)[[:space:]]+([0-9GMK-]+)[[:space:]]+([a-zA-Z]+) ]]; then
local_intf="${BASH_REMATCH[1]}"
local_vsan="${BASH_REMATCH[2]}"
local_status="${BASH_REMATCH[6]}"

if [[ "$local_status" == "up" ]]; then
UP_PORT_MAP["${local_intf}"]=1
PORT_VSAN_MAP["${local_intf}"]="${local_vsan}"
fi
fi
done <<< "$INTF_BRIEF_OUTPUT"

log " Up ports detected: ${!UP_PORT_MAP[*]}"
log " Total up: ${#UP_PORT_MAP[@]}"
fi

if [[ -n "$EXPECTED_PORTS" ]]; then
IFS=',' read -ra PORT_ARRAY <<< "$EXPECTED_PORTS"
for p in "${PORT_ARRAY[@]}"; do
p=$(trim "$p")
[[ -z "$p" ]] && continue
EXPECTED_PORT_MAP["$p"]=1
done
log " Expected ports (from --ports): ${!EXPECTED_PORT_MAP[*]}"
elif [[ -n "$PORT_FILE" ]]; then
while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue
EXPECTED_PORT_MAP["$line"]=1
done < "$PORT_FILE"
log " Expected ports (from ${PORT_FILE}): ${!EXPECTED_PORT_MAP[*]}"
else
for port_intf in "${!UP_PORT_MAP[@]}"; do
EXPECTED_PORT_MAP["$port_intf"]=1
done
log " Expected ports (auto-detected): ${!EXPECTED_PORT_MAP[*]}"
fi

EXPECTED_TOTAL=${#EXPECTED_PORT_MAP[@]}
log " Total expected ports: ${EXPECTED_TOTAL}"
log ""

# ======================================================================
# STEP 3: VALIDATE EXPECTED PORTS ARE UP
# ======================================================================
log "============ STEP 3: VALIDATE EXPECTED PORTS ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log_raw " +------------+----------+------+"
log_raw " | Interface | Status | VSAN |"
log_raw " +------------+----------+------+"

SORTED_EXPECTED=($(echo "${!EXPECTED_PORT_MAP[@]}" | tr ' ' '\n' | sort -t'/' -k1,1 -k2,2n))

for port_intf in "${SORTED_EXPECTED[@]}"; do
port_display=$(printf "%-10s" "$port_intf")

if [[ -n "${UP_PORT_MAP[$port_intf]+_}" ]]; then
vsan_val="${PORT_VSAN_MAP[$port_intf]:-?}"
vsan_display=$(printf "%-4s" "$vsan_val")
log_raw " | ${port_display} | UP | ${vsan_display} |"
PORTS_UP=$((PORTS_UP + 1))
else
actual_state="NOT UP"

if [[ -n "$INTF_BRIEF_OUTPUT" ]]; then
state_line=$(echo "$INTF_BRIEF_OUTPUT" | grep -E "^[[:space:]]*${port_intf}[[:space:]]" | head -1 || true)
if [[ -n "$state_line" ]]; then
if [[ "$state_line" =~ sfpAbsent ]]; then
actual_state="NO SFP"
PORTS_NO_SFP=$((PORTS_NO_SFP + 1))
elif [[ "$state_line" =~ down ]]; then
actual_state="DOWN"
PORTS_DOWN=$((PORTS_DOWN + 1))
elif [[ "$state_line" =~ noOperMembers ]]; then
actual_state="NO OPER"
PORTS_OTHER=$((PORTS_OTHER + 1))
else
PORTS_OTHER=$((PORTS_OTHER + 1))
fi
else
actual_state="NOT FOUND"
PORTS_OTHER=$((PORTS_OTHER + 1))
fi
fi

log_raw " | ${port_display} | *** ${actual_state} *** | --- | EXPECTED UP"
EXPECTED_MISSING=$((EXPECTED_MISSING + 1))
fi

TOTAL_PORTS_CHECKED=$((TOTAL_PORTS_CHECKED + 1))
done

log_raw " +------------+----------+------+"
log ""

if [[ $EXPECTED_MISSING -gt 0 ]]; then
log " !!! WARNING: ${EXPECTED_MISSING} of ${EXPECTED_TOTAL} expected ports are NOT up"
else
log " OK: All ${EXPECTED_TOTAL} expected ports are up"
fi
else
log " (dry-run: would validate ${EXPECTED_TOTAL} expected ports)"
fi
log ""

# ======================================================================
# STEP 4: SFP DIAGNOSTICS
# ======================================================================
log "============ STEP 4: SFP DIAGNOSTICS (transceiver details) ============"

if [[ "$DRY_RUN" == false ]]; then
SFP_PORTS=()
for port_intf in "${SORTED_EXPECTED[@]}"; do
if [[ -n "${UP_PORT_MAP[$port_intf]+_}" ]]; then
SFP_PORTS+=("$port_intf")
fi
done

if [[ ${#SFP_PORTS[@]} -eq 0 ]]; then
log " No up ports to check SFP diagnostics on."
else
log ""
log_raw " +------------+-------------+-------------+--------+------------------+"
log_raw " | Interface | RX Pwr(dBm) | TX Pwr(dBm) | Status | Detail |"
log_raw " +------------+-------------+-------------+--------+------------------+"

for port_intf in "${SFP_PORTS[@]}"; do
sfp_output=$(run_cmd "show interface ${port_intf} transceiver details" "SFP diagnostics for ${port_intf}" 2>/dev/null) || {
log " !!! Failed to get transceiver details for ${port_intf}"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
continue
}

rx_dbm=""
if echo "$sfp_output" | grep -qi "Rx Power"; then
rx_line=$(echo "$sfp_output" | grep -i "Rx Power" | head -1)
if [[ "$rx_line" =~ (-?[0-9]+\.?[0-9]*)[[:space:]]*dBm ]]; then
rx_dbm="${BASH_REMATCH[1]}"
fi
fi

tx_dbm=""
if echo "$sfp_output" | grep -qi "Tx Power"; then
tx_line=$(echo "$sfp_output" | grep -i "Tx Power" | head -1)
if [[ "$tx_line" =~ (-?[0-9]+\.?[0-9]*)[[:space:]]*dBm ]]; then
tx_dbm="${BASH_REMATCH[1]}"
fi
fi

port_display=$(printf "%-10s" "$port_intf")
rx_display=$(printf "%-11s" "${rx_dbm:-N/A}")
tx_display=$(printf "%-11s" "${tx_dbm:-N/A}")
status="OK"
detail=""

if [[ -z "$rx_dbm" || -z "$tx_dbm" ]]; then
status="UNKNOWN"
detail="Could not parse power"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
else
if float_lt "$rx_dbm" "$RX_CRIT_DBM" 2>/dev/null; then
status="CRIT"
detail="RX below ${RX_CRIT_DBM}"
elif float_lt "$rx_dbm" "$RX_WARN_DBM" 2>/dev/null; then
status="WARN"
detail="RX below ${RX_WARN_DBM}"
fi

if float_lt "$tx_dbm" "$TX_CRIT_DBM" 2>/dev/null; then
status="CRIT"
detail="${detail:+${detail}; }TX below ${TX_CRIT_DBM}"
elif float_lt "$tx_dbm" "$TX_WARN_DBM" 2>/dev/null; then
if [[ "$status" == "OK" ]]; then status="WARN"; fi
detail="${detail:+${detail}; }TX below ${TX_WARN_DBM}"
fi

case "$status" in
OK) SFP_OK=$((SFP_OK + 1)) ;;
WARN) SFP_WARN=$((SFP_WARN + 1)) ;;
CRIT) SFP_CRIT=$((SFP_CRIT + 1)) ;;
esac
fi

[[ -z "$detail" ]] && detail="Clean"
status_display=$(printf "%-6s" "$status")
detail_display=$(printf "%-16s" "$detail")
log_raw " | ${port_display} | ${rx_display} | ${tx_display} | ${status_display} | ${detail_display} |"

echo "--- transceiver ${port_intf} ---" >> "$LOG_FILE"
echo "$sfp_output" >> "$LOG_FILE"
echo "--- end transceiver ${port_intf} ---" >> "$LOG_FILE"

sleep 1
done

log_raw " +------------+-------------+-------------+--------+------------------+"
log ""

[[ $SFP_CRIT -gt 0 ]] && log " !!! CRITICAL: ${SFP_CRIT} port(s) with critical SFP power levels — check cables!"
[[ $SFP_WARN -gt 0 ]] && log " !!! WARNING: ${SFP_WARN} port(s) with marginal SFP power levels"
[[ $SFP_OK -gt 0 ]] && log " OK: ${SFP_OK} port(s) with clean SFP power levels"
fi
else
log " (dry-run: would run 'show interface transceiver details' on each up port)"
fi
log ""

# ======================================================================
# STEP 5: PORT ERROR COUNTERS
# ======================================================================
log "============ STEP 5: PORT ERROR COUNTERS ============"

if [[ "$DRY_RUN" == false ]]; then
PORTERR_OUTPUT=$(run_cmd "show interface counters errors" "Collect port error counters")
if [[ -n "$PORTERR_OUTPUT" ]]; then
echo "$PORTERR_OUTPUT" >> "$LOG_FILE"

PORTS_WITH_ERRORS=0
for port_intf in "${SORTED_EXPECTED[@]}"; do
if [[ -n "${UP_PORT_MAP[$port_intf]+_}" ]]; then
err_line=$(echo "$PORTERR_OUTPUT" | grep -E "^[[:space:]]*${port_intf}[[:space:]]" | head -1 || true)
if [[ -n "$err_line" ]]; then
has_errors=false
err_values=$(echo "$err_line" | awk '{for(i=2;i<=NF;i++) print $i}')
for val in $err_values; do
if [[ "$val" =~ ^[0-9]+$ && "$val" -gt 0 ]]; then
has_errors=true
break
fi
done
if [[ "$has_errors" == true ]]; then
log " !!! Port ${port_intf}: Non-zero error counters detected"
log " ${err_line}"
PORTS_WITH_ERRORS=$((PORTS_WITH_ERRORS + 1))
fi
fi
fi
done

if [[ $PORTS_WITH_ERRORS -eq 0 ]]; then
log " OK: No error counters on expected up ports"
else
log " !!! WARNING: ${PORTS_WITH_ERRORS} port(s) have non-zero error counters"
fi
fi
else
log " (dry-run: would run 'show interface counters errors')"
fi
log ""

# ======================================================================
# STEP 6: WWN LOGIN VERIFICATION via flogi database (optional)
# ======================================================================
if [[ -n "$ALIAS_FILE" ]]; then
log "============ STEP 6: WWN LOGIN VERIFICATION via flogi/fcns (from ${ALIAS_FILE}) ============"

FLOGI_OUTPUT=""
FCNS_OUTPUT=""
if [[ "$DRY_RUN" == false ]]; then
FLOGI_OUTPUT=$(run_cmd "show flogi database vsan ${VSAN}" "Collect FLOGI database for VSAN ${VSAN}")
echo "$FLOGI_OUTPUT" >> "$LOG_FILE"

FCNS_OUTPUT=$(run_cmd "show fcns database vsan ${VSAN}" "Collect FCNS database for VSAN ${VSAN}")
echo "$FCNS_OUTPUT" >> "$LOG_FILE"
fi

declare -A ALIAS_WWNS
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

if [[ "$DRY_RUN" == false && ( -n "$FLOGI_OUTPUT" || -n "$FCNS_OUTPUT" ) ]]; then
log ""
log_raw " +----------------------------------+-------------------------+----------+------------+----------------+"
log_raw " | Alias | WWN | Logged In| Interface | Source |"
log_raw " +----------------------------------+-------------------------+----------+------------+----------------+"

SORTED_ALIASES=($(echo "${!ALIAS_WWNS[@]}" | tr ' ' '\n' | sort))

for alias_name in "${SORTED_ALIASES[@]}"; do
wwn="${ALIAS_WWNS[$alias_name]}"
alias_display=$(printf "%-32s" "$alias_name")
wwn_display=$(printf "%-23s" "$wwn")

found=false
found_intf="---"
found_source="---"

if [[ -n "$FLOGI_OUTPUT" ]]; then
flogi_line=$(echo "$FLOGI_OUTPUT" | grep -i "$wwn" | head -1 || true)
if [[ -n "$flogi_line" ]]; then
found=true
found_source="FLOGI (local)"
if [[ "$flogi_line" =~ (fc[0-9]+/[0-9]+) ]]; then
found_intf="${BASH_REMATCH[1]}"
fi
fi
fi

if [[ "$found" == false && -n "$FCNS_OUTPUT" ]]; then
fcns_line=$(echo "$FCNS_OUTPUT" | grep -i "$wwn" | head -1 || true)
if [[ -n "$fcns_line" ]]; then
found=true
found_source="FCNS (remote)"
found_intf="remote"
fi
fi

intf_display=$(printf "%-10s" "$found_intf")
source_display=$(printf "%-14s" "$found_source")

if [[ "$found" == true ]]; then
log_raw " | ${alias_display} | ${wwn_display} | YES | ${intf_display} | ${source_display} |"
WWN_FOUND=$((WWN_FOUND + 1))
else
log_raw " | ${alias_display} | ${wwn_display} | *** NO ***| --- | --- |"
WWN_MISSING=$((WWN_MISSING + 1))
fi
done

log_raw " +----------------------------------+-------------------------+----------+------------+----------------+"
log ""

if [[ $WWN_MISSING -gt 0 ]]; then
log " !!! WARNING: ${WWN_MISSING} of ${TOTAL_ALIASES} alias WWNs are NOT logged into the fabric"
log " Possible causes:"
log " - Device is powered off"
log " - Cable not connected or connected to a different switch/VSAN"
log " - HBA driver not loaded"
log " - Wrong WWN in alias file"
log " - Device is in a different VSAN (checked VSAN ${VSAN})"
else
log " OK: All ${TOTAL_ALIASES} alias WWNs are logged into the fabric"
fi
else
log " (dry-run: would verify ${TOTAL_ALIASES} WWNs against flogi/fcns database)"
fi
log ""
fi

# ======================================================================
# SUMMARY
# ======================================================================
log "============ SUMMARY ============"
log ""
log " Switch: ${SWITCH_IP} | VSAN: ${VSAN}"
log ""
log " --- Port Status ---"
log " Expected ports: ${EXPECTED_TOTAL}"
log " Up: ${PORTS_UP}"
log " Missing (expected): ${EXPECTED_MISSING}"
[[ $PORTS_DOWN -gt 0 ]] && log " Down: ${PORTS_DOWN}"
[[ $PORTS_NO_SFP -gt 0 ]] && log " No SFP: ${PORTS_NO_SFP}"
[[ $PORTS_OTHER -gt 0 ]] && log " Other: ${PORTS_OTHER}"
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
log "========== Cisco MDS Port & SFP Health Check Complete =========="