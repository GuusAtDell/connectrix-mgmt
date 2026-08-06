# Validation Logic — Detailed Reference

This document explains how the Connectrix zoning automation scripts validate your input files before making any changes to the switch.

---

## Overview

The script enforces a **strict three-stage dependency chain**. Every reference is validated **in memory** before any SSH commands are sent to the switch. If any validation error is found, the script aborts immediately without touching the switch.

```
+---------------+     validates      +---------------+     validates      +---------------+
|  aliases.txt  | -----------------> |   zones.txt   | -----------------> |  config.txt   |
|               |                    |               |                    |               |
|  Creates:     |  "Does every zone  |  Creates:     |  "Does every cfg   |  Creates:     |
|  CREATED_     |   member exist as  |  CREATED_     |   member exist as  |  cfgcreate    |
|  ALIASES[]    |   a known alias?"  |  ZONES[]      |   a known zone?"   |  command      |
|  (hash map)   |                    |  (hash map)   |                    |               |
|               |  NO -> ABORT       |               |  NO -> ABORT       |               |
+---------------+                    +---------------+                    +---------------+
```

---

## Stage 1: Alias File Parsing

**Input:** `aliases.txt` (or custom file via `--alias-file`)

### What happens:

1. The script reads the file line by line
2. For each `alias:` line, it captures the alias name
3. For each WWN line (regex: `^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){7}$`), it:
   - Verifies a preceding `alias:` name was captured
   - Sends `alicreate '<name>', '<wwn>'` to the switch (or prints in dry-run)
   - Stores the alias name in the `CREATED_ALIASES` associative array

### Validation checks:

| Check | Error if failed |
|---|---|
| WWN appears without preceding `alias:` line | `WWN found without preceding 'alias:' line` |
| `alias:` line has no following WWN | `Alias '<name>' has no corresponding WWN` |
| Line doesn't match `alias:` or WWN pattern | `WARNING: Unrecognized line` |
| WWN format invalid (wrong length, bad hex) | Line is treated as unrecognized |

### Result:

An in-memory hash map (`CREATED_ALIASES`) containing every alias name that was successfully created. This is used in Stage 2.

---

## Stage 2: Zone File Parsing and Validation

**Input:** `zones.txt` (or custom file via `--zone-file`)

### What happens:

1. The script reads the file, collecting each zone name and its members
2. Members can span multiple lines (collected until the next `zone:` line or EOF)
3. The member string is normalized: newlines become spaces, semicolons are used as delimiters
4. **For each member alias**: the script checks whether it exists in `CREATED_ALIASES`
5. If all members validate, the zone is created on the switch
6. The zone name is stored in the `CREATED_ZONES` associative array

### Validation checks:

| Check | Error if failed |
|---|---|
| Zone member alias not in `CREATED_ALIASES` | `VALIDATION ERROR: Zone '<zone>' references alias '<alias>' which was NOT defined in <alias_file>` |
| Zone has zero members after parsing | `Zone '<name>' has no members` |
| All errors are collected | Script reports total count and aborts: `ABORTING: N validation error(s) found` |

### Important: All errors are reported before aborting

The script does **not** stop at the first validation error. It continues parsing all zones, collecting all errors, and reports the full list. This helps you fix everything in one pass rather than fixing one error at a time.

### Example error output:

```
!!! VALIDATION ERROR: Zone 'Z_ctlnm_pesx001_hba2_ctlnp1_u001' references
    alias 'ctlnm_pesx001_hba2' which was NOT defined in aliases.txt
!!! VALIDATION ERROR: Zone 'Z_ctlnm_pesx001_hba2_ctlnp1_u003' references
    alias 'ctlnm_pesx001_hba2' which was NOT defined in aliases.txt
!!! ABORTING: 2 validation error(s) found.
!!! All alias members referenced in zones must be defined in aliases.txt.
!!! Fix the input files and re-run.
```

### Result:

An in-memory hash map (`CREATED_ZONES`) containing every zone name that was successfully created. This is used in Stage 3.

---

## Stage 3: Config File Parsing and Validation

**Input:** `config.txt` (or custom file via `--cfg-file`)

### What happens:

1. The script reads the `cfg:` line to capture the config name
2. All subsequent lines are collected as semicolon-separated zone members
3. The member string is normalized (same as zone members)
4. **For each zone reference**: the script checks whether it exists in `CREATED_ZONES`
5. If all zones validate, the config is created on the switch

### Validation checks:

| Check | Error if failed |
|---|---|
| No `cfg:` line found | `No 'cfg:' line found in <cfg_file>` |
| Multiple `cfg:` lines found | `Multiple configs found. Only one config per file is supported` |
| Zone reference not in `CREATED_ZONES` | `VALIDATION ERROR: Config '<cfg>' references zone '<zone>' which was NOT defined in <zone_file>` |

### Example error output:

```
!!! VALIDATION ERROR: Config 'BaseConfig_201805311240' references zone
    'Z_ctlnm_pesx012_hba2_ctlnp1_u001' which was NOT defined in zones.txt
!!! ABORTING: 1 validation error(s) found.
```

---

## What Is NOT Validated

The script validates the **consistency between input files** but does **not** check:

| Not Checked | Reason |
|---|---|
| Whether aliases/zones already exist on the switch | Would require querying the switch first. See idempotency roadmap item |
| Whether WWNs are actually logged into the fabric | WWN validity is a cabling/physical concern, not a zoning concern |
| Whether the config name conflicts with an existing config | `cfgcreate` will fail at runtime; the error is caught and logged |
| Brocade name length limits (64 chars) | Rarely exceeded. Could be added in a future version |
| Circular or duplicate references | Brocade FOS handles these gracefully |

---

## Validation in Dry-Run Mode

Validation works **identically** in `--dry-run` mode. The only difference is that `alicreate`, `zonecreate`, and `cfgcreate` commands are printed rather than executed. The in-memory tracking (`CREATED_ALIASES`, `CREATED_ZONES`) still operates, so validation is fully functional even without switch connectivity.

This means you can validate your input files **on any machine** — you don't need access to the switch to verify correctness:

```bash
./zone_brocade.sh --dry-run 2>&1 | grep -E '(VALIDATION|ABORT|ERROR)'
```

If no output appears, your files are valid.

---

## Quick Validation Checklist

Before running the script, verify:

- [ ] Every alias name referenced in `zones.txt` exists in `aliases.txt`
- [ ] Every zone name referenced in `config.txt` exists in `zones.txt`
- [ ] All WWNs are in correct format (`XX:XX:XX:XX:XX:XX:XX:XX`)
- [ ] No duplicate alias names in `aliases.txt`
- [ ] Exactly one `cfg:` line in `config.txt`
- [ ] Run with `--dry-run` and check for any `VALIDATION ERROR` messages
