#!/bin/bash
##############################################################################
# Cisco MDS Configuration Script — Dynamic / File-Driven
#
# Supported layers:
# - base_config.txt : global chassis settings
# - vsan_config.txt : VSAN creation and naming
# - port_config.txt : interface admin/mode/trunk/access config
# - aliases.txt : device-alias definitions
# - zones.txt : zone definitions
# - config.txt : zoneset definition
#
# Key behavior:
# - Each layer can run independently
# - Zoning runs ONLY if explicitly requested with zoning files
# - Comments are supported when first non-space char is '#' or ';'
# - CLI --vsan overrides embedded VSAN values in zoning files
# - hostname is global only, never VSAN-scoped
# - disable_all_ports: yes is an explicit reset action
# - --debug enables detailed phase and parser logging
# - --dry-run shows intent in a human-readable way
# - --generate-script <file> emits runnable switch CLI to screen and tees it to <file>
##############################################################################

set -euo pipefail

# ========================= DEFAULTS ===================================
SWITCH_NAME="someswitch"
SWITCH_IP="192.168.0.1"
SWITCH_USER="admin"
SSH_KEY=""
KNOWN_HOSTS_FILE=""
INSECURE_HOSTKEY=false
DEBUG=false
VSAN="1"
VSAN_CLI_SET=false
ALIAS_FILE=""
ZONE_FILE=""
CFG_FILE=""
BASE_CONFIG_FILE=""
VSAN_CONFIG_FILE=""
PORT_CONFIG_FILE=""
DRY_RUN=false
GENERATE_SCRIPT=false
GENERATE_SCRIPT_FILE=""
LOG_FILE="zoning_$(date +%Y%m%d_%H%M%S).log"

RUN_BASE=false
RUN_VSAN=false
RUN_PORT=false
RUN_ZONING=false

# ========================= LOGGING ====================================
log() {
local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
echo "$msg" | tee -a "$LOG_FILE"
}

emit_script_line() {
# raw runnable output, no timestamps or prefixes
printf '%s\n' "$1" | tee -a "$GENERATE_SCRIPT_FILE"
}

debug() {
[[ "$DEBUG" == true ]] || return 0
log "DEBUG: $1"
}

# ========================= PARSE ARGUMENTS ============================
debug_arg_dump() {
[[ "$DEBUG" == true ]] || return 0
log "DEBUG: SWITCH_NAME=$SWITCH_NAME"
log "DEBUG: SWITCH_IP=$SWITCH_IP"
log "DEBUG: SWITCH_USER=$SWITCH_USER"
log "DEBUG: DRY_RUN=$DRY_RUN"
log "DEBUG: GENERATE_SCRIPT=$GENERATE_SCRIPT"
log "DEBUG: GENERATE_SCRIPT_FILE=${GENERATE_SCRIPT_FILE:- (none)}"
log "DEBUG: DEBUG=$DEBUG"
log "DEBUG: VSAN=$VSAN"
log "DEBUG: VSAN_CLI_SET=$VSAN_CLI_SET"
log "DEBUG: RUN_BASE=$RUN_BASE RUN_VSAN=$RUN_VSAN RUN_PORT=$RUN_PORT RUN_ZONING=$RUN_ZONING"
log "DEBUG: BASE_CONFIG_FILE=${BASE_CONFIG_FILE:- (none)}"
log "DEBUG: VSAN_CONFIG_FILE=${VSAN_CONFIG_FILE:- (none)}"
log "DEBUG: PORT_CONFIG_FILE=${PORT_CONFIG_FILE:- (none)}"
log "DEBUG: ALIAS_FILE=${ALIAS_FILE:- (none)}"
log "DEBUG: ZONE_FILE=${ZONE_FILE:- (none)}"
log "DEBUG: CFG_FILE=${CFG_FILE:- (none)}"
}

while [[ $# -gt 0 ]]; do
case "$1" in
--dry-run) DRY_RUN=true; shift ;;
--generate-script)
GENERATE_SCRIPT=true
[[ $# -ge 2 ]] || { echo "ERROR: --generate-script requires an output filename" >&2; exit 1; }
GENERATE_SCRIPT_FILE="$2"
shift 2 ;;
--debug) DEBUG=true; shift ;;
--switch-name) SWITCH_NAME="$2"; shift 2 ;;
--switch-ip) SWITCH_IP="$2"; shift 2 ;;
--switch-user) SWITCH_USER="$2"; shift 2 ;;
--ssh-key) SSH_KEY="$2"; shift 2 ;;
--known-hosts-file) KNOWN_HOSTS_FILE="$2"; shift 2 ;;
--insecure-hostkey) INSECURE_HOSTKEY=true; shift ;;
--vsan) VSAN="$2"; VSAN_CLI_SET=true; shift 2 ;;
--alias-file) ALIAS_FILE="$2"; RUN_ZONING=true; shift 2 ;;
--zone-file) ZONE_FILE="$2"; RUN_ZONING=true; shift 2 ;;
--cfg-file) CFG_FILE="$2"; RUN_ZONING=true; shift 2 ;;
--base-config-file) BASE_CONFIG_FILE="$2"; RUN_BASE=true; shift 2 ;;
--vsan-config-file) VSAN_CONFIG_FILE="$2"; RUN_VSAN=true; shift 2 ;;
--port-config-file) PORT_CONFIG_FILE="$2"; RUN_PORT=true; shift 2 ;;
--log-file) LOG_FILE="$2"; shift 2 ;;
-h|--help)
printf '%s\n' \
  "Usage: $0 [options]" \
  "  --dry-run" \
  "  --generate-script <file>" \
  "  --debug" \
  "  --switch-name <name>" \
  "  --switch-ip <ip>" \
  "  --switch-user <user>" \
  "  --ssh-key <file>" \
  "  --known-hosts-file <file>" \
  "  --insecure-hostkey" \
  "  --vsan <id>" \
  "  --alias-file <file>" \
  "  --zone-file <file>" \
  "  --cfg-file <file>" \
  "  --base-config-file <file>" \
  "  --vsan-config-file <file>" \
  "  --port-config-file <file>" \
  "  --log-file <file>"exit 0 ;;
*)
log "ERROR: Unknown argument: $1"
exit 1 ;;
esac
done

if [[ "$DRY_RUN" == true && "$GENERATE_SCRIPT" == true ]]; then
log "ERROR: --dry-run and --generate-script are mutually exclusive"
exit 1
fi

if [[ "$GENERATE_SCRIPT" == true && -z "$GENERATE_SCRIPT_FILE" ]]; then
log "ERROR: --generate-script requires an output filename"
exit 1
fi

# ========================= SSH ========================================
build_ssh_cmd() {
local -a cmd=(ssh)
cmd+=("-o" "BatchMode=yes")
cmd+=("-o" "ConnectTimeout=10")

if [[ "$INSECURE_HOSTKEY" == true ]]; then
cmd+=("-o" "StrictHostKeyChecking=no")
cmd+=("-o" "UserKnownHostsFile=/dev/null")
elif [[ -n "$KNOWN_HOSTS_FILE" ]]; then
cmd+=("-o" "UserKnownHostsFile=$KNOWN_HOSTS_FILE")
fi

[[ -n "$SSH_KEY" ]] && cmd+=("-i" "$SSH_KEY")
cmd+=("${SWITCH_USER}@${SWITCH_IP}")
printf '%s\n' "${cmd[@]}"
}

run_cmd() {
local cmd="$1"
local description="${2:-}"
[[ -n "$description" && "$GENERATE_SCRIPT" == false ]] && log "# $description"
debug "run_cmd invoked with: $cmd"

if [[ "$GENERATE_SCRIPT" == true ]]; then
emit_script_line "$cmd"
return 0
fi

log ">>> $cmd"

if [[ "$DRY_RUN" == false ]]; then
local output
local -a ssh_cmd
mapfile -t ssh_cmd < <(build_ssh_cmd)
output=$("${ssh_cmd[@]}" "terminal length 0 ; ${cmd}" 2>&1) || {
log "!!! COMMAND FAILED: $cmd"
log "!!! Output: $output"
exit 1
}
[[ -n "$output" ]] && log "$output"
sleep 1
else
debug "dry-run mode: command not executed"
fi
log ""
}

run_cmd_capture() {
local cmd="$1"
debug "run_cmd_capture invoked with: $cmd"
local -a ssh_cmd
mapfile -t ssh_cmd < <(build_ssh_cmd)
"${ssh_cmd[@]}" "terminal length 0 ; ${cmd}" 2>/dev/null || true
}

run_config_block() {
local cmds="$1"
local description="${2:-}"
[[ -n "$description" && "$GENERATE_SCRIPT" == false ]] && log "# $description"
debug "run_config_block start"

if [[ "$GENERATE_SCRIPT" == true ]]; then
emit_script_line "configure terminal"
while IFS= read -r line; do
[[ -z "$line" ]] && continue
emit_script_line "$line"
done <<< "$cmds"
emit_script_line "end"
return 0
fi

if [[ "$DRY_RUN" == true ]]; then
log "DRY-RUN: would enter configuration mode"
while IFS= read -r line; do
[[ -z "$line" ]] && continue
log "DRY-RUN: $line"
done <<< "$cmds"
debug "dry-run mode: config block not executed"
log ""
return 0
fi

while IFS= read -r line; do
[[ -z "$line" ]] && continue
log ">>> (config) $line"
done <<< "$cmds"

local output payload
local -a ssh_cmd
mapfile -t ssh_cmd < <(build_ssh_cmd)
payload=$'configure terminal\n'"${cmds}"$'\nend\n'
output=$(printf '%s' "$payload" | "${ssh_cmd[@]}" 2>&1) || {
log "!!! CONFIG BLOCK FAILED"
log "!!! Output: $output"
exit 1
}
[[ -n "$output" ]] && log "$output"
sleep 1
log ""
}

run_cmd_confirm() {
local cmd="$1"
local description="${2:-}"
[[ -n "$description" && "$GENERATE_SCRIPT" == false ]] && log "# $description"
debug "run_cmd_confirm invoked with: $cmd"

if [[ "$GENERATE_SCRIPT" == true ]]; then
emit_script_line "$cmd"
return 0
fi

log ">>> $cmd (with auto-confirm)"

if [[ "$DRY_RUN" == false ]]; then
local output
local -a ssh_cmd
mapfile -t ssh_cmd < <(build_ssh_cmd)
output=$(printf 'y\n' | "${ssh_cmd[@]}" "terminal length 0 ; ${cmd}" 2>&1) || {
log "!!! COMMAND FAILED: $cmd"
log "!!! Output: $output"
exit 1
}
[[ -n "$output" ]] && log "$output"
sleep 2
else
debug "dry-run mode: confirm command not executed"
fi
log ""
}

# ========================= UTILITY ====================================
trim() {
local var="$1"
var="${var#"${var%%[![:space:]]*}"}"
var="${var%"${var##*[![:space:]]}"}"
echo "$var"
}

lower() {
echo "$1" | tr '[:upper:]' '[:lower:]'
}

upper() {
echo "$1" | tr '[:lower:]' '[:upper:]'
}

is_comment_or_blank() {
local line="$1"
[[ -z "$line" ]] && return 0
[[ "$line" =~ ^[[:space:]]*([#;]) ]] && return 0
return 1
}

is_valid_name() {
local name="$1"
[[ "$name" =~ ^[A-Za-z0-9_.:-]+$ ]]
}

normalize_wwn() {
local wwn="$1"
echo "${wwn,,}"
}

normalize_member_list() {
local raw="$1"
echo "$raw" | tr '\n' ' ' | sed 's/[[:space:]]*;[[:space:]]*/;/g' | sed 's/^[;[:space:]]*//;s/[;[:space:]]*$//'
}

is_valid_ipv4() {
local ip="$1"
[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
local IFS='.'
read -r o1 o2 o3 o4 <<< "$ip"
for octet in "$o1" "$o2" "$o3" "$o4"; do
(( octet >= 0 && octet <= 255 )) || return 1
done
}

is_valid_fc_interface() {
local iface="$1"
[[ "$iface" =~ ^fc[0-9]+/[0-9]+$ ]]
}

extract_embedded_vsan() {
local file="$1"
local found=""
debug "extract_embedded_vsan reading ${file}"
while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
is_comment_or_blank "$line" && continue
if [[ "$line" =~ ^VSAN:[[:space:]]*([0-9]+)$ ]]; then
local this_vsan="${BASH_REMATCH[1]}"
debug "found embedded VSAN ${this_vsan} in ${file}"
if [[ -z "$found" ]]; then
found="$this_vsan"
elif [[ "$found" != "$this_vsan" ]]; then
log "ERROR: Conflicting VSAN lines inside ${file}: ${found} vs ${this_vsan}"
exit 1
fi
fi
done < "$file"
echo "$found"
}

resolve_vsan() {
local alias_vsan zone_vsan cfg_vsan discovered_vsan
debug "resolve_vsan start"
alias_vsan=$(extract_embedded_vsan "$ALIAS_FILE")
zone_vsan=$(extract_embedded_vsan "$ZONE_FILE")
cfg_vsan=$(extract_embedded_vsan "$CFG_FILE")

discovered_vsan=""
for candidate in "$alias_vsan" "$zone_vsan" "$cfg_vsan"; do
[[ -z "$candidate" ]] && continue
if [[ -z "$discovered_vsan" ]]; then
discovered_vsan="$candidate"
elif [[ "$discovered_vsan" != "$candidate" ]]; then
log "ERROR: Conflicting embedded VSAN values across input files: ${discovered_vsan} vs ${candidate}"
exit 1
fi
done

if [[ "$VSAN_CLI_SET" == true ]]; then
[[ -n "$discovered_vsan" && "$discovered_vsan" != "$VSAN" ]] && log "INFO: CLI --vsan ${VSAN} overrides embedded VSAN ${discovered_vsan}"
else
[[ -n "$discovered_vsan" ]] && VSAN="$discovered_vsan"
fi
debug "resolve_vsan end with VSAN=${VSAN}"
}

# ========================= BASE CONFIG ================================
BASE_HOSTNAME=""
BASE_DOMAIN_ID=""
declare -a BASE_DNS_SERVERS=()
declare -a BASE_NTP_SERVERS=()

parse_base_config() {
[[ "$RUN_BASE" == false ]] && return 0
debug "parse_base_config start"
local line key value
local -A seen_singletons=()

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
is_comment_or_blank "$line" && continue
[[ "$line" == *:* ]] || { log "ERROR: Invalid line in ${BASE_CONFIG_FILE}: ${line}"; exit 1; }

key=$(lower "$(trim "${line%%:*}")")
value=$(trim "${line#*:}")
debug "base key=${key} value=${value}"

case "$key" in
hostname)
[[ -z "${seen_singletons[hostname]+x}" ]] || { log "ERROR: Duplicate hostname in ${BASE_CONFIG_FILE}"; exit 1; }
is_valid_name "$value" || { log "ERROR: Invalid hostname '${value}'"; exit 1; }
BASE_HOSTNAME="$value"
seen_singletons[hostname]=1 ;;
domain_id)
[[ -z "${seen_singletons[domain_id]+x}" ]] || { log "ERROR: Duplicate domain_id in ${BASE_CONFIG_FILE}"; exit 1; }
[[ "$value" =~ ^[0-9]+$ ]] || { log "ERROR: domain_id must be numeric: ${value}"; exit 1; }
BASE_DOMAIN_ID="$value"
seen_singletons[domain_id]=1 ;;
dns)
is_valid_ipv4 "$value" || { log "ERROR: Invalid DNS IP '${value}'"; exit 1; }
BASE_DNS_SERVERS+=("$value") ;;
ntp)
is_valid_ipv4 "$value" || { log "ERROR: Invalid NTP IP '${value}'"; exit 1; }
BASE_NTP_SERVERS+=("$value") ;;
*)
log "ERROR: Unsupported base config key '${key}' in ${BASE_CONFIG_FILE}"
exit 1 ;;
esac
done < "$BASE_CONFIG_FILE"
debug "parse_base_config end"
}

build_base_config_block() {
local block=""
[[ "$RUN_BASE" == false ]] && { echo "$block"; return 0; }
debug "build_base_config_block start"

[[ -n "$BASE_HOSTNAME" ]] && block+="hostname ${BASE_HOSTNAME}"$'\n'
[[ -n "$BASE_DOMAIN_ID" ]] && block+="fcdomain domain ${BASE_DOMAIN_ID}"$'\n'

local dns ntp
for dns in "${BASE_DNS_SERVERS[@]}"; do
block+="ip name-server ${dns}"$'\n'
done
for ntp in "${BASE_NTP_SERVERS[@]}"; do
block+="ntp server ${ntp}"$'\n'
done
debug "build_base_config_block end"
printf '%s' "$block"
}

# ========================= VSAN CONFIG ================================
VSAN_CFG_ID=""
VSAN_CFG_NAME=""

parse_vsan_config() {
[[ "$RUN_VSAN" == false ]] && return 0
debug "parse_vsan_config start"
local line key value

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
is_comment_or_blank "$line" && continue
[[ "$line" == *:* ]] || { log "ERROR: Invalid line in ${VSAN_CONFIG_FILE}: ${line}"; exit 1; }

key=$(lower "$(trim "${line%%:*}")")
value=$(trim "${line#*:}")
debug "vsan key=${key} value=${value}"

case "$key" in
vsan)
[[ "$value" =~ ^[0-9]+$ ]] || { log "ERROR: vsan must be numeric in ${VSAN_CONFIG_FILE}: ${value}"; exit 1; }
VSAN_CFG_ID="$value" ;;
vsan_name)
is_valid_name "$value" || { log "ERROR: Invalid vsan_name '${value}'"; exit 1; }
VSAN_CFG_NAME="$value" ;;
*)
log "ERROR: Unsupported VSAN config key '${key}' in ${VSAN_CONFIG_FILE}"
exit 1 ;;
esac
done < "$VSAN_CONFIG_FILE"

if [[ -n "$VSAN_CFG_ID" ]]; then
if [[ "$VSAN_CLI_SET" == true && "$VSAN_CFG_ID" != "$VSAN" ]]; then
log "INFO: CLI --vsan ${VSAN} overrides vsan ${VSAN_CFG_ID} from ${VSAN_CONFIG_FILE}"
elif [[ "$VSAN_CLI_SET" == false ]]; then
VSAN="$VSAN_CFG_ID"
fi
fi
debug "parse_vsan_config end"
}

build_vsan_config_block() {
local block=""
[[ "$RUN_VSAN" == false ]] && { echo "$block"; return 0; }
debug "build_vsan_config_block start"

block+="vsan database"$'\n'
block+=" vsan ${VSAN}"$'\n'
[[ -n "$VSAN_CFG_NAME" ]] && block+=" vsan ${VSAN} name ${VSAN_CFG_NAME}"$'\n'
block+="exit"
debug "build_vsan_config_block end"
printf '%s' "$block"
}

# ========================= PORT CONFIG ================================
PORT_DISABLE_ALL=false
declare -a PORT_CONFIG_BLOCKS=()

discover_fc_interfaces() {
local discovered=()

if [[ "$GENERATE_SCRIPT" == true ]]; then
printf '%s\n' ""
return 0
fi

if [[ "$DRY_RUN" == true ]]; then
printf '%s\n' ""
return 0
fi

local output
output=$(run_cmd_capture "show interface brief | include ^fc")
while IFS= read -r line; do
local iface
iface=$(awk '{print $1}' <<< "$line")
[[ -z "$iface" ]] && continue
if is_valid_fc_interface "$iface"; then
discovered+=("$iface")
fi
done <<< "$output"

printf '%s\n' "${discovered[@]}"
}

parse_port_config() {
[[ "$RUN_PORT" == false ]] && return 0
debug "parse_port_config start"

local line key value
local current_interface=""
local current_admin_state=""
local current_mode=""
local current_trunk=""
local current_access_vsan=""
local current_allowed_vsans=""

flush_port_block() {
[[ -z "$current_interface" ]] && return 0
debug "flush_port_block interface=${current_interface} mode=${current_mode} admin=${current_admin_state}"

current_admin_state=$(upper "$current_admin_state")
current_mode=$(upper "$current_mode")
current_trunk=$(upper "$current_trunk")

is_valid_fc_interface "$current_interface" || { log "ERROR: Invalid interface '${current_interface}'"; exit 1; }
[[ "$current_admin_state" == "UP" || "$current_admin_state" == "DOWN" ]] || { log "ERROR: admin_state must be up or down for ${current_interface}"; exit 1; }
[[ "$current_mode" == "F" || "$current_mode" == "E" ]] || { log "ERROR: mode must be f or e for ${current_interface}"; exit 1; }

local block=""
block+="interface ${current_interface}"$'\n'

if [[ "$current_mode" == "F" ]]; then
[[ "$current_access_vsan" =~ ^[0-9]+$ ]] || { log "ERROR: access_vsan must be numeric for ${current_interface}"; exit 1; }
block+=" switchport mode F"$'\n'
block+=" switchport access vsan ${current_access_vsan}"$'\n'
else
[[ "$current_trunk" == "ON" || "$current_trunk" == "OFF" ]] || { log "ERROR: trunk must be on or off for ${current_interface}"; exit 1; }
block+=" switchport mode E"$'\n'
if [[ "$current_trunk" == "ON" ]]; then
[[ "$current_allowed_vsans" =~ ^[0-9]+(,[0-9]+)*$ ]] || { log "ERROR: invalid allowed_vsans for ${current_interface}"; exit 1; }
block+=" switchport trunk mode on"$'\n'
block+=" switchport trunk allowed vsan ${current_allowed_vsans}"$'\n'
else
block+=" switchport trunk mode off"$'\n'
fi
fi

if [[ "$current_admin_state" == "UP" ]]; then
block+=" no shutdown"$'\n'
else
block+=" shutdown"$'\n'
fi

block+="exit"
PORT_CONFIG_BLOCKS+=("$block")

current_interface=""
current_admin_state=""
current_mode=""
current_trunk=""
current_access_vsan=""
current_allowed_vsans=""
}

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
is_comment_or_blank "$line" && continue
[[ "$line" == *:* ]] || { log "ERROR: Invalid line in ${PORT_CONFIG_FILE}: ${line}"; exit 1; }

key=$(lower "$(trim "${line%%:*}")")
value=$(trim "${line#*:}")
debug "port key=${key} value=${value}"

case "$key" in
disable_all_ports)
value=$(lower "$value")
[[ "$value" == "yes" || "$value" == "no" ]] || { log "ERROR: disable_all_ports must be yes or no"; exit 1; }
[[ "$value" == "yes" ]] && PORT_DISABLE_ALL=true ;;
interface)
flush_port_block
current_interface="$value" ;;
admin_state) current_admin_state="$value" ;;
mode) current_mode="$value" ;;
trunk) current_trunk="$value" ;;
access_vsan) current_access_vsan="$value" ;;
allowed_vsans) current_allowed_vsans="$value" ;;
*)
log "ERROR: Unsupported port config key '${key}' in ${PORT_CONFIG_FILE}"
exit 1 ;;
esac
done < "$PORT_CONFIG_FILE"

flush_port_block
debug "parse_port_config end: PORT_DISABLE_ALL=$PORT_DISABLE_ALL blocks=${#PORT_CONFIG_BLOCKS[@]}"
}

build_disable_all_ports_block() {
local block=""
debug "build_disable_all_ports_block start"

if [[ "$GENERATE_SCRIPT" == true ]]; then
block+="! example only: live discovery is not available in generate-script mode"$'\n'
block+="! show interface brief | include ^fc"$'\n'
block+="interface fcX/Y"$'\n'
block+=" shutdown"$'\n'
block+="exit"$'\n'
printf '%s' "$block"
return 0
fi

if [[ "$DRY_RUN" == true ]]; then
block+="DRY-RUN: would discover ports using: show interface brief | include ^fc"$'\n'
block+="DRY-RUN: if ports are found, the script would emit interface/shutdown/exit for each"$'\n'
printf '%s' "$block"
return 0
fi

local discovered_ifaces=()
mapfile -t discovered_ifaces < <(discover_fc_interfaces)
local iface
for iface in "${discovered_ifaces[@]}"; do
[[ -z "$iface" ]] && continue
block+="interface ${iface}"$'\n'
block+=" shutdown"$'\n'
block+="exit"$'\n'
done

debug "build_disable_all_ports_block end"
printf '%s' "$block"
}

build_port_config_block() {
local combined=""
debug "build_port_config_block start"
if [[ "$PORT_DISABLE_ALL" == true ]]; then
combined+="$(build_disable_all_ports_block)"
[[ -n "$combined" ]] && combined+=$'\n'
fi

local entry
for entry in "${PORT_CONFIG_BLOCKS[@]}"; do
combined+="$entry"$'\n'
done
debug "build_port_config_block end"
printf '%s' "$combined"
}

# ========================= PRE-FLIGHT =================================
if [[ "$GENERATE_SCRIPT" == true ]]; then
: > "$GENERATE_SCRIPT_FILE" || { echo "ERROR: Cannot write to $GENERATE_SCRIPT_FILE" >&2; exit 1; }
fi

if [[ "$GENERATE_SCRIPT" == false ]]; then
log "======================================================================"
if [[ "$DRY_RUN" == true ]]; then
log " *** DRY RUN MODE — No commands will be sent ***"
else
log " *** LIVE MODE — Commands WILL be sent to the switch ***"
fi
log "======================================================================"
log " Switch : ${SWITCH_NAME} (IP: ${SWITCH_IP}; user: ${SWITCH_USER})"
log " Base File : ${BASE_CONFIG_FILE:- (none)}"
log " VSAN File : ${VSAN_CONFIG_FILE:- (none)}"
log " Port File : ${PORT_CONFIG_FILE:- (none)}"
log " Alias File: ${ALIAS_FILE:- (none)}"
log " Zone File : ${ZONE_FILE:- (none)}"
log " Cfg File : ${CFG_FILE:- (none)}"
log " Log File : ${LOG_FILE}"
log "======================================================================"
log ""

debug_arg_dump
fi

debug "starting file validation"
if [[ "$RUN_BASE" == true && ! -f "$BASE_CONFIG_FILE" ]]; then
log "ERROR: Base config file not found: $BASE_CONFIG_FILE"
exit 1
fi
if [[ "$RUN_VSAN" == true && ! -f "$VSAN_CONFIG_FILE" ]]; then
log "ERROR: VSAN config file not found: $VSAN_CONFIG_FILE"
exit 1
fi
if [[ "$RUN_PORT" == true && ! -f "$PORT_CONFIG_FILE" ]]; then
log "ERROR: Port config file not found: $PORT_CONFIG_FILE"
exit 1
fi
if [[ "$RUN_ZONING" == true ]]; then
[[ -f "$ALIAS_FILE" ]] || { log "ERROR: Alias file not found: $ALIAS_FILE"; exit 1; }
[[ -f "$ZONE_FILE" ]] || { log "ERROR: Zone file not found: $ZONE_FILE"; exit 1; }
[[ -f "$CFG_FILE" ]] || { log "ERROR: Config file not found: $CFG_FILE"; exit 1; }
fi

if [[ "$GENERATE_SCRIPT" == false ]]; then
debug "checking binaries and optional files"
if ! command -v ssh >/dev/null 2>&1; then
log "ERROR: ssh is not installed or not in PATH."
exit 1
fi

if [[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]]; then
log "ERROR: SSH key file not found: ${SSH_KEY}"
exit 1
fi
if [[ -n "$KNOWN_HOSTS_FILE" && ! -f "$KNOWN_HOSTS_FILE" ]]; then
log "ERROR: Known hosts file not found: ${KNOWN_HOSTS_FILE}"
exit 1
fi
fi

if [[ "$RUN_ZONING" == true ]]; then
resolve_vsan
fi
parse_base_config
parse_vsan_config
parse_port_config

[[ "$VSAN" =~ ^[0-9]+$ ]] || { log "ERROR: VSAN must be numeric: ${VSAN}"; exit 1; }
(( VSAN >= 1 && VSAN <= 4093 )) || { log "ERROR: VSAN out of range (1-4093): ${VSAN}"; exit 1; }

if [[ "$GENERATE_SCRIPT" == false ]]; then
log " Final VSAN : ${VSAN}"
debug "preflight complete"
log ""
fi

# ========================= EXECUTION ==================================
if [[ "$RUN_BASE" == true ]]; then
debug "entering RUN_BASE block"
BASE_CONFIG_BLOCK=$(build_base_config_block)
[[ -n "$BASE_CONFIG_BLOCK" ]] && run_config_block "$BASE_CONFIG_BLOCK" "Apply global base configuration"
fi

if [[ "$RUN_VSAN" == true ]]; then
debug "entering RUN_VSAN block"
VSAN_CONFIG_BLOCK=$(build_vsan_config_block)
[[ -n "$VSAN_CONFIG_BLOCK" ]] && run_config_block "$VSAN_CONFIG_BLOCK" "Apply VSAN configuration"
fi

if [[ "$RUN_PORT" == true ]]; then
debug "entering RUN_PORT block"
debug "PORT_DISABLE_ALL=$PORT_DISABLE_ALL"
debug "PORT_CONFIG_BLOCKS=${#PORT_CONFIG_BLOCKS[@]}"
if [[ "$PORT_DISABLE_ALL" == true && "$DRY_RUN" == false && "$GENERATE_SCRIPT" == false ]]; then
log "WARNING: disable_all_ports: yes is enabled; blanket shutdown will run before per-port config"
fi
PORT_CONFIG_BLOCK=$(build_port_config_block)
[[ -n "$PORT_CONFIG_BLOCK" ]] && run_config_block "$PORT_CONFIG_BLOCK" "Apply interface-level fabric configuration"
fi

if [[ "$RUN_ZONING" == true ]]; then
debug "entering RUN_ZONING block"
declare -A CREATED_ALIASES
declare -A CREATED_ALIAS_WWNS
ALIAS_NAME=""
ALIAS_COUNT=0
DEVALIAS_CONFIG="device-alias database"

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
is_comment_or_blank "$line" && continue
[[ "$line" =~ ^VSAN:[[:space:]]*[0-9]+$ ]] && continue

if [[ "$line" =~ ^alias:[[:space:]]*(.+)$ ]]; then
[[ -n "$ALIAS_NAME" ]] && { log "ERROR: Alias '${ALIAS_NAME}' missing WWN"; exit 1; }
ALIAS_NAME=$(trim "${BASH_REMATCH[1]}")
is_valid_name "$ALIAS_NAME" || { log "ERROR: Invalid alias '${ALIAS_NAME}'"; exit 1; }
elif [[ "$line" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){7}$ ]]; then
[[ -z "$ALIAS_NAME" ]] && { log "ERROR: WWN without preceding alias"; exit 1; }
line=$(normalize_wwn "$line")
DEVALIAS_CONFIG+=$'\n'" device-alias name ${ALIAS_NAME} pwwn ${line}"
CREATED_ALIASES["${ALIAS_NAME}"]=1
CREATED_ALIAS_WWNS["${line}"]=1
ALIAS_COUNT=$((ALIAS_COUNT + 1))
ALIAS_NAME=""
else
log "ERROR: Unrecognized line in ${ALIAS_FILE}: ${line}"
exit 1
fi
done < "$ALIAS_FILE"

[[ -n "$ALIAS_NAME" ]] && { log "ERROR: Alias '${ALIAS_NAME}' missing WWN"; exit 1; }
DEVALIAS_CONFIG+=$'\n''exit'$'\n''device-alias commit'
run_config_block "$DEVALIAS_CONFIG" "Create ${ALIAS_COUNT} device-aliases and commit"

declare -A CREATED_ZONES
ZONE_NAME=""
ZONE_MEMBERS_RAW=""
ZONE_COUNT=0
VALIDATION_ERRORS=0
ZONE_CONFIG=""

process_zone() {
local z_name="$1"
local z_members_raw="$2"
local normalized
normalized=$(normalize_member_list "$z_members_raw")

is_valid_name "$z_name" || { log "VALIDATION ERROR: Invalid zone '${z_name}'"; VALIDATION_ERRORS=$((VALIDATION_ERRORS+1)); return; }
[[ -n "${CREATED_ZONES[$z_name]+_}" ]] && { log "VALIDATION ERROR: Duplicate zone '${z_name}'"; VALIDATION_ERRORS=$((VALIDATION_ERRORS+1)); return; }

local IFS=';'
local members_array=()
local member
for member in $normalized; do
member=$(trim "$member")
[[ -z "$member" ]] && continue
[[ -z "${CREATED_ALIASES[$member]+_}" ]] && { log "VALIDATION ERROR: Zone '${z_name}' references undefined alias '${member}'"; VALIDATION_ERRORS=$((VALIDATION_ERRORS+1)); return; }
members_array+=("$member")
done

[[ ${#members_array[@]} -eq 0 ]] && { log "VALIDATION ERROR: Zone '${z_name}' has no members"; VALIDATION_ERRORS=$((VALIDATION_ERRORS+1)); return; }

ZONE_CONFIG+="zone name ${z_name} vsan ${VSAN}"$'\n'
for m in "${members_array[@]}"; do
ZONE_CONFIG+=" member device-alias ${m}"$'\n'
done
ZONE_CONFIG+="exit"$'\n'
CREATED_ZONES["${z_name}"]=1
ZONE_COUNT=$((ZONE_COUNT + 1))
}

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
is_comment_or_blank "$line" && continue
[[ "$line" =~ ^VSAN:[[:space:]]*[0-9]+$ ]] && continue

if [[ "$line" =~ ^zone:[[:space:]]*(.+)$ ]]; then
[[ -n "$ZONE_NAME" ]] && process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"
ZONE_NAME=$(trim "${BASH_REMATCH[1]}")
ZONE_MEMBERS_RAW=""
else
ZONE_MEMBERS_RAW+=" ${line}"
fi
done < "$ZONE_FILE"
[[ -n "$ZONE_NAME" ]] && process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"

[[ $VALIDATION_ERRORS -gt 0 ]] && { log "ABORTING: ${VALIDATION_ERRORS} zone validation error(s) found"; exit 1; }
run_config_block "$ZONE_CONFIG" "Create ${ZONE_COUNT} zones in VSAN ${VSAN}"

CFG_NAME=""
CFG_MEMBERS_RAW=""
CFG_COUNT=0
ZONESET_CONFIG=""
declare -A SEEN_CFG_ZONES

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
is_comment_or_blank "$line" && continue
[[ "$line" =~ ^VSAN:[[:space:]]*[0-9]+$ ]] && continue

if [[ "$line" =~ ^cfg:[[:space:]]*(.+)$ ]]; then
[[ -n "$CFG_NAME" ]] && { log "ERROR: Multiple cfg definitions in ${CFG_FILE}"; exit 1; }
CFG_NAME=$(trim "${BASH_REMATCH[1]}")
elif [[ -n "$line" ]]; then
CFG_MEMBERS_RAW+=" ${line}"
fi
done < "$CFG_FILE"

[[ -z "$CFG_NAME" ]] && { log "ERROR: No cfg line found in ${CFG_FILE}"; exit 1; }
CFG_MEMBERS_NORMALIZED=$(normalize_member_list "$CFG_MEMBERS_RAW")
IFS=';' read -ra CFG_ZONE_ARRAY <<< "$CFG_MEMBERS_NORMALIZED"
ZONESET_CONFIG="zoneset name ${CFG_NAME} vsan ${VSAN}"$'\n'

for zone_ref in "${CFG_ZONE_ARRAY[@]}"; do
zone_ref=$(trim "$zone_ref")
[[ -z "$zone_ref" ]] && continue
[[ -z "${CREATED_ZONES[$zone_ref]+_}" ]] && { log "ERROR: Zoneset references undefined zone '${zone_ref}'"; exit 1; }
[[ -n "${SEEN_CFG_ZONES[$zone_ref]+_}" ]] && continue
SEEN_CFG_ZONES["$zone_ref"]=1
ZONESET_CONFIG+=" member ${zone_ref}"$'\n'
CFG_COUNT=$((CFG_COUNT + 1))
done
ZONESET_CONFIG+="exit"

run_config_block "$ZONESET_CONFIG" "Create zoneset: ${CFG_NAME} (${CFG_COUNT} zone members) in VSAN ${VSAN}"
run_cmd "zone commit vsan ${VSAN}" "Commit zone database for VSAN ${VSAN}"
run_config_block "zoneset activate name ${CFG_NAME} vsan ${VSAN}" "Activate zoneset: ${CFG_NAME} in VSAN ${VSAN}"
run_cmd_confirm "copy running-config startup-config" "Save running config to startup"
run_cmd "show zoneset active vsan ${VSAN}" "Show active zoneset"
run_cmd "show device-alias database" "Show all device-aliases"
run_cmd "show zone vsan ${VSAN}" "Show zone definitions"
run_cmd "show zone status vsan ${VSAN}" "Show zone status"
fi

if [[ "$GENERATE_SCRIPT" == false ]]; then
debug "script completed"
log "Script completed successfully"
fi
