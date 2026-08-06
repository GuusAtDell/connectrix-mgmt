# Input File Formats — Detailed Reference

This document describes the exact format for each input file used by the Connectrix zoning automation scripts. All formats apply to both Brocade and Cisco (where applicable).

---

## General Rules (All Files)

| Rule | Description |
|---|---|
| **Comments** | Lines starting with `#` are ignored |
| **Empty lines** | Blank lines are ignored and can be used for readability |
| **Whitespace** | Leading and trailing whitespace on each line is trimmed automatically |
| **Encoding** | Files must be plain text (UTF-8 or ASCII). Avoid Unicode characters in alias/zone names |
| **Line endings** | Both LF (Linux/macOS) and CRLF (Windows) are supported |
| **Case sensitivity** | Alias names, zone names, and WWNs are **case-sensitive** on Brocade FOS. Use consistent casing |

---

## Alias File

**Default filename:** `aliases.txt`
**Override:** `--alias-file <path>`

### Format

Each alias is defined as exactly **two lines**:

1. A name line starting with `alias:` followed by the alias name
2. A WWN line containing exactly 8 colon-separated hex byte pairs

```
alias: <alias_name>
<XX:XX:XX:XX:XX:XX:XX:XX>
```

### Rules

| Rule | Detail |
|---|---|
| **Alias name** | Must follow Brocade naming rules: alphanumeric, underscores, hyphens. Max 64 characters |
| **WWN format** | Must be exactly `XX:XX:XX:XX:XX:XX:XX:XX` where `XX` is a two-digit hex value (0-9, a-f, A-F) |
| **One WWN per alias** | Each alias entry maps to exactly one WWN. For multi-WWN aliases, create separate entries or modify the script to use `aliadd` |
| **No duplicate names** | Each alias name must be unique within the file. The switch will reject duplicates |
| **Order** | Aliases are created in file order. Order does not affect functionality |

### Example

```
# ==================================================
# Initiator Aliases — Physical Linux Servers
# ==================================================
alias: ctlnp1_pdbsa_hba2
10:00:00:10:9b:33:b3:a7

alias: ctlnp1_pdbsb_hba2
10:00:00:10:9b:33:b3:d4

alias: ctlnp1_pdbsc_hba2
10:00:00:10:9b:33:b2:ea

# ==================================================
# Initiator Aliases — ESXi Hosts
# ==================================================
alias: ctlnm_pesx001_hba2
20:02:58:8a:5a:c0:52:36

alias: ctlnm_pesx002_hba2
20:02:58:8a:5a:c0:52:43

# ==================================================
# Target Aliases — Storage Array u001
# ==================================================
alias: ctlnp1_u001_spa_fc5
50:06:01:63:47:e0:4d:ed

alias: ctlnp1_u001_spb_fc5
50:06:01:6b:47:e0:4d:ed

# ==================================================
# Target Aliases — Storage Array u003
# ==================================================
alias: ctlnp1_u003_spa_fc1
50:06:01:65:4c:e0:23:ac

alias: ctlnp1_u003_spa_fc3
50:06:01:67:4c:e0:23:ac

alias: ctlnp1_u003_spb_fc1
50:06:01:6d:4c:e0:23:ac

alias: ctlnp1_u003_spb_fc3
50:06:01:6f:4c:e0:23:ac
```

### Common Errors

| Error | Cause | Fix |
|---|---|---|
| `WWN found without preceding alias:` | A WWN line appears before any `alias:` line | Add the missing `alias:` line above the WWN |
| `Alias has no corresponding WWN` | An `alias:` line is not followed by a WWN line | Add the WWN on the next line, or remove the stale `alias:` line |
| `Unrecognized line` | A line doesn't match `alias:` prefix or WWN regex | Check for typos, extra spaces in the WWN, or missing colons |

---

## Zone File

**Default filename:** `zones.txt`
**Override:** `--zone-file <path>`

### Format

Each zone starts with a `zone:` line, followed by one or more lines of **semicolon-separated** alias member names:

```
zone: <zone_name>
<member1>; <member2>; <member3>
```

Members can span **multiple lines**. The parser collects all lines between one `zone:` line and the next `zone:` line (or end of file) as belonging to that zone.

### Rules

| Rule | Detail |
|---|---|
| **Zone name** | Must follow Brocade naming rules: alphanumeric, underscores, hyphens. Max 64 characters |
| **Members** | Semicolon-separated alias names. Each member must exist in the alias file |
| **Multi-line** | Members can span multiple lines. Trailing semicolons on continuation lines are fine |
| **Minimum members** | Each zone must have at least 1 member (typically 2+: initiator + target) |
| **Whitespace around semicolons** | Optional. `a;b` and `a; b` and `a ; b` are all equivalent |
| **Trailing semicolons** | Allowed. `member1; member2;` is valid (trailing semicolon is stripped) |
| **Order** | Zones are created in file order. Order does not affect functionality |

### Example: Simple Zone (Single Line)

```
zone: Z_ctlnp1_pdbsa_hba2_ctlnp1_u001
ctlnp1_pdbsa_hba2; ctlnp1_u001_spa_fc5; ctlnp1_u001_spb_fc5
```

This creates a zone with 3 members: one initiator and two storage target ports.

### Example: Multi-Line Zone

```
zone: Z_ctlnm_pesx001_hba2_ctlnp1_u003
ctlnm_pesx001_hba2; ctlnp1_u003_spa_fc1; ctlnp1_u003_spa_fc3;
ctlnp1_u003_spb_fc1; ctlnp1_u003_spb_fc3
```

This creates a zone with 5 members: one initiator and four storage target ports. Note the trailing semicolon on the first member line — this is handled correctly.

### Common Errors

| Error | Cause | Fix |
|---|---|---|
| `VALIDATION ERROR: references alias which was NOT defined` | A zone member name doesn't match any alias in the alias file | Check spelling, ensure the alias exists in `aliases.txt` |
| `Zone has no members` | A `zone:` line with no member lines following it | Add members or remove the empty zone definition |

---

## Config File

**Default filename:** `config.txt`
**Override:** `--cfg-file <path>`

### Format

The config starts with a `cfg:` line (Brocade) or `zoneset:` line (Cisco, planned), followed by one or more lines of **semicolon-separated** zone names:

```
cfg: <config_name>
<zone1>;
<zone2>;
<zone3>
```

### Rules

| Rule | Detail |
|---|---|
| **Config name** | Must follow Brocade naming rules. Max 64 characters |
| **One config per file** | Only one `cfg:` line is allowed per file. The script aborts if multiple are found |
| **Members** | Semicolon-separated zone names. Each zone must exist in the zone file |
| **Multi-line** | Zone names can span multiple lines, same as zone members |
| **Trailing semicolons** | Allowed on continuation lines |
| **Order** | Zone members are added in file order |

### Example

```
cfg: BaseConfig_201805311240
Z_ctlnp1_pdbsa_hba2_ctlnp1_u001;
Z_ctlnp1_pdbsb_hba2_ctlnp1_u001;
Z_ctlnp1_pdbsc_hba2_ctlnp1_u001;
Z_ctlnm_pesx001_hba2_ctlnp1_u001;
Z_ctlnm_pesx002_hba2_ctlnp1_u001;
Z_ctlnm_pesx003_hba2_ctlnp1_u001;
Z_ctlnm_pesx001_hba2_ctlnp1_u003;
Z_ctlnm_pesx002_hba2_ctlnp1_u003;
Z_ctlnm_pesx003_hba2_ctlnp1_u003
```

### Common Errors

| Error | Cause | Fix |
|---|---|---|
| `VALIDATION ERROR: references zone which was NOT defined` | A zone name in the config doesn't match any zone in the zone file | Check spelling, ensure the zone exists in `zones.txt` |
| `No cfg: line found` | The file doesn't contain a `cfg:` line | Add `cfg: <name>` as the first non-comment line |
| `Multiple configs found` | More than one `cfg:` line exists | Keep only one config per file |

---

## Naming Conventions (Recommended)

While not enforced by the scripts, the following naming conventions are recommended for consistency:

### Aliases

```
<site>_<hostname>_<hba_port>       (initiators)
<site>_<array>_<sp>_<fc_port>      (targets)
```

Examples:
- `ctlnp1_pdbsa_hba2` — Physical server pdbsa, HBA port 2, site ctlnp1
- `ctlnp1_u001_spa_fc5` — Storage array u001, SP A, FC port 5

### Zones

```
Z_<initiator_alias>_<storage_alias_prefix>
```

Examples:
- `Z_ctlnp1_pdbsa_hba2_ctlnp1_u001` — Server pdbsa to storage u001
- `Z_ctlnm_pesx001_hba2_ctlnp1_u003` — ESXi host pesx001 to storage u003

### Configs

```
<descriptive_name>_<YYYYMMDDHHMI>
```

Examples:
- `BaseConfig_201805311240` — Base config created May 31, 2018 at 12:40

---

## Generating Input Files from Existing Switch Config

If you need to recreate input files from an existing switch, use these commands:

### Brocade

```bash
# Collect all data needed
ssh admin@<switch_ip> "cfgshow; echo '==='; configshow -pattern 'Zoning'"
```

From the `configshow` output under the `[Zoning]` section:
- Lines starting with `alias.` give you alias names and WWNs
- Lines starting with `zone.` give you zone names and members
- Lines starting with `cfg.` give you config names and zone members
- The `enable:` line tells you which config is currently active

A parser script to automate this conversion is on the roadmap. See [Contributing](../CONTRIBUTING.md).
