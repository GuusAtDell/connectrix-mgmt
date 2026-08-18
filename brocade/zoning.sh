#!/bin/bash
##############################################################################
# Brocade Zoning Configuration Script — Fully Dynamic / File-Driven
#
# All aliases, zones, and the zone configuration are read from external
# input files. Nothing is hardcoded.
#
# INPUT FILES (configurable via variables or command-line arguments):
#   aliases.txt  — Alias definitions      (alias name + WWN pairs)
#   zones.txt    — Zone definitions        (zone name + alias members)
#   config.txt   — Config definition       (config name + zone members)
#
# FILE FORMATS:
#   aliases.txt:
#     alias: <alias_name>
#     <wwn>
#
#   zones.txt:
#     zone: <zone_name>
#     <member1>; <member2>; <member3>;
#     <member4>; <member5>
#       (members can span multiple lines; semicolons separate them)
#
#   config.txt:
#     cfg: <config_name>
#     <zone1>;
#     <zone2>;
#     <zone3>
#       (zone members can span multiple lines; semicolons separate them)
#
# PREREQUISITES:
#   - For Windows: use WSL, Git Bash, or Cygwin
#
# USAGE:
#   chmod +x zone_brocade.sh
#   ./zone_brocade.sh --dry-run                              # Dry run, default files
#   ./zone_brocade.sh                                        # Live run, default files
#   ./zone_brocade.sh \
#                     --switch-name myswitch \
#                     --switch-ip 192.168.0.1 \
#                     --switch-user admin \
#                     --switch-pass 'MyPassword!' \
#                     --alias-file site2_aliases.txt \
#                     --zone-file site2_zones.txt \
#                     --cfg-file site2_config.txt \
#                     --log-file site2_log.txt \
#                     --dry-run                              # Custom input files
#
# VALIDATION:
#   - Before creating zones, verifies ALL member aliases were defined
#   - Before creating config, verifies ALL member zones were defined
#   - Aborts with clear error messages on any validation failure
##############################################################################

set -euo pipefail

# ========================= DEFAULTS ===================================
SWITCH_NAME="someswitch"
SWITCH_IP="192.168.0.1"
SWITCH_USER="admin"
SWITCH_PASS='Password123!'
ALIAS_FILE="aliases.txt"
ZONE_FILE="zones.txt"
CFG_FILE="config.txt"
DRY_RUN=false
LOG_FILE="zoning_$(date +%Y%m%d_%H%M%S).log"

# ========================= PARSE ARGUMENTS ============================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=true;       shift ;;
		--switch-name)  SWITCH_NAME="$2";    shift 2 ;;
        --switch-ip)    SWITCH_IP="$2";      shift 2 ;;
        --switch-user)  SWITCH_USER="$2";    shift 2 ;;
        --switch-pass)  SWITCH_PASS="$2";    shift 2 ;;
        --alias-file)   ALIAS_FILE="$2";     shift 2 ;;
        --zone-file)    ZONE_FILE="$2";      shift 2 ;;
        --cfg-file)     CFG_FILE="$2";       shift 2 ;;
        --log-file)     LOG_FILE="$2";       shift 2 ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run              Print commands without executing"
            echo "  --switch-name  NAME    Switch Name          (default: ${SWITCH_NAME})"
            echo "  --switch-ip  IP        Switch IP address    (default: ${SWITCH_IP})"
            echo "  --switch-user USER     SSH username         (default: ${SWITCH_USER})"
            echo "  --switch-pass PASS     SSH password         (default: ********)"
            echo "  --alias-file FILE      Alias input file     (default: ${ALIAS_FILE})"
            echo "  --zone-file  FILE      Zone input file      (default: ${ZONE_FILE})"
            echo "  --cfg-file   FILE      Config input file    (default: ${CFG_FILE})"
            echo "  --log-file   FILE      Log output file      (default: auto-timestamped)"
            echo "  -h, --help             Show this help"
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
        output=$("${ssh_cmd[@]}" "$cmd" <<< "y" 2>&1) || {
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

# ========================= UTILITY: TRIM WHITESPACE ===================
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"   # Leading
    var="${var%"${var##*[![:space:]]}"}"   # Trailing
    echo "$var"
}

# ========================= PRE-FLIGHT =================================
log "======================================================================"
if [[ "$DRY_RUN" == true ]]; then
    log "  *** DRY RUN MODE — No commands will be sent ***"
else
    log "  *** LIVE MODE — Commands WILL be sent to the switch ***"
fi
log "======================================================================"
log "  Switch     : ${SWITCH_NAME} (IP: ${SWITCH_IP}; user: ${SWITCH_USER})"
log "  Alias File : ${ALIAS_FILE}"
log "  Zone File  : ${ZONE_FILE}"
log "  Config File: ${CFG_FILE}"
log "  Log File   : ${LOG_FILE}"
log "======================================================================"
log ""

# Verify all input files exist
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

# Associative array to track all created aliases (for validation in step 2)
declare -A CREATED_ALIASES

ALIAS_NAME=""
ALIAS_COUNT=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim "$line")

    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    if [[ "$line" =~ ^alias:[[:space:]]*(.+)$ ]]; then
        # Alias name line
        ALIAS_NAME=$(trim "${BASH_REMATCH[1]}")

    elif [[ "$line" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){7}$ ]]; then
        # WWN line
        if [[ -z "$ALIAS_NAME" ]]; then
            log "!!! ERROR: WWN '${line}' found without preceding 'alias:' line"
            exit 1
        fi

        run_cmd "alicreate '${ALIAS_NAME}', '${line}'" \
                "Create alias: ${ALIAS_NAME} -> ${line}"

        CREATED_ALIASES["${ALIAS_NAME}"]=1
        ALIAS_COUNT=$((ALIAS_COUNT + 1))
        ALIAS_NAME=""

    else
        log "!!! WARNING: Unrecognized line in ${ALIAS_FILE}: ${line}"
    fi
done < "$ALIAS_FILE"

if [[ -n "$ALIAS_NAME" ]]; then
    log "!!! ERROR: Alias '${ALIAS_NAME}' has no corresponding WWN"
    exit 1
fi

log "  Aliases created: ${ALIAS_COUNT}"
log ""


# ======================================================================
# STEP 2: PARSE, VALIDATE, AND CREATE ZONES
# ======================================================================
log "============ STEP 2: CREATE ZONES (from ${ZONE_FILE}) ============"

# Associative array to track all created zones (for validation in step 3)
declare -A CREATED_ZONES

# ------------------------------------------------------------------
# Parser: collects zone name + multi-line members, then processes
# each zone when the next "zone:" line (or EOF) is encountered.
# ------------------------------------------------------------------

ZONE_NAME=""
ZONE_MEMBERS_RAW=""
ZONE_COUNT=0
VALIDATION_ERRORS=0

# Function to process (validate + create) a single zone
process_zone() {
    local z_name="$1"
    local z_members_raw="$2"

    # Normalize: replace newlines with spaces, collapse whitespace,
    # remove trailing semicolons/whitespace, then split on ";"
    local normalized
    normalized=$(echo "$z_members_raw" | tr '\n' ' ' | sed 's/[[:space:]]*;[[:space:]]*/;/g' | sed 's/^;//;s/;$//')

    # Convert to semicolon-separated list (Brocade format)
    # Also validate each member alias exists
    local IFS=';'
    local members_array=()
    for member in $normalized; do
        member=$(trim "$member")
        [[ -z "$member" ]] && continue

        # Validate: does this alias exist?
        if [[ -z "${CREATED_ALIASES[$member]+_}" ]]; then
            log "!!! VALIDATION ERROR: Zone '${z_name}' references alias '${member}' which was NOT defined in ${ALIAS_FILE}"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi

        members_array+=("$member")
    done

    if [[ ${#members_array[@]} -eq 0 ]]; then
        log "!!! ERROR: Zone '${z_name}' has no members"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return
    fi

    # Build semicolon-separated member string for Brocade CLI
    local brocade_members=""
    for m in "${members_array[@]}"; do
        if [[ -z "$brocade_members" ]]; then
            brocade_members="$m"
        else
            brocade_members="${brocade_members};${m}"
        fi
    done

    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        run_cmd "zonecreate '${z_name}', '${brocade_members}'" \
                "Create zone: ${z_name} (${#members_array[@]} members)"

        CREATED_ZONES["${z_name}"]=1
        ZONE_COUNT=$((ZONE_COUNT + 1))
    fi
}

# Read the zone file
while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim "$line")

    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    if [[ "$line" =~ ^zone:[[:space:]]*(.+)$ ]]; then
        # New zone encountered — process previous zone if any
        if [[ -n "$ZONE_NAME" ]]; then
            process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"
        fi

        ZONE_NAME=$(trim "${BASH_REMATCH[1]}")
        ZONE_MEMBERS_RAW=""
    else
        # Member line (could be a continuation of multi-line members)
        ZONE_MEMBERS_RAW+=" ${line}"
    fi
done < "$ZONE_FILE"

# Process the last zone in the file
if [[ -n "$ZONE_NAME" ]]; then
    process_zone "$ZONE_NAME" "$ZONE_MEMBERS_RAW"
fi

# Abort if any validation errors occurred
if [[ $VALIDATION_ERRORS -gt 0 ]]; then
    log ""
    log "!!! ABORTING: ${VALIDATION_ERRORS} validation error(s) found."
    log "!!! All alias members referenced in zones must be defined in ${ALIAS_FILE}."
    log "!!! Fix the input files and re-run."
    exit 1
fi

log "  Zones created: ${ZONE_COUNT}"
log ""


# ======================================================================
# STEP 3: PARSE, VALIDATE, AND CREATE ZONE CONFIGURATION
# ======================================================================
log "============ STEP 3: CREATE ZONE CONFIG (from ${CFG_FILE}) ============"

CFG_NAME=""
CFG_MEMBERS_RAW=""
CFG_COUNT=0

# Read the config file
while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim "$line")

    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    if [[ "$line" =~ ^cfg:[[:space:]]*(.+)$ ]]; then
        # Config name line
        if [[ -n "$CFG_NAME" ]]; then
            log "!!! ERROR: Multiple configs found in ${CFG_FILE}. Only one config per file is supported."
            exit 1
        fi
        CFG_NAME=$(trim "${BASH_REMATCH[1]}")
    else
        # Zone member line
        CFG_MEMBERS_RAW+=" ${line}"
    fi
done < "$CFG_FILE"

if [[ -z "$CFG_NAME" ]]; then
    log "!!! ERROR: No 'cfg:' line found in ${CFG_FILE}"
    exit 1
fi

# Normalize the member string
CFG_MEMBERS_NORMALIZED=$(echo "$CFG_MEMBERS_RAW" | tr '\n' ' ' | sed 's/[[:space:]]*;[[:space:]]*/;/g' | sed 's/^;//;s/;$//')

# Validate: every zone referenced in the config must exist
VALIDATION_ERRORS=0
IFS=';' read -ra CFG_ZONE_ARRAY <<< "$CFG_MEMBERS_NORMALIZED"

for zone_ref in "${CFG_ZONE_ARRAY[@]}"; do
    zone_ref=$(trim "$zone_ref")
    [[ -z "$zone_ref" ]] && continue
    CFG_COUNT=$((CFG_COUNT + 1))

    if [[ -z "${CREATED_ZONES[$zone_ref]+_}" ]]; then
        log "!!! VALIDATION ERROR: Config '${CFG_NAME}' references zone '${zone_ref}' which was NOT defined in ${ZONE_FILE}"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
done

if [[ $VALIDATION_ERRORS -gt 0 ]]; then
    log ""
    log "!!! ABORTING: ${VALIDATION_ERRORS} validation error(s) found."
    log "!!! All zones referenced in the config must be defined in ${ZONE_FILE}."
    log "!!! Fix the input files and re-run."
    exit 1
fi

# Build the final semicolon-separated member list (clean, no trailing semicolon)
CFG_BROCADE_MEMBERS=""
for zone_ref in "${CFG_ZONE_ARRAY[@]}"; do
    zone_ref=$(trim "$zone_ref")
    [[ -z "$zone_ref" ]] && continue
    if [[ -z "$CFG_BROCADE_MEMBERS" ]]; then
        CFG_BROCADE_MEMBERS="$zone_ref"
    else
        CFG_BROCADE_MEMBERS="${CFG_BROCADE_MEMBERS};${zone_ref}"
    fi
done

run_cmd "cfgcreate '${CFG_NAME}', '${CFG_BROCADE_MEMBERS}'" \
        "Create zone config: ${CFG_NAME} (${CFG_COUNT} zone members)"

log "  Config created: ${CFG_NAME} with ${CFG_COUNT} zones"
log ""


# ======================================================================
# STEP 4: SAVE CONFIGURATION
# ======================================================================
log "============ STEP 4: SAVE CONFIGURATION ============"

if [[ "$DRY_RUN" == false ]]; then
    log ""
    log "============================================================"
    log "  All aliases (${ALIAS_COUNT}), zones (${ZONE_COUNT}), and"
    log "  config '${CFG_NAME}' (${CFG_COUNT} members) have been created."
    log ""
    log "  About to run: cfgsave"
    log "  Press ENTER to save, or CTRL+C to abort..."
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
    log "  CRITICAL: About to activate the zone configuration!"
    log "  Config: ${CFG_NAME}"
    log ""
    log "  This WILL affect traffic on the fabric."
    log "  Press ENTER to cfgenable, or CTRL+C to abort..."
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
run_cmd "zoneshow"    "Show all zone definitions"
run_cmd "cfgshow"     "Show full defined and effective config"

log ""
log "============================================================"
log "  Script completed successfully."
log "  Summary:"
log "    Aliases : ${ALIAS_COUNT}"
log "    Zones   : ${ZONE_COUNT}"
log "    Config  : ${CFG_NAME} (${CFG_COUNT} zone members)"
log "  Log file  : ${LOG_FILE}"
log "============================================================"
