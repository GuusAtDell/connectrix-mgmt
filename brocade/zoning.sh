#!/bin/bash
##############################################################################
# Brocade Zoning Configuration Script — Fully Dynamic / File-Driven
#
# All aliases, zones, and the zone configuration are read from external
# input files. Nothing is hardcoded.
#
# INPUT FILES (configurable via variables or command-line arguments):
# aliases.txt — Alias definitions (alias name + WWN pairs)
# zones.txt — Zone definitions (zone name + alias members)
# config.txt — Config definition (config name + zone members)
#
# FILE FORMATS:
# - Please refer to the docs/FILE_FORMATS.md documentation
#
# PREREQUISITES:
# - For Windows: use WSL, Git Bash, or Cygwin
#
# USAGE:
# chmod +x zone_brocade.sh
# ./zone_brocade.sh --dry-run
# ./zone_brocade.sh
# ./zone_brocade.sh \
# --switch-name myswitch \
# --switch-ip 192.168.0.1 \
# --switch-user admin \
# --ssh-key ~/.ssh/id_ed25519 \
# --known-hosts-file ./known_hosts \
# --alias-file site2_aliases.txt \
# --zone-file site2_zones.txt \
# --cfg-file site2_config.txt \
# --log-file site2_log.txt \
# --dry-run
#
# LAB OVERRIDE:
# ./zone_brocade.sh --switch-ip 192.168.0.1 --insecure-hostkey --dry-run
#
# VALIDATION:
# - Before creating zones, verifies ALL member aliases were defined
# - Before creating config, verifies ALL member zones were defined
# - Aborts with clear error messages on any validation failure
##############################################################################

set -euo pipefail

# ========================= DEFAULTS ===================================
SWITCH_NAME="someswitch"
SWITCH_IP="192.168.0.1"
SWITCH_USER="admin"
SSH_KEY=""
KNOWN_HOSTS_FILE=""
INSECURE_HOSTKEY=false
ALIAS_FILE="aliases.txt"
ZONE_FILE="zones.txt"
CFG_FILE="config.txt"
DRY_RUN=false
LOG_FILE="zoning_$(date +%Y%m%d_%H%M%S).log"

# ========================= PARSE ARGUMENTS ============================
while [[ $# -gt 0 ]]; do
case "$1" in
--dry-run) DRY_RUN=true; shift ;;
--switch-name) SWITCH_NAME="$2"; shift 2 ;;
--switch-ip) SWITCH_IP="$2"; shift 2 ;;
--switch-user) SWITCH_USER="$2"; shift 2 ;;
--ssh-key) SSH_KEY="$2"; shift 2 ;;
--known-hosts-file) KNOWN_HOSTS_FILE="$2"; shift 2 ;;
--insecure-hostkey) INSECURE_HOSTKEY=true; shift ;;
--alias-file) ALIAS_FILE="$2"; shift 2 ;;
--zone-file) ZONE_FILE="$2"; shift 2 ;;
--cfg-file) CFG_FILE="$2"; shift 2 ;;
--log-file) LOG_FILE="$2"; shift 2 ;;
-h|--help)
echo "Usage: $0 [OPTIONS]"
echo ""
echo "Options:"
echo " --dry-run Print commands without executing"
echo " --switch-name NAME Switch Name (default: ${SWITCH_NAME})"
echo " --switch-ip IP Switch IP address (default: ${SWITCH_IP})"
echo " --switch-user USER SSH username (default: ${SWITCH_USER})"
echo " --ssh-key FILE SSH private key file"
echo " --known-hosts-file FILE Use a dedicated known_hosts file"
echo " --insecure-hostkey Disable host key verification (lab use only)"
echo " --alias-file FILE Alias input file (default: ${ALIAS_FILE})"
echo " --zone-file FILE Zone input file (default: ${ZONE_FILE})"
echo " --cfg-file FILE Config input file (default: ${CFG_FILE})"
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

# ========================= LOGGING ====================================
log() {
local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
echo "$msg" | tee -a "$LOG_FILE"
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
log "!!! Aborting script."
exit 1
}
if [[ -n "$output" ]]; then
log "$output"
fi
sleep 1
fi
log ""
}

run_cmd_confirm() {
local cmd="$1"
local description="${2:-}"

if [[ -n "$description" ]]; then
log "# $description"
fi
log ">>> $cmd (with auto-confirm 'y')"

if [[ "$DRY_RUN" == false ]]; then
local output
mapfile -t ssh_cmd < <(build_ssh_cmd)
output=$(printf 'y\n' | "${ssh_cmd[@]}" "$cmd" 2>&1) || {
log "!!! COMMAND FAILED: $cmd"
log "!!! Output: $output"
log "!!! Aborting script."
exit 1
}
if [[ -n "$output" ]]; then
log "$output"
fi
sleep 2
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

validate_brocade_object_name() {
local value="$1"
[[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]]
}

# ========================= LIST PARSERS ===============================
parse_semicolon_members() {
local raw="$1"
local normalized=""
local token=""
local -a parsed=()

normalized=$(echo "$raw" | tr '\n' ' ' | sed 's/[[:space:]]*;[[:space:]]*/;/g' | sed 's/^;//;s/;$//')
IFS=';' read -ra _tokens <<< "$normalized"
for token in "${_tokens[@]}"; do
token=$(trim "$token")
if [[ -z "$token" ]]; then
printf 'EMPTY_TOKEN\n'
return 1
fi
parsed+=("$token")
done
printf '%s\n' "${parsed[@]}"
return 0
}

# ========================= PRE-FLIGHT =================================
log "======================================================================"
if [[ "$DRY_RUN" == true ]]; then
log " *** DRY RUN MODE — No commands will be sent ***"
else
log " *** LIVE MODE — Commands WILL be sent to the switch ***"
fi
log "======================================================================"
log " Switch : ${SWITCH_NAME} (IP: ${SWITCH_IP}; user: ${SWITCH_USER})"
log " SSH Key : ${SSH_KEY:-default ssh agent / keychain}"
if [[ "$INSECURE_HOSTKEY" == true ]]; then
log " Host Trust : INSECURE (host key verification disabled)"
elif [[ -n "$KNOWN_HOSTS_FILE" ]]; then
log " Host Trust : strict verification using ${KNOWN_HOSTS_FILE}"
else
log " Host Trust : strict verification using default known_hosts"
fi
log " Alias File : ${ALIAS_FILE}"
log " Zone File : ${ZONE_FILE}"
log " Config File: ${CFG_FILE}"
log " Log File : ${LOG_FILE}"
log "======================================================================"
log ""

MISSING=false
for f in "$ALIAS_FILE" "$ZONE_FILE" "$CFG_FILE"; do
if [[ ! -f "$f" ]]; then
log "ERROR: Input file not found: $f"
MISSING=true
fi
done
if [[ "$MISSING" == true ]]; then
exit 1
fi

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

if [[ "$DRY_RUN" == false ]]; then
log "Testing SSH connectivity to ${SWITCH_IP}..."
run_cmd "switchstatusshow" "Pre-flight: verify connectivity and switch health"
log ""
log "Press ENTER to proceed with zoning changes, or CTRL+C to abort..."
read -r
fi

log "========== Script started =========="

# ======================================================================
# STEP 1: PARSE AND CREATE ALIASES
# ======================================================================
log "============ STEP 1: CREATE ALIASES (from ${ALIAS_FILE}) ============"

declare -A CREATED_ALIASES
declare -A WWN_TO_ALIAS

ALIAS_NAME=""
ALIAS_COUNT=0

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue

if [[ "$line" =~ ^alias:[[:space:]]*(.+)$ ]]; then
if [[ -n "$ALIAS_NAME" ]]; then
log "!!! PARSER ERROR: Alias '${ALIAS_NAME}' did not receive a WWN before the next alias header"
exit 1
fi

ALIAS_NAME=$(trim "${BASH_REMATCH[1]}")

if ! validate_brocade_object_name "$ALIAS_NAME"; then
log "!!! PARSER ERROR: Alias name '${ALIAS_NAME}' contains unsupported characters"
exit 1
fi

if [[ -n "${CREATED_ALIASES[$ALIAS_NAME]+_}" ]]; then
log "!!! PARSER ERROR: Duplicate alias name '${ALIAS_NAME}' in ${ALIAS_FILE}"
exit 1
fi

elif [[ "$line" =~ ^[0-9a-fA-F:]+$ ]]; then
if [[ -z "$ALIAS_NAME" ]]; then
log "!!! PARSER ERROR: WWN '${line}' found without preceding 'alias:' line"
exit 1
fi

normalized_wwn=$(normalize_wwn "$line" || true)
if [[ -z "$normalized_wwn" ]]; then
log "!!! PARSER ERROR: Invalid WWN '${line}' in ${ALIAS_FILE}"
exit 1
fi

if [[ -n "${WWN_TO_ALIAS[$normalized_wwn]+_}" ]]; then
log "!!! PARSER ERROR: Duplicate WWN '${normalized_wwn}' already assigned to alias '${WWN_TO_ALIAS[$normalized_wwn]}'"
exit 1
fi

run_cmd "alicreate '${ALIAS_NAME}', '${normalized_wwn}'" \
"Create alias: ${ALIAS_NAME} -> ${normalized_wwn}"

CREATED_ALIASES["${ALIAS_NAME}"]="$normalized_wwn"
WWN_TO_ALIAS["${normalized_wwn}"]="$ALIAS_NAME"
ALIAS_COUNT=$((ALIAS_COUNT + 1))
ALIAS_NAME=""
else
log "!!! PARSER ERROR: Unrecognized line in ${ALIAS_FILE}: ${line}"
exit 1
fi
done < "$ALIAS_FILE"

if [[ -n "$ALIAS_NAME" ]]; then
log "!!! PARSER ERROR: Alias '${ALIAS_NAME}' has no corresponding WWN"
exit 1
fi

log " Aliases created: ${ALIAS_COUNT}"
log ""

# ======================================================================
# STEP 2: PARSE, VALIDATE, AND CREATE ZONES
# ======================================================================
log "============ STEP 2: CREATE ZONES (from ${ZONE_FILE}) ============"

declare -A CREATED_ZONES
ZONE_NAME=""
ZONE_MEMBERS_RAW=""
ZONE_COUNT=0
VALIDATION_ERRORS=0

actionable_zone_parse_errors=0

process_zone() {
local z_name="$1"
local z_members_raw="$2"
local -a members_array=()
local -A SEEN_ZONE_MEMBERS=()
local brocade_members=""
local member=""
local zone_validation_errors=0

if ! validate_brocade_object_name "$z_name"; then
log "!!! PARSER ERROR: Zone name '${z_name}' contains unsupported characters"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
return
fi

if [[ -n "${CREATED_ZONES[$z_name]+_}" ]]; then
log "!!! PARSER ERROR: Duplicate zone name '${z_name}' in ${ZONE_FILE}"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
return
fi

mapfile -t members_array < <(parse_semicolon_members "$z_members_raw") || {
log "!!! PARSER ERROR: Zone '${z_name}' contains empty or malformed member tokens"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
return
}

if [[ ${#members_array[@]} -eq 0 ]]; then
log "!!! PARSER ERROR: Zone '${z_name}' has no members"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
return
fi

for member in "${members_array[@]}"; do
if ! validate_brocade_object_name "$member"; then
log "!!! PARSER ERROR: Zone '${z_name}' contains invalid member token '${member}'"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
return
fi

if [[ -n "${SEEN_ZONE_MEMBERS[$member]+_}" ]]; then
log "!!! PARSER ERROR: Zone '${z_name}' repeats member '${member}'"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
return
fi
SEEN_ZONE_MEMBERS["$member"]=1

if [[ -z "${CREATED_ALIASES[$member]+_}" ]]; then
log "!!! VALIDATION ERROR: Zone '${z_name}' references alias '${member}' which was NOT defined in ${ALIAS_FILE}"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
zone_validation_errors=$((zone_validation_errors + 1))
fi

if [[ -z "$brocade_members" ]]; then
brocade_members="$member"
else
brocade_members="${brocade_members};${member}"
fi
done

if [[ $zone_validation_errors -eq 0 ]]; then
run_cmd "zonecreate '${z_name}', '${brocade_members}'" \
"Create zone: ${z_name} (${#members_array[@]} members)"

CREATED_ZONES["${z_name}"]=1
ZONE_COUNT=$((ZONE_COUNT + 1))
fi
}

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" ]] && continue
[[ $line == \#* ]] && continue

if [[ $line == zone:* ]]; then
if [[ -n "$ZONE_NAME" ]]; then
process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"
fi

ZONE_NAME=$(trim "${line#zone:}")
if [[ -z "$ZONE_NAME" ]]; then
log "!!! PARSER ERROR: Empty zone name in ${ZONE_FILE}"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
ZONE_NAME=""
ZONE_MEMBERS_RAW=""
continue
fi

ZONE_MEMBERS_RAW=""
else
if [[ -z "$ZONE_NAME" ]]; then
log "!!! PARSER ERROR: Zone member line found before first 'zone:' header: ${line}"
actionable_zone_parse_errors=$((actionable_zone_parse_errors + 1))
continue
fi
ZONE_MEMBERS_RAW+=" ${line}"
fi
done < "$ZONE_FILE"

if [[ -n "$ZONE_NAME" ]]; then
process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"
fi

if [[ $actionable_zone_parse_errors -gt 0 ]]; then
log ""
log "!!! ABORTING: ${actionable_zone_parse_errors} zone parser error(s) found."
log "!!! Fix the malformed zone definitions and re-run."
exit 1
fi

if [[ $VALIDATION_ERRORS -gt 0 ]]; then
log ""
log "!!! ABORTING: ${VALIDATION_ERRORS} validation error(s) found."
log "!!! All alias members referenced in zones must be defined in ${ALIAS_FILE}."
log "!!! Fix the input files and re-run."
exit 1
fi

log " Zones created: ${ZONE_COUNT}"
log ""

# ======================================================================
# STEP 3: PARSE, VALIDATE, AND CREATE ZONE CONFIGURATION
# ======================================================================
log "============ STEP 3: CREATE ZONE CONFIG (from ${CFG_FILE}) ============"

CFG_NAME=""
CFG_MEMBERS_RAW=""
CFG_COUNT=0
VALIDATION_ERRORS=0
CFG_PARSE_ERRORS=0

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue

if [[ "$line" =~ ^cfg:[[:space:]]*(.+)$ ]]; then
if [[ -n "$CFG_NAME" ]]; then
log "!!! PARSER ERROR: Multiple configs found in ${CFG_FILE}. Only one config per file is supported."
exit 1
fi
CFG_NAME=$(trim "${BASH_REMATCH[1]}")
else
CFG_MEMBERS_RAW+=" ${line}"
fi
done < "$CFG_FILE"

if [[ -z "$CFG_NAME" ]]; then
log "!!! PARSER ERROR: No 'cfg:' line found in ${CFG_FILE}"
exit 1
fi

if ! validate_brocade_object_name "$CFG_NAME"; then
log "!!! PARSER ERROR: Config name '${CFG_NAME}' contains unsupported characters"
exit 1
fi

mapfile -t CFG_ZONE_ARRAY < <(parse_semicolon_members "$CFG_MEMBERS_RAW") || {
log "!!! PARSER ERROR: Config '${CFG_NAME}' contains empty or malformed zone tokens"
exit 1
}

if [[ ${#CFG_ZONE_ARRAY[@]} -eq 0 ]]; then
log "!!! PARSER ERROR: Config '${CFG_NAME}' has no zone members"
exit 1
fi

declare -A SEEN_CFG_ZONES=()
CFG_BROCADE_MEMBERS=""
for zone_ref in "${CFG_ZONE_ARRAY[@]}"; do
zone_ref=$(trim "$zone_ref")
[[ -z "$zone_ref" ]] && {
CFG_PARSE_ERRORS=$((CFG_PARSE_ERRORS + 1))
continue
}

if ! validate_brocade_object_name "$zone_ref"; then
log "!!! PARSER ERROR: Config '${CFG_NAME}' contains invalid zone token '${zone_ref}'"
CFG_PARSE_ERRORS=$((CFG_PARSE_ERRORS + 1))
continue
fi

if [[ -n "${SEEN_CFG_ZONES[$zone_ref]+_}" ]]; then
log "!!! PARSER ERROR: Config '${CFG_NAME}' repeats zone '${zone_ref}'"
CFG_PARSE_ERRORS=$((CFG_PARSE_ERRORS + 1))
continue
fi
SEEN_CFG_ZONES["$zone_ref"]=1

CFG_COUNT=$((CFG_COUNT + 1))

if [[ -z "${CREATED_ZONES[$zone_ref]+_}" ]]; then
log "!!! VALIDATION ERROR: Config '${CFG_NAME}' references zone '${zone_ref}' which was NOT defined in ${ZONE_FILE}"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [[ -z "$CFG_BROCADE_MEMBERS" ]]; then
CFG_BROCADE_MEMBERS="$zone_ref"
else
CFG_BROCADE_MEMBERS="${CFG_BROCADE_MEMBERS};${zone_ref}"
fi
done

if [[ $CFG_PARSE_ERRORS -gt 0 ]]; then
log ""
log "!!! ABORTING: ${CFG_PARSE_ERRORS} config parser error(s) found."
log "!!! Fix the malformed config definition and re-run."
exit 1
fi

if [[ $VALIDATION_ERRORS -gt 0 ]]; then
log ""
log "!!! ABORTING: ${VALIDATION_ERRORS} validation error(s) found."
log "!!! All zones referenced in the config must be defined in ${ZONE_FILE}."
log "!!! Fix the input files and re-run."
exit 1
fi

run_cmd "cfgcreate '${CFG_NAME}', '${CFG_BROCADE_MEMBERS}'" \
"Create zone config: ${CFG_NAME} (${CFG_COUNT} zone members)"

log " Config created: ${CFG_NAME} with ${CFG_COUNT} zones"
log ""

# ======================================================================
# STEP 4: SAVE CONFIGURATION
# ======================================================================
log "============ STEP 4: SAVE CONFIGURATION ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log "============================================================"
log " All aliases (${ALIAS_COUNT}), zones (${ZONE_COUNT}), and"
log " config '${CFG_NAME}' (${CFG_COUNT} members) have been created."
log ""
log " About to run: cfgsave"
log " Press ENTER to save, or CTRL+C to abort..."
log "============================================================"
read -r
fi

run_cmd_confirm "cfgsave" "Save zone database to flash memory"

# ======================================================================
# STEP 5: ENABLE CONFIGURATION
# ======================================================================
log "============ STEP 5: ENABLE CONFIGURATION ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
log " CRITICAL: About to activate the zone configuration!"
log " Config: ${CFG_NAME}"
log ""
log " This WILL affect traffic on the fabric."
log " Press ENTER to cfgenable, or CTRL+C to abort..."
log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
read -r
fi

run_cmd_confirm "cfgenable '${CFG_NAME}'" "Enable effective configuration: ${CFG_NAME}"

# ======================================================================
# STEP 6: VERIFY
# ======================================================================
log "============ STEP 6: POST-CHANGE VERIFICATION ============"

run_cmd "cfgactvshow" "Show active (effective) configuration"
run_cmd "alishow '*'" "Show all aliases"
run_cmd "zoneshow" "Show all zone definitions"
run_cmd "cfgshow" "Show full defined and effective config"

log ""
log "============================================================"
log " Script completed successfully."
log " Summary:"
log " Aliases : ${ALIAS_COUNT}"
log " Zones : ${ZONE_COUNT}"
log " Config : ${CFG_NAME} (${CFG_COUNT} zone members)"
log " Log file : ${LOG_FILE}"
log "============================================================"