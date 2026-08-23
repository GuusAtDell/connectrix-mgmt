#!/bin/bash
##############################################################################
# Cisco MDS Zoning Configuration Script — Fully Dynamic / File-Driven
#
# Cisco NX-OS equivalent of zone_brocade.sh. All device-aliases, zones,
# and the zoneset are read from external input files. Nothing is hardcoded.
#
# INPUT FILES (same format as Brocade version):
# aliases.txt — Device-alias definitions (alias name + WWN pairs)
# zones.txt — Zone definitions (zone name + alias members)
# config.txt — Zoneset definition (zoneset name + zone members)
#
# FILE FORMATS:
# - Please refer to the docs/FILE_FORMATS.md documentation
#
# AUTHENTICATION:
# - SSH key only. Password authentication is intentionally disabled.
# - Supports an optional identity file via --ssh-key.
#
# USAGE:
# chmod +x zoning.sh
# ./zoning.sh --dry-run
# ./zoning.sh
# ./zoning.sh \
# --switch-name myswitch \
# --switch-ip 192.168.0.1 \
# --switch-user admin \
# --ssh-key ~/.ssh/id_ed25519 \
# --known-hosts-file ./known_hosts \
# --vsan 100 \
# --alias-file site2_aliases.txt \
# --zone-file site2_zones.txt \
# --cfg-file site2_config.txt \
# --dry-run
#
# LAB OVERRIDE:
# ./zoning.sh --switch-ip 192.168.0.1 --insecure-hostkey --dry-run
#
# VALIDATION:
# - Before creating zones, verifies ALL member device-aliases were defined
# - Before creating zoneset, verifies ALL member zones were defined
# - Aborts with clear error messages on any validation failure
#
# NOTES:
# - This script assumes ENHANCED zoning mode is active on the switch.
# Enhanced zoning uses 'zone commit vsan' to apply changes atomically.
# - If using BASIC zoning mode, remove/skip the 'zone commit' command
# and rely on 'copy running-config startup-config' only.
# - Device-aliases are VSAN-independent (fabric-wide); zones and zonesets
# are VSAN-specific.
##############################################################################

set -euo pipefail

# ========================= DEFAULTS ===================================
SWITCH_NAME="someswitch"
SWITCH_IP="192.168.0.1"
SWITCH_USER="admin"
SSH_KEY=""
KNOWN_HOSTS_FILE=""
INSECURE_HOSTKEY=false
VSAN="1"
ALIAS_FILE="aliases.txt"
ZONE_FILE="zones.txt"
CFG_FILE="config.txt"
DRY_RUN=false
LOG_FILE="zoning_$(date +%Y%m%d_%H%M%S).log"

# ========================= PARSE ARGUMENTS ============================
while [[ $# -gt 0 ]]; do
case "$1" in
--dry-run) DRY_RUN=true; shift ;;
--switch-name)
[[ $# -ge 2 ]] || { echo "Missing value for --switch-name"; exit 1; }
SWITCH_NAME="$2"; shift 2 ;;
--switch-ip)
[[ $# -ge 2 ]] || { echo "Missing value for --switch-ip"; exit 1; }
SWITCH_IP="$2"; shift 2 ;;
--switch-user)
[[ $# -ge 2 ]] || { echo "Missing value for --switch-user"; exit 1; }
SWITCH_USER="$2"; shift 2 ;;
--ssh-key)
[[ $# -ge 2 ]] || { echo "Missing value for --ssh-key"; exit 1; }
SSH_KEY="$2"; shift 2 ;;
--known-hosts-file)
[[ $# -ge 2 ]] || { echo "Missing value for --known-hosts-file"; exit 1; }
KNOWN_HOSTS_FILE="$2"; shift 2 ;;
--insecure-hostkey) INSECURE_HOSTKEY=true; shift ;;
--vsan)
[[ $# -ge 2 ]] || { echo "Missing value for --vsan"; exit 1; }
VSAN="$2"; shift 2 ;;
--alias-file)
[[ $# -ge 2 ]] || { echo "Missing value for --alias-file"; exit 1; }
ALIAS_FILE="$2"; shift 2 ;;
--zone-file)
[[ $# -ge 2 ]] || { echo "Missing value for --zone-file"; exit 1; }
ZONE_FILE="$2"; shift 2 ;;
--cfg-file)
[[ $# -ge 2 ]] || { echo "Missing value for --cfg-file"; exit 1; }
CFG_FILE="$2"; shift 2 ;;
--log-file)
[[ $# -ge 2 ]] || { echo "Missing value for --log-file"; exit 1; }
LOG_FILE="$2"; shift 2 ;;
-h|--help)
echo "Usage: $0 [OPTIONS]"
echo ""
echo "Options:"
echo " --dry-run Print commands without executing"
echo " --switch-name NAME Switch name (default: ${SWITCH_NAME})"
echo " --switch-ip IP Switch IP address (default: ${SWITCH_IP})"
echo " --switch-user USER SSH username (default: ${SWITCH_USER})"
echo " --ssh-key FILE SSH private key file"
echo " --known-hosts-file FILE Use a dedicated known_hosts file"
echo " --insecure-hostkey Disable host key verification (lab use only)"
echo " --vsan VSAN VSAN ID for zoning (default: ${VSAN})"
echo " --alias-file FILE Alias input file (default: ${ALIAS_FILE})"
echo " --zone-file FILE Zone input file (default: ${ZONE_FILE})"
echo " --cfg-file FILE Zoneset input file (default: ${CFG_FILE})"
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

# Run a show/exec command (non-config mode)
run_cmd() {
local cmd="$1"
local description="${2:-}"

if [[ -n "$description" ]]; then
log "# $description"
fi
log ">>> $cmd"

if [[ "$DRY_RUN" == false ]]; then
local output
local -a ssh_cmd
mapfile -t ssh_cmd < <(build_ssh_cmd)
output=$("${ssh_cmd[@]}" "terminal length 0 ; ${cmd}" 2>&1) || {
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

# Run a block of configuration commands
# Takes a multi-line string; wraps in 'configure terminal' / 'end'
run_config_block() {
local cmds="$1"
local description="${2:-}"

if [[ -n "$description" ]]; then
log "# $description"
fi

while IFS= read -r line; do
[[ -z "$line" ]] && continue
log ">>> (config) $line"
done <<< "$cmds"

if [[ "$DRY_RUN" == false ]]; then
local output
local payload
local -a ssh_cmd
mapfile -t ssh_cmd < <(build_ssh_cmd)
payload=$'configure terminal\n'"${cmds}"$'\nend\n'
output=$(printf '%s' "$payload" | "${ssh_cmd[@]}" 2>&1) || {
log "!!! CONFIG BLOCK FAILED"
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
log ">>> $cmd (with auto-confirm)"

if [[ "$DRY_RUN" == false ]]; then
local output
local -a ssh_cmd
mapfile -t ssh_cmd < <(build_ssh_cmd)
output=$(printf 'y\n' | "${ssh_cmd[@]}" "terminal length 0 ; ${cmd}" 2>&1) || {
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

# ========================= UTILITY: TRIM ==============================
trim() {
local var="$1"
var="${var#"${var%%[![:space:]]*}"}"
var="${var%"${var##*[![:space:]]}"}"
echo "$var"
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
log " VSAN : ${VSAN}"
log " Alias File : ${ALIAS_FILE}"
log " Zone File : ${ZONE_FILE}"
log " Config File: ${CFG_FILE}"
log " Log File : ${LOG_FILE}"
log "======================================================================"
log ""

[[ "$VSAN" =~ ^[0-9]+$ ]] || { log "ERROR: VSAN must be numeric: ${VSAN}"; exit 1; }
(( VSAN >= 1 && VSAN <= 4093 )) || { log "ERROR: VSAN out of range (1-4093): ${VSAN}"; exit 1; }

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
run_cmd "show switchname" "Pre-flight: verify connectivity"
run_cmd "show zone status vsan ${VSAN}" "Pre-flight: verify VSAN ${VSAN} zoning status"

log ""
log "Press ENTER to proceed with zoning changes, or CTRL+C to abort..."
read -r
fi

log "========== Script started =========="

# ======================================================================
# STEP 1: PARSE AND CREATE DEVICE-ALIASES
# ======================================================================
log "============ STEP 1: CREATE DEVICE-ALIASES (from ${ALIAS_FILE}) ============"

declare -A CREATED_ALIASES
declare -A CREATED_ALIAS_WWNS
ALIAS_NAME=""
ALIAS_COUNT=0

DEVALIAS_CONFIG="device-alias database"

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue

if [[ "$line" =~ ^alias:[[:space:]]*(.+)$ ]]; then
if [[ -n "$ALIAS_NAME" ]]; then
log "!!! ERROR: Alias '${ALIAS_NAME}' has no corresponding WWN before next alias declaration"
exit 1
fi
ALIAS_NAME=$(trim "${BASH_REMATCH[1]}")

if [[ -z "$ALIAS_NAME" ]]; then
log "!!! ERROR: Empty alias name in ${ALIAS_FILE}"
exit 1
fi

if ! is_valid_name "$ALIAS_NAME"; then
log "!!! ERROR: Alias '${ALIAS_NAME}' contains invalid characters"
exit 1
fi

if [[ -n "${CREATED_ALIASES[$ALIAS_NAME]+_}" ]]; then
log "!!! ERROR: Duplicate alias '${ALIAS_NAME}' found in ${ALIAS_FILE}"
exit 1
fi

elif [[ "$line" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){7}$ ]]; then
if [[ -z "$ALIAS_NAME" ]]; then
log "!!! ERROR: WWN '${line}' found without preceding 'alias:' line"
exit 1
fi

line=$(normalize_wwn "$line")
if [[ -n "${CREATED_ALIAS_WWNS[$line]+_}" ]]; then
log "!!! ERROR: WWN '${line}' is assigned more than once in ${ALIAS_FILE}"
exit 1
fi

DEVALIAS_CONFIG+=$'\n'" device-alias name ${ALIAS_NAME} pwwn ${line}"
CREATED_ALIASES["${ALIAS_NAME}"]=1
CREATED_ALIAS_WWNS["${line}"]=1
ALIAS_COUNT=$((ALIAS_COUNT + 1))
ALIAS_NAME=""

else
log "!!! ERROR: Unrecognized line in ${ALIAS_FILE}: ${line}"
exit 1
fi
done < "$ALIAS_FILE"

if [[ -n "$ALIAS_NAME" ]]; then
log "!!! ERROR: Alias '${ALIAS_NAME}' has no corresponding WWN"
exit 1
fi

DEVALIAS_CONFIG+=$'\n'"exit"
DEVALIAS_CONFIG+=$'\n'"device-alias commit"

run_config_block "$DEVALIAS_CONFIG" \
"Create ${ALIAS_COUNT} device-aliases and commit"

log " Device-aliases created: ${ALIAS_COUNT}"
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

ZONE_CONFIG=""

process_zone() {
local z_name="$1"
local z_members_raw="$2"

local normalized
normalized=$(normalize_member_list "$z_members_raw")

if [[ -z "$z_name" ]]; then
log "!!! ERROR: Encountered empty zone name"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
return
fi

if ! is_valid_name "$z_name"; then
log "!!! VALIDATION ERROR: Zone '${z_name}' contains invalid characters"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
return
fi

if [[ -n "${CREATED_ZONES[$z_name]+_}" ]]; then
log "!!! VALIDATION ERROR: Duplicate zone '${z_name}' found in ${ZONE_FILE}"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
return
fi

local IFS=';'
local members_array=()
local -A seen_members=()
local member
local zone_has_errors=0
for member in $normalized; do
member=$(trim "$member")
[[ -z "$member" ]] && continue

if ! is_valid_name "$member"; then
log "!!! VALIDATION ERROR: Zone '${z_name}' contains invalid member '${member}'"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
zone_has_errors=1
continue
fi

if [[ -z "${CREATED_ALIASES[$member]+_}" ]]; then
log "!!! VALIDATION ERROR: Zone '${z_name}' references device-alias '${member}' which was NOT defined in ${ALIAS_FILE}"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
zone_has_errors=1
fi

if [[ -n "${seen_members[$member]+_}" ]]; then
log "!!! VALIDATION ERROR: Zone '${z_name}' contains duplicate member '${member}'"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
zone_has_errors=1
continue
fi

seen_members["$member"]=1
members_array+=("$member")
done

if [[ ${#members_array[@]} -eq 0 ]]; then
log "!!! ERROR: Zone '${z_name}' has no members"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
return
fi

if [[ $zone_has_errors -eq 0 ]]; then
ZONE_CONFIG+="zone name ${z_name} vsan ${VSAN}"$'\n'
for m in "${members_array[@]}"; do
ZONE_CONFIG+=" member device-alias ${m}"$'\n'
done
ZONE_CONFIG+="exit"$'\n'

CREATED_ZONES["${z_name}"]=1
ZONE_COUNT=$((ZONE_COUNT + 1))
fi
}

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue

if [[ "$line" =~ ^zone:[[:space:]]*(.+)$ ]]; then
if [[ -n "$ZONE_NAME" ]]; then
process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"
fi
ZONE_NAME=$(trim "${BASH_REMATCH[1]}")
ZONE_MEMBERS_RAW=""
else
ZONE_MEMBERS_RAW+=" ${line}"
fi
done < "$ZONE_FILE"

if [[ -n "$ZONE_NAME" ]]; then
process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"
fi

if [[ $VALIDATION_ERRORS -gt 0 ]]; then
log ""
log "!!! ABORTING: ${VALIDATION_ERRORS} validation error(s) found."
log "!!! All device-alias members referenced in zones must be defined in ${ALIAS_FILE}."
exit 1
fi

if [[ -n "$ZONE_CONFIG" ]]; then
run_config_block "$ZONE_CONFIG" \
"Create ${ZONE_COUNT} zones in VSAN ${VSAN}"
fi

log " Zones created: ${ZONE_COUNT}"
log ""

# ======================================================================
# STEP 3: PARSE, VALIDATE, AND CREATE ZONESET
# ======================================================================
log "============ STEP 3: CREATE ZONESET (from ${CFG_FILE}) ============"

CFG_NAME=""
CFG_MEMBERS_RAW=""
CFG_COUNT=0

while IFS= read -r line || [[ -n "$line" ]]; do
line=$(trim "$line")
[[ -z "$line" || "$line" =~ ^# ]] && continue

if [[ "$line" =~ ^cfg:[[:space:]]*(.+)$ ]]; then
if [[ -n "$CFG_NAME" ]]; then
log "!!! ERROR: Multiple configs found in ${CFG_FILE}. Only one is supported."
exit 1
fi
CFG_NAME=$(trim "${BASH_REMATCH[1]}")
else
CFG_MEMBERS_RAW+=" ${line}"
fi
done < "$CFG_FILE"

if [[ -z "$CFG_NAME" ]]; then
log "!!! ERROR: No 'cfg:' line found in ${CFG_FILE}"
exit 1
fi

if ! is_valid_name "$CFG_NAME"; then
log "!!! ERROR: Zoneset name '${CFG_NAME}' contains invalid characters"
exit 1
fi

CFG_MEMBERS_NORMALIZED=$(normalize_member_list "$CFG_MEMBERS_RAW")

VALIDATION_ERRORS=0
IFS=';' read -ra CFG_ZONE_ARRAY <<< "$CFG_MEMBERS_NORMALIZED"

ZONESET_CONFIG="zoneset name ${CFG_NAME} vsan ${VSAN}"$'\n'
declare -A SEEN_CFG_ZONES

for zone_ref in "${CFG_ZONE_ARRAY[@]}"; do
zone_ref=$(trim "$zone_ref")
[[ -z "$zone_ref" ]] && continue

if ! is_valid_name "$zone_ref"; then
log "!!! VALIDATION ERROR: Zoneset '${CFG_NAME}' contains invalid zone reference '${zone_ref}'"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
continue
fi

if [[ -n "${SEEN_CFG_ZONES[$zone_ref]+_}" ]]; then
log "!!! VALIDATION ERROR: Zoneset '${CFG_NAME}' contains duplicate zone '${zone_ref}'"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
continue
fi
SEEN_CFG_ZONES["$zone_ref"]=1
CFG_COUNT=$((CFG_COUNT + 1))

if [[ -z "${CREATED_ZONES[$zone_ref]+_}" ]]; then
log "!!! VALIDATION ERROR: Zoneset '${CFG_NAME}' references zone '${zone_ref}' which was NOT defined in ${ZONE_FILE}"
VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

ZONESET_CONFIG+=" member ${zone_ref}"$'\n'
done

ZONESET_CONFIG+="exit"

if [[ $CFG_COUNT -eq 0 ]]; then
log "!!! ERROR: Zoneset '${CFG_NAME}' has no members"
exit 1
fi

if [[ $VALIDATION_ERRORS -gt 0 ]]; then
log ""
log "!!! ABORTING: ${VALIDATION_ERRORS} validation error(s) found."
log "!!! All zones referenced in the zoneset must be defined in ${ZONE_FILE}."
exit 1
fi

run_config_block "$ZONESET_CONFIG" \
"Create zoneset: ${CFG_NAME} (${CFG_COUNT} zone members) in VSAN ${VSAN}"

log " Zoneset created: ${CFG_NAME} with ${CFG_COUNT} zones"
log ""

# ======================================================================
# STEP 4: COMMIT ZONE DATABASE
# ======================================================================
log "============ STEP 4: COMMIT ZONE DATABASE ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log "============================================================"
log " All device-aliases (${ALIAS_COUNT}), zones (${ZONE_COUNT}), and"
log " zoneset '${CFG_NAME}' (${CFG_COUNT} members) have been created."
log ""
log " About to run: zone commit vsan ${VSAN}"
log " Press ENTER to commit, or CTRL+C to abort..."
log "============================================================"
read -r
fi

run_cmd "zone commit vsan ${VSAN}" "Commit zone database for VSAN ${VSAN}"

# ======================================================================
# STEP 5: ACTIVATE ZONESET
# ======================================================================
log "============ STEP 5: ACTIVATE ZONESET ============"

if [[ "$DRY_RUN" == false ]]; then
log ""
log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
log " CRITICAL: About to activate the zoneset!"
log " Zoneset: ${CFG_NAME} | VSAN: ${VSAN}"
log ""
log " This WILL affect traffic on the fabric."
log " Press ENTER to activate, or CTRL+C to abort..."
log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
read -r
fi

run_config_block "zoneset activate name ${CFG_NAME} vsan ${VSAN}" \
"Activate zoneset: ${CFG_NAME} in VSAN ${VSAN}"

# ======================================================================
# STEP 6: SAVE CONFIGURATION
# ======================================================================
log "============ STEP 6: SAVE CONFIGURATION ============"

run_cmd_confirm "copy running-config startup-config" \
"Save running config to startup (persistent)"

# ======================================================================
# STEP 7: VERIFY
# ======================================================================
log "============ STEP 7: POST-CHANGE VERIFICATION ============"

run_cmd "show zoneset active vsan ${VSAN}" "Show active zoneset for VSAN ${VSAN}"
run_cmd "show device-alias database" "Show all device-aliases"
run_cmd "show zone vsan ${VSAN}" "Show all zone definitions for VSAN ${VSAN}"
run_cmd "show zone status vsan ${VSAN}" "Show zone status for VSAN ${VSAN}"

log ""
log "============================================================"
log " Script completed successfully."
log " Summary:"
log " Device-aliases : ${ALIAS_COUNT}"
log " Zones : ${ZONE_COUNT}"
log " Zoneset : ${CFG_NAME} (${CFG_COUNT} zone members)"
log " VSAN : ${VSAN}"
log " Log file : ${LOG_FILE}"
log "============================================================"