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

normalize_wwn() {
local raw="$1"
local hex=""
hex=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd '0-9a-f')
if [[ ${#hex} -ne 16 ]]; then
return 1
fi
printf '%s:%s:%s:%s:%s:%s:%s:%s\n' \
"${hex:0:2}" "${hex:2:2}" "${hex:4:2}" "${hex:6:2}" \
"${hex:8:2}" "${hex:10:2}" "${hex:12:2}" "${hex:14:2}"
}

# ========================= INPUT VALIDATION HELPERS ===================
validate_cisco_port_token() {
local port_value="$1"
[[ "$port_value" =~ ^fc[0-9]+/[0-9]+$ ]]
}

add_expected_port() {
local port_value="$1"
if ! validate_cisco_port_token "$port_value"; then
log "ERROR: Invalid Cisco interface '${port_value}' — expected format like fc1/23"
exit 1
fi
EXPECTED_PORT_MAP["$port_value"]=1
}

# ========================= INTERFACE BRIEF PARSERS ====================
parse_interface_brief_line() {
local line="$1"
local trimmed_line=""
local intf=""
local vsan=""
local status=""
local tail=""

trimmed_line=$(trim "$line")
[[ -z "$trimmed_line" ]] && return 1
[[ "$trimmed_line" =~ ^[-=]+$ ]] && return 1
[[ "$trimmed_line" =~ ^(Interface|Port|Mode|Status|IP[[:space:]]+Address) ]] && return 1

if [[ "$trimmed_line" =~ ^(fc[0-9]+/[0-9]+)[[:space:]]+([0-9-]+)[[:space:]]+(.*)$ ]]; then
intf="${BASH_REMATCH[1]}"
vsan="${BASH_REMATCH[2]}"
tail="${BASH_REMATCH[3]}"
else
return 1
fi

case "$tail" in
*" admin down "*|*" admin-down "*) status="admin down" ;;
*" sfpAbsent "*) status="sfpAbsent" ;;
*" noOperMembers "*) status="noOperMembers" ;;
*" trunking "*) status="trunking" ;;
*" up "*) status="up" ;;
*" down "*) status="down" ;;
*) status="unknown" ;;
esac

printf '%s|%s|%s\n' "$intf" "$vsan" "$status"
return 0
}

parse_interface_brief_output() {
local input="$1"
local parsed=""
while IFS= read -r line; do
parsed=$(parse_interface_brief_line "$line") || continue
printf '%s\n' "$parsed"
done <<< "$input"
}

get_interface_brief_state_for_port() {
local target_port="$1"
local input="$2"
local parsed=""
local local_intf=""
local local_vsan=""
local local_status=""

while IFS= read -r line; do
parsed=$(parse_interface_brief_line "$line") || continue
IFS='|' read -r local_intf local_vsan local_status <<< "$parsed"
if [[ "$local_intf" == "$target_port" ]]; then
printf '%s\n' "$local_status"
return 0
fi
done <<< "$input"

return 1
}

# ========================= SFP PARSERS ================================
extract_cisco_power_dbm() {
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

parse_cisco_sfp_output() {
local input="$1"
local rx_dbm=""
local tx_dbm=""
local parse_status=""

rx_dbm=$(extract_cisco_power_dbm "Rx" "$input" || true)
tx_dbm=$(extract_cisco_power_dbm "Tx" "$input" || true)

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

# ========================= ERROR COUNTER PARSERS ======================
parse_cisco_error_counter_line() {
local line="$1"
local trimmed_line=""
local intf=""
local remainder=""
local -a raw_tokens=()
local numeric_values=""
local value=""

trimmed_line=$(trim "$line")
[[ -z "$trimmed_line" ]] && return 1
[[ "$trimmed_line" =~ ^[-=]+$ ]] && return 1
[[ "$trimmed_line" =~ ^(Interface|ifInErrors|ifOutErrors|CRC|Symbol|Port) ]] && return 1

if [[ "$trimmed_line" =~ ^(fc[0-9]+/[0-9]+)[[:space:]]+(.*)$ ]]; then
intf="${BASH_REMATCH[1]}"
remainder="${BASH_REMATCH[2]}"
else
return 1
fi

read -r -a raw_tokens <<< "$remainder"
[[ ${#raw_tokens[@]} -eq 0 ]] && return 1

for value in "${raw_tokens[@]}"; do
if [[ "$value" =~ ^[0-9]+$ ]]; then
numeric_values+="${numeric_values:+ }$value"
fi
done

[[ -z "$numeric_values" ]] && return 1
printf '%s|%s\n' "$intf" "$numeric_values"
return 0
}

get_cisco_error_values_for_port() {
local target_port="$1"
local input="$2"
local parsed=""
local local_intf=""
local local_values=""

while IFS= read -r line; do
parsed=$(parse_cisco_error_counter_line "$line") || continue
IFS='|' read -r local_intf local_values <<< "$parsed"
if [[ "$local_intf" == "$target_port" ]]; then
printf '%s\n' "$local_values"
return 0
fi
done <<< "$input"

return 1
}

cisco_error_values_have_nonzero_errors() {
local values="$1"
local val=""
for val in $values; do
if [[ "$val" =~ ^[0-9]+$ && "$val" -gt 0 ]]; then
return 0
fi
done
return 1
}

# ========================= WWN DATABASE PARSERS =======================
parse_flogi_fcns_match() {
local wwn="$1"
local flogi_input="$2"
local fcns_input="$3"
local canonical_wwn=""
local raw_line=""
local norm_line=""
local port_found=""

canonical_wwn=$(normalize_wwn "$wwn" || true)
[[ -z "$canonical_wwn" ]] && {
printf 'NOT_FOUND|||\n'
return 0
}

while IFS= read -r raw_line; do
raw_line=$(printf '%s' "$raw_line" | tr -d '\r')
norm_line=$(normalize_wwn "$raw_line" 2>/dev/null || true)
if [[ "$raw_line" == *"$canonical_wwn"* || "$norm_line" == "$canonical_wwn" ]]; then
if [[ "$raw_line" =~ (fc[0-9]+/[0-9]+) ]]; then
port_found="${BASH_REMATCH[1]}"
fi
printf 'FOUND|%s|FLOGI (local)\n' "${port_found:-?}"
return 0
fi
done <<< "$flogi_input"

while IFS= read -r raw_line; do
raw_line=$(printf '%s' "$raw_line" | tr -d '\r')
norm_line=$(normalize_wwn "$raw_line" 2>/dev/null || true)
if [[ "$raw_line" == *"$canonical_wwn"* || "$norm_line" == "$canonical_wwn" ]]; then
printf 'FOUND|remote|FCNS (remote)\n'
return 0
fi
done <<< "$fcns_input"

printf 'NOT_FOUND|||\n'
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
elif [[ "$line" =~ ^[0-9a-fA-F:]+$ ]]; then
if [[ -z "$current_alias" ]]; then
log "ERROR: WWN '${line}' found without preceding alias in ${alias_file}"
exit 1
fi
normalized_wwn=$(normalize_wwn "$line" || true)
if [[ -z "$normalized_wwn" ]]; then
log "ERROR: Invalid WWN '${line}' found in ${alias_file}"
exit 1
fi
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
while IFS='|' read -r local_intf local_vsan local_status; do
[[ -z "$local_intf" ]] && continue
if [[ "$local_status" == "up" || "$local_status" == "trunking" ]]; then
UP_PORT_MAP["${local_intf}"]=1
PORT_VSAN_MAP["${local_intf}"]="${local_vsan}"
fi
done < <(parse_interface_brief_output "$INTF_BRIEF_OUTPUT")

log " Up ports detected: ${!UP_PORT_MAP[*]}"
log " Total up: ${#UP_PORT_MAP[@]}"
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
for port_intf in "${!UP_PORT_MAP[@]}"; do
EXPECTED_PORT_MAP["$port_intf"]=1
done
log " Expected ports (auto-detected): ${!EXPECTED_PORT_MAP[*]}"
fi

EXPECTED_TOTAL=${#EXPECTED_PORT_MAP[@]}
log " Total expected ports: ${EXPECTED_TOTAL}"

for port_intf in "${!EXPECTED_PORT_MAP[@]}"; do
if [[ "$DRY_RUN" == false && -z "${UP_PORT_MAP[$port_intf]+_}" ]]; then
if ! get_interface_brief_state_for_port "$port_intf" "$INTF_BRIEF_OUTPUT" >/dev/null 2>&1; then
log " !!! Requested interface ${port_intf} does not appear in show interface brief output"
fi
fi
done
log ""

# ======================================================================
# STEP 3: VALIDATE EXPECTED PORTS ARE UP
# ======================================================================
log "============ STEP 3: VALIDATE EXPECTED PORTS ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log_raw " +------------+----------------------+------+"
log_raw " | Interface | Status | VSAN |"
log_raw " +------------+----------------------+------+"

SORTED_EXPECTED=($(echo "${!EXPECTED_PORT_MAP[@]}" | tr ' ' '\n' | sort -t'/' -k1,1 -k2,2n))

for port_intf in "${SORTED_EXPECTED[@]}"; do
port_display=$(printf "%-10s" "$port_intf")

if [[ -n "${UP_PORT_MAP[$port_intf]+_}" ]]; then
vsan_val="${PORT_VSAN_MAP[$port_intf]:-?}"
vsan_display=$(printf "%-4s" "$vsan_val")
log_raw " | ${port_display} | UP/TRUNKING | ${vsan_display} |"
PORTS_UP=$((PORTS_UP + 1))
else
actual_state="NOT UP"
parsed_state=$(get_interface_brief_state_for_port "$port_intf" "$INTF_BRIEF_OUTPUT" || true)

case "$parsed_state" in
sfpAbsent)
actual_state="NO SFP"
PORTS_NO_SFP=$((PORTS_NO_SFP + 1))
;;
down|admin\ down)
actual_state="DOWN"
PORTS_DOWN=$((PORTS_DOWN + 1))
;;
noOperMembers)
actual_state="NO OPER"
PORTS_OTHER=$((PORTS_OTHER + 1))
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

log_raw " | ${port_display} | *** ${actual_state} *** | --- | EXPECTED UP"
EXPECTED_MISSING=$((EXPECTED_MISSING + 1))
fi

TOTAL_PORTS_CHECKED=$((TOTAL_PORTS_CHECKED + 1))
done

log_raw " +------------+----------------------+------+"
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
log_raw " +------------+-------------+-------------+--------+--------------------------+"
log_raw " | Interface | RX Pwr(dBm) | TX Pwr(dBm) | Status | Detail |"
log_raw " +------------+-------------+-------------+--------+--------------------------+"

for port_intf in "${SFP_PORTS[@]}"; do
sfp_output=$(run_cmd "show interface ${port_intf} transceiver details" "SFP diagnostics for ${port_intf}" 2>/dev/null) || {
log " !!! Failed to get transceiver details for ${port_intf}"
SFP_UNKNOWN=$((SFP_UNKNOWN + 1))
continue
}

IFS='|' read -r sfp_parse_status rx_dbm tx_dbm <<< "$(parse_cisco_sfp_output "$sfp_output")"

port_display=$(printf "%-10s" "$port_intf")
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
detail_display=$(printf "%-24s" "$detail")
log_raw " | ${port_display} | ${rx_display} | ${tx_display} | ${status_display} | ${detail_display} |"

echo "--- transceiver ${port_intf} ---" >> "$LOG_FILE"
echo "$sfp_output" >> "$LOG_FILE"
echo "--- end transceiver ${port_intf} ---" >> "$LOG_FILE"

sleep 1
done

log_raw " +------------+-------------+-------------+--------+--------------------------+"
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
err_values=$(get_cisco_error_values_for_port "$port_intf" "$PORTERR_OUTPUT" || true)
if [[ -n "$err_values" ]]; then
if cisco_error_values_have_nonzero_errors "$err_values"; then
log " !!! Port ${port_intf}: Non-zero error counters detected"
log " ${port_intf}: ${err_values}"
PORTS_WITH_ERRORS=$((PORTS_WITH_ERRORS + 1))
fi
else
log " !!! Port ${port_intf}: Parser could not classify any error-counter row"
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

load_alias_file "$ALIAS_FILE"
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

IFS='|' read -r match_status found_intf found_source <<< "$(parse_flogi_fcns_match "$wwn" "$FLOGI_OUTPUT" "$FCNS_OUTPUT")"

intf_display=$(printf "%-10s" "${found_intf:----}")
source_display=$(printf "%-14s" "${found_source:----}")

if [[ "$match_status" == "FOUND" ]]; then
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