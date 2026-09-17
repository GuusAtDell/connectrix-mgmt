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
float_lt() {
awk "BEGIN { exit !($1 < $2) }"
}

float_gte() {
awk "BEGIN { exit !($1 >= $2) }"
}

# ========================= INPUT VALIDATION HELPERS ===================
validate_port_token() {
local port_value="$1"
[[ "$port_value" =~ ^[0-9]+$ ]]
}

add_expected_port() {
local port_value="$1"
if ! validate_port_token "$port_value"; then
log "ERROR: Invalid port value '${port_value}' — expected numeric port index"
exit 1
fi
EXPECTED_PORT_MAP["$port_value"]=1
}

# ========================= SWITCHSHOW PARSERS =========================
parse_switchshow_line() {
local line="$1"
local trimmed_line=""
local -a fields=()
local port_index=""
local port_num=""
local state=""
local wwn=""
local token=""

trimmed_line=$(trim "$line")

[[ -z "$trimmed_line" ]] && return 1
[[ "$trimmed_line" =~ ^[-=]+$ ]] && return 1
[[ "$trimmed_line" =~ ^(Index|Area|Slot|Port|switchName|switchType|LS[[:space:]]+Attributes|Index[[:space:]]+Slot) ]] && return 1

read -r -a fields <<< "$trimmed_line"
[[ ${#fields[@]} -lt 6 ]] && return 1

[[ ! "${fields[0]}" =~ ^[0-9]+$ ]] && return 1
[[ ! "${fields[1]}" =~ ^[0-9]+$ ]] && return 1

port_index="${fields[0]}"
port_num="${fields[1]}"

for token in "${fields[@]}"; do
case "$token" in
Online|Offline|No_Light|No_Module|Disabled|Faulty|In_Sync)
state="$token"
break
;;
esac
done

if [[ "$trimmed_line" =~ ([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){7}) ]]; then
wwn="${BASH_REMATCH[1],,}"
fi

[[ -z "$state" ]] && return 1
printf '%s|%s|%s|%s\n' "$port_index" "$port_num" "$state" "$wwn"
return 0
}

parse_switchshow_output() {
local input="$1"
local parsed=""
while IFS= read -r line; do
parsed=$(parse_switchshow_line "$line") || continue
printf '%s\n' "$parsed"
done <<< "$input"
}

get_switchshow_state_for_port() {
local target_port="$1"
local input="$2"
local parsed=""
local local_index=""
local local_port=""
local local_state=""
local local_wwn=""

while IFS= read -r line; do
parsed=$(parse_switchshow_line "$line") || continue
IFS='|' read -r local_index local_port local_state local_wwn <<< "$parsed"
if [[ "$local_index" == "$target_port" ]]; then
printf '%s\n' "$local_state"
return 0
fi
done <<< "$input"

return 1
}

# ========================= PORTERRSHOW PARSERS ========================
parse_porterrshow_line() {
local line="$1"
local trimmed_line=""
local port_index=""
local remainder=""
local -a values=()
local value=""

trimmed_line=$(trim "$line")

[[ -z "$trimmed_line" ]] && return 1
[[ "$trimmed_line" =~ ^[-=]+$ ]] && return 1
[[ "$trimmed_line" =~ ^(frames|enc_in|crc_err|too_shrt|too_long|bad_eof|enc_out|disc_c3|link_fail|loss_sync|loss_sig|port) ]] && return 1

if [[ "$trimmed_line" =~ ^([0-9]+):?[[:space:]]+(.*)$ ]]; then
port_index="${BASH_REMATCH[1]}"
remainder="${BASH_REMATCH[2]}"
else
return 1
fi

read -r -a values <<< "$remainder"
[[ ${#values[@]} -eq 0 ]] && return 1

for value in "${values[@]}"; do
[[ ! "$value" =~ ^[0-9]+$ ]] && return 1
done

printf '%s|%s\n' "$port_index" "$remainder"
return 0
}

get_porterrshow_values_for_port() {
local target_port="$1"
local input="$2"
local parsed=""
local local_index=""
local local_values=""

while IFS= read -r line; do
parsed=$(parse_porterrshow_line "$line") || continue
IFS='|' read -r local_index local_values <<< "$parsed"
if [[ "$local_index" == "$target_port" ]]; then
printf '%s\n' "$local_values"
return 0
fi
done <<< "$input"

return 1
}

porterrshow_has_nonzero_errors() {
local values="$1"
local val=""
for val in $values; do
if [[ "$val" =~ ^[0-9]+$ && "$val" -gt 0 ]]; then
return 0
fi
done
return 1
}

# ========================= SFP PARSERS ================================
extract_power_dbm() {
local label="$1"
local input="$2"
local normalized=""
local matched_line=""

normalized=$(printf '%s\n' "$input" | tr -d '\r')
matched_line=$(echo "$normalized" | grep -iE "${label}[[:space:]]*Power[[:space:]]*:|${label}[[:space:]]*Power" | head -1 || true)

if [[ -n "$matched_line" && "$matched_line" =~ (-?[0-9]+\.?[0-9]*)[[:space:]]*dBm ]]; then
printf '%s\n' "${BASH_REMATCH[1]}"
return 0
fi

return 1
}

parse_sfpshow_output() {
local input="$1"
local rx_dbm=""
local tx_dbm=""
local parse_status=""

rx_dbm=$(extract_power_dbm "RX" "$input" || true)
tx_dbm=$(extract_power_dbm "TX" "$input" || true)

if [[ -n "$rx_dbm" && -n "$tx_dbm" ]]; then
parse_status="BOTH"
elif [[ -n "$rx_dbm" ]]; then
parse_status="RX_ONLY"
elif [[ -n "$tx_dbm" ]]; then
parse_status="TX_ONLY"
else
parse_status="NONE"
fi

printf '%s|%s|%s\n' "$parse_status" "$rx_dbm" "$tx_dbm"
}

# ========================= NODEFIND PARSERS ===========================
parse_nodefind_output() {
local input="$1"
local normalized=""
local port_found=""
local device_info=""
local speed_info=""
local detail=""

normalized=$(printf '%s\n' "$input" | tr -d '\r')

if echo "$normalized" | grep -Eqi 'no[[:space:]]+device[[:space:]]+found|not[[:space:]]+found'; then
printf 'NOT_FOUND|||Not logged in to fabric\n'
return 0
fi

if [[ "$normalized" =~ Port[[:space:]_]+Index:[[:space:]]*([0-9]+) ]]; then
port_found="${BASH_REMATCH[1]}"
elif [[ "$normalized" =~ Port:[[:space:]]*([0-9]+) ]]; then
port_found="${BASH_REMATCH[1]}"
fi

if [[ "$normalized" =~ HN:([^[:space:]\."]+) ]]; then
device_info="HN:${BASH_REMATCH[1]}"
else
local nodesymb_line=""
nodesymb_line=$(echo "$normalized" | grep -i 'NodeSymb' | head -1 || true)
if [[ -n "$nodesymb_line" && "$nodesymb_line" =~ \"([^\"]+)\" ]]; then
device_info="${BASH_REMATCH[1]:0:28}"
fi
fi

if [[ "$normalized" =~ Device[[:space:]]+link[[:space:]]+speed:[[:space:]]*([0-9]+G) ]]; then
speed_info="${BASH_REMATCH[1]}"
elif [[ "$normalized" =~ ([0-9]+G)[[:space:]]*(SWL|LWL|NWL)? ]]; then
speed_info="${BASH_REMATCH[1]}"
fi

if [[ -n "$port_found" || "$normalized" =~ Port[[:space:]_]+Index: ]]; then
detail="$device_info"
if [[ -n "$speed_info" ]]; then
detail="${detail:+${detail} }${speed_info}"
fi
[[ -z "$detail" ]] && detail="Found"
printf 'FOUND|%s|%s|%s\n' "$port_found" "$speed_info" "$detail"
return 0
fi

if [[ -n "$(trim "$normalized")" ]]; then
detail="$device_info"
if [[ -n "$speed_info" ]]; then
detail="${detail:+${detail} }${speed_info}"
fi
[[ -z "$detail" ]] && detail="Unrecognized nodefind output"
printf 'AMBIGUOUS|%s|%s|%s\n' "$port_found" "$speed_info" "$detail"
return 0
fi

printf 'NOT_FOUND|||Unrecognized nodefind output\n'
return 0
}

# ========================= ALIAS FILE PARSERS =========================
load_alias_file() {
local alias_file="$1"
local line=""
local current_alias=""
local normalized_wwn=""

declare -gA ALIAS_WWNS=()
declare -gA WWN_ALIAS_MAP=()

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue

if [[ "$line" =~ ^alias:[[:space:]]*(.+)$ ]]; then
current_alias=$(trim "${BASH_REMATCH[1]}")
[[ -z "$current_alias" ]] && {
log "ERROR: Empty alias name found in ${alias_file}"
exit 1
}
if [[ -n "${ALIAS_WWNS[$current_alias]+_}" ]]; then
log "ERROR: Duplicate alias name '${current_alias}' found in ${alias_file}"
exit 1
fi
elif [[ "$line" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){7}$ ]]; then
if [[ -z "$current_alias" ]]; then
log "ERROR: WWN '${line}' found without preceding alias in ${alias_file}"
exit 1
fi
normalized_wwn="${line,,}"
if [[ -n "${WWN_ALIAS_MAP[$normalized_wwn]+_}" ]]; then
log "ERROR: Duplicate WWN '${normalized_wwn}' found in ${alias_file}"
exit 1
fi
ALIAS_WWNS["$current_alias"]="$normalized_wwn"
WWN_ALIAS_MAP["$normalized_wwn"]="$current_alias"
current_alias=""
else
log "ERROR: Unrecognized alias-file line '${line}' in ${alias_file}"
exit 1
fi
done < "$alias_file"

if [[ -n "$current_alias" ]]; then
log "ERROR: Alias '${current_alias}' has no WWN in ${alias_file}"
exit 1
fi
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

declare -A EXPECTED_PORT_MAP
declare -A ONLINE_PORT_MAP
declare -A PORT_WWN_MAP

if [[ "$DRY_RUN" == false && -n "$SWITCHSHOW_OUTPUT" ]]; then
while IFS='|' read -r local_index local_port local_state local_wwn; do
[[ -z "$local_index" ]] && continue

if [[ "$local_state" == "Online" ]]; then
ONLINE_PORT_MAP["${local_index}"]=1
if [[ -n "$local_wwn" ]]; then
PORT_WWN_MAP["${local_index}"]="$local_wwn"
fi
fi
done < <(parse_switchshow_output "$SWITCHSHOW_OUTPUT")

log " Online ports detected: ${!ONLINE_PORT_MAP[*]}"
log " Total online: ${#ONLINE_PORT_MAP[@]}"
fi

if [[ -n "$EXPECTED_PORTS" ]]; then
IFS=',' read -ra PORT_ARRAY <<< "$EXPECTED_PORTS"
for p in "${PORT_ARRAY[@]}"; do
p=$(trim "$p")
[[ -z "$p" ]] && continue
add_expected_port "$p"
done
log " Expected ports (from --ports): ${!EXPECTED_PORT_MAP[*]}"

elif [[ -n "$PORT_FILE" ]]; then
while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue
add_expected_port "$line"
done < "$PORT_FILE"
log " Expected ports (from ${PORT_FILE}): ${!EXPECTED_PORT_MAP[*]}"

else
for port_idx in "${!ONLINE_PORT_MAP[@]}"; do
EXPECTED_PORT_MAP["$port_idx"]=1
done
log " Expected ports (auto-detected from switchshow): ${!EXPECTED_PORT_MAP[*]}"
fi

EXPECTED_TOTAL=${#EXPECTED_PORT_MAP[@]}
log " Total expected ports: ${EXPECTED_TOTAL}"

for port_idx in "${!EXPECTED_PORT_MAP[@]}"; do
if [[ "$DRY_RUN" == false && -z "${ONLINE_PORT_MAP[$port_idx]+_}" ]]; then
if ! get_switchshow_state_for_port "$port_idx" "$SWITCHSHOW_OUTPUT" >/dev/null 2>&1; then
log " !!! Requested port ${port_idx} does not appear in switchshow output"
fi
fi
done
log ""

# ======================================================================
# STEP 3: VALIDATE EXPECTED PORTS ARE ONLINE
# ======================================================================
log "============ STEP 3: VALIDATE EXPECTED PORTS ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log_raw " +-------+----------------------+---------------------------+"
log_raw " | Port | Status | WWN |"
log_raw " +-------+----------------------+---------------------------+"

SORTED_EXPECTED=($(echo "${!EXPECTED_PORT_MAP[@]}" | tr ' ' '\n' | sort -n))

for port_idx in "${SORTED_EXPECTED[@]}"; do
port_display=$(printf "%-5s" "$port_idx")

if [[ -n "${ONLINE_PORT_MAP[$port_idx]+_}" ]]; then
wwn="${PORT_WWN_MAP[$port_idx]:-N/A}"
log_raw " | ${port_display} | ONLINE | ${wwn} |"
PORTS_ONLINE=$((PORTS_ONLINE + 1))
else
actual_state="NOT ONLINE"
parsed_state=$(get_switchshow_state_for_port "$port_idx" "$SWITCHSHOW_OUTPUT" || true)

case "$parsed_state" in
No_Light)
actual_state="NO LIGHT"
PORTS_NO_LIGHT=$((PORTS_NO_LIGHT + 1))
;;
No_Module)
actual_state="NO SFP"
PORTS_OTHER=$((PORTS_OTHER + 1))
;;
Disabled)
actual_state="DISABLED"
PORTS_OTHER=$((PORTS_OTHER + 1))
;;
Offline)
actual_state="OFFLINE"
PORTS_OFFLINE=$((PORTS_OFFLINE + 1))
;;
In_Sync)
actual_state="IN SYNC"
PORTS_OTHER=$((PORTS_OTHER + 1))
;;
Faulty)
actual_state="FAULTY"
PORTS_OTHER=$((PORTS_OTHER + 1))
;;
Online)
actual_state="ONLINE"
;;
"")
actual_state="NOT FOUND"
PORTS_OTHER=$((PORTS_OTHER + 1))
;;
*)
actual_state="$parsed_state"
PORTS_OTHER=$((PORTS_OTHER + 1))
;;
esac

log_raw " | ${port_display} | *** ${actual_state} *** | --- EXPECTED ONLINE |"
EXPECTED_MISSING=$((EXPECTED_MISSING + 1))
fi

TOTAL_PORTS_CHECKED=$((TOTAL_PORTS_CHECKED + 1))
done

log_raw " +-------+----------------------+---------------------------+"
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
log_raw " +-------+-------------+-------------+--------+--------------------------+"
log_raw " | Port | RX Pwr(dBm) | TX Pwr(dBm) | Status | Detail |"
log_raw " +-------+-------------+-------------+--------+--------------------------+"

for port_idx in "${SFPSHOW_PORTS[@]}"; do
sfp_output=$(run_cmd "sfpshow ${port_idx}" "SFP diagnostics for port ${port_idx}" 2>/dev/null) || {
log " !!! Failed to get sfpshow for port ${port_idx}"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
continue
}

IFS='|' read -r sfp_parse_status rx_dbm tx_dbm <<< "$(parse_sfpshow_output "$sfp_output")"

port_display=$(printf "%-5s" "$port_idx")
rx_display=$(printf "%-11s" "${rx_dbm:-N/A}")
tx_display=$(printf "%-11s" "${tx_dbm:-N/A}")
status="OK"
detail=""

case "$sfp_parse_status" in
BOTH)
;;
RX_ONLY)
status="UNKNOWN"
detail="TX power parse failed"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
;;
TX_ONLY)
status="UNKNOWN"
detail="RX power parse failed"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
;;
NONE|*)
status="UNKNOWN"
detail="Both power parses failed"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
;;
esac

if [[ "$status" != "UNKNOWN" ]]; then
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
if [[ "$status" == "OK" ]]; then
status="WARN"
fi
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
detail_display=$(printf "%-24s" "$detail")
log_raw " | ${port_display} | ${rx_display} | ${tx_display} | ${status_display} | ${detail_display} |"

echo "--- sfpshow ${port_idx} ---" >> "$LOG_FILE"
echo "$sfp_output" >> "$LOG_FILE"
echo "--- end sfpshow ${port_idx} ---" >> "$LOG_FILE"

sleep 1
done

log_raw " +-------+-------------+-------------+--------+--------------------------+"
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

PORTS_WITH_ERRORS=0

for port_idx in "${SORTED_EXPECTED[@]}"; do
if [[ -n "${ONLINE_PORT_MAP[$port_idx]+_}" ]]; then
err_values=$(get_porterrshow_values_for_port "$port_idx" "$PORTERR_OUTPUT" || true)
if [[ -n "$err_values" ]]; then
if porterrshow_has_nonzero_errors "$err_values"; then
log " !!! Port ${port_idx}: Non-zero error counters detected"
log " ${port_idx}: ${err_values}"
PORTS_WITH_ERRORS=$((PORTS_WITH_ERRORS + 1))
fi
else
log " !!! Port ${port_idx}: Parser could not classify any porterrshow row"
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
# STEP 6: WWN LOGIN VERIFICATION via nodefind (optional, if --alias-file provided)
# ======================================================================
if [[ -n "$ALIAS_FILE" ]]; then
log "============ STEP 6: WWN LOGIN VERIFICATION via nodefind (from ${ALIAS_FILE}) ============"

load_alias_file "$ALIAS_FILE"
TOTAL_ALIASES=${#ALIAS_WWNS[@]}
log " Aliases loaded from ${ALIAS_FILE}: ${TOTAL_ALIASES}"

if [[ "$DRY_RUN" == false ]]; then
log ""
log_raw " +----------------------------------+-------------------------+----------+-------+--------------------------------+"
log_raw " | Alias | WWN | Logged In| Port | Detail |"
log_raw " +----------------------------------+-------------------------+----------+-------+--------------------------------+"

SORTED_ALIASES=($(echo "${!ALIAS_WWNS[@]}" | tr ' ' '\n' | sort))

for alias_name in "${SORTED_ALIASES[@]}"; do
wwn="${ALIAS_WWNS[$alias_name]}"
alias_display=$(printf "%-32s" "$alias_name")
wwn_display=$(printf "%-23s" "$wwn")

nodefind_output=$(run_cmd "nodefind ${wwn}" "nodefind for alias ${alias_name} (${wwn})" 2>/dev/null) || {
log " !!! Failed to run nodefind for ${alias_name} (${wwn})"
log_raw " | ${alias_display} | ${wwn_display} | ERROR | --- | nodefind command failed |"
WWN_MISSING=$((WWN_MISSING + 1))
continue
}

echo "--- nodefind ${wwn} (${alias_name}) ---" >> "$LOG_FILE"
echo "$nodefind_output" >> "$LOG_FILE"
echo "--- end nodefind ---" >> "$LOG_FILE"

nodefind_parsed=$(parse_nodefind_output "$nodefind_output")
IFS='|' read -r nodefind_status port_found speed_info detail <<< "$nodefind_parsed"

case "$nodefind_status" in
FOUND)
port_display=$(printf "%-5s" "${port_found:-?}")
detail_display=$(printf "%-30s" "$detail")
log_raw " | ${alias_display} | ${wwn_display} | YES | ${port_display} | ${detail_display} |"
WWN_FOUND=$((WWN_FOUND + 1))
;;
AMBIGUOUS)
port_display=$(printf "%-5s" "${port_found:-?}")
detail_display=$(printf "%-30s" "$detail")
log_raw " | ${alias_display} | ${wwn_display} | ??? | ${port_display} | ${detail_display} |"
WWN_MISSING=$((WWN_MISSING + 1))
;;
NOT_FOUND|*)
detail_display=$(printf "%-30s" "$detail")
log_raw " | ${alias_display} | ${wwn_display} | *** NO ***| --- | ${detail_display} |"
WWN_MISSING=$((WWN_MISSING + 1))
;;
esac

sleep 1
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