# Connectrix SAN Management Automation

Automated, file-driven zoning scripts for **Dell Connectrix** (Brocade and Cisco) Fibre Channel switches.

These scripts allow you to define your entire SAN zoning configuration — aliases, zones, and zone configs — in simple text files, then deploy them to the switch over SSH with full validation, dry-run support, and logging.

---

## Table of Contents

- [Overview](#overview)
- [Supported Platforms](#supported-platforms)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Input File Formats](#input-file-formats)
  - [Alias File](#alias-file)
  - [Zone File](#zone-file)
  - [Config File](#config-file)
- [Usage](#usage)
  - [Brocade](#brocade)
  - [Cisco MDS](#cisco-mds)
- [Validation Logic](#validation-logic)
- [Safety Features](#safety-features)
- [Logging](#logging)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)
- [Disclaimer](#disclaimer)

---

## Overview

Manually creating aliases, zones, and zone configurations on SAN switches is tedious and error-prone — especially across large fabrics with dozens of initiators and storage targets. A single typo in a WWN or zone member can cause storage outages.

This repository provides **Bash scripts** that:

1. **Read** alias, zone, and config definitions from plain-text input files
2. **Validate** the entire dependency chain before touching the switch
3. **Execute** the commands via SSH (using `sshpass`)
4. **Log** every action to a timestamped log file

Everything is **file-driven** — nothing is hardcoded. The same script works on any switch; just prepare the input files for your environment.

---

## Supported Platforms

| Platform | Switch Family | Script | Status |
|---|---|---|---|
| **Brocade FOS** | Connectrix B-series (DS-6610B, DS-6620B, ED-DCX6-4B, etc.) | `brocade/zone_brocade.sh` | Available |
| **Cisco NX-OS / MDS** | Connectrix M-series (DS-C9148T, DS-C9396T, etc.) | `cisco/zone_cisco.sh` | Planned |

> **Note:** While these scripts were developed for Dell Connectrix switches, they should work on any standard Brocade FOS or Cisco MDS switch using the same CLI commands.

---

## Repository Structure

```
connectrix-zoning/
├── README.md
├── LICENSE
├── brocade/
│   ├── zone_brocade.sh              # Main Brocade zoning script
│   └── examples/
│       ├── aliases.txt              # Example alias definitions
│       ├── zones.txt                # Example zone definitions
│       └── config.txt               # Example zone config definition
├── cisco/
│   ├── zone_cisco.sh                # Main Cisco MDS zoning script (planned)
│   └── examples/
│       ├── aliases.txt              # Example alias definitions
│       ├── zones.txt                # Example zone definitions
│       └── config.txt               # Example zoneset definition
└── docs/
    ├── FILE_FORMATS.md              # Detailed file format reference
    ├── VALIDATION.md                # Validation logic explained
    └── TROUBLESHOOTING.md           # Common issues and solutions
```

---

## Prerequisites

### Required

- **Bash 4.0+** (for associative arrays)
  - Linux: included by default
  - macOS: `brew install bash` (macOS ships Bash 3.x)
  - Windows: use **WSL**, **Git Bash**, or **Cygwin**
- **sshpass** — for non-interactive SSH password authentication

### Installing sshpass

| OS | Command |
|---|---|
| Debian / Ubuntu | `sudo apt install sshpass` |
| RHEL / CentOS / Fedora | `sudo yum install sshpass` or `sudo dnf install sshpass` |
| macOS | `brew install hudochenkov/sshpass/sshpass` |
| Windows (WSL) | `sudo apt install sshpass` |

### Network Requirements

- SSH (TCP/22) connectivity from the machine running the script to the target switch
- Valid switch credentials (username + password)

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/<your-org>/connectrix-zoning.git
cd connectrix-zoning/brocade

# 2. Prepare your input files (see format below)
#    - aliases.txt
#    - zones.txt
#    - config.txt

# 3. Make the script executable
chmod +x zone_brocade.sh

# 4. Dry run — review all commands without executing
./zone_brocade.sh --dry-run

# 5. Live run — execute with confirmation prompts
./zone_brocade.sh
```

---

## Input File Formats

All input files use simple, human-readable text formats. Lines starting with `#` are treated as comments. Empty lines are ignored.

### Alias File

Each alias is defined as two lines: a name line prefixed with `alias:` followed by a WWN line.

**Format:**

```
alias: <alias_name>
<XX:XX:XX:XX:XX:XX:XX:XX>
```

**Example (`aliases.txt`):**

```
# Initiators — Physical Linux servers
alias: ctlnp1_pdbsa_hba2
10:00:00:10:9b:33:b3:a7

alias: ctlnp1_pdbsb_hba2
10:00:00:10:9b:33:b3:d4

# Initiators — ESXi hosts
alias: ctlnm_pesx001_hba2
20:02:58:8a:5a:c0:52:36

# Targets — Storage array u001
alias: ctlnp1_u001_spa_fc5
50:06:01:63:47:e0:4d:ed

alias: ctlnp1_u001_spb_fc5
50:06:01:6b:47:e0:4d:ed
```

### Zone File

Each zone starts with a `zone:` line, followed by one or more lines of semicolon-separated alias member names. Members can span multiple lines.

**Format:**

```
zone: <zone_name>
<member1>; <member2>; <member3>;
<member4>; <member5>
```

**Example (`zones.txt`):**

```
# Simple zone — 1 initiator, 2 storage ports
zone: Z_ctlnp1_pdbsa_hba2_ctlnp1_u001
ctlnp1_pdbsa_hba2; ctlnp1_u001_spa_fc5; ctlnp1_u001_spb_fc5

# Multi-line zone — 1 initiator, 4 storage ports
zone: Z_ctlnm_pesx001_hba2_ctlnp1_u003
ctlnm_pesx001_hba2; ctlnp1_u003_spa_fc1; ctlnp1_u003_spa_fc3;
ctlnp1_u003_spb_fc1; ctlnp1_u003_spb_fc3
```

### Config File

The config starts with a `cfg:` line (or `zoneset:` for Cisco), followed by semicolon-separated zone names. Can span multiple lines.

**Format:**

```
cfg: <config_name>
<zone1>;
<zone2>;
<zone3>
```

**Example (`config.txt`):**

```
cfg: BaseConfig_201805311240
Z_ctlnp1_pdbsa_hba2_ctlnp1_u001;
Z_ctlnp1_pdbsb_hba2_ctlnp1_u001;
Z_ctlnm_pesx001_hba2_ctlnp1_u001;
Z_ctlnm_pesx001_hba2_ctlnp1_u003
```

---

## Usage

### Brocade

```bash
# Dry run with default file names (aliases.txt, zones.txt, config.txt)
./zone_brocade.sh --dry-run

# Live run with default files
./zone_brocade.sh

# Fully parameterized
./zone_brocade.sh \
    --switch-ip 10.154.81.7 \
    --switch-user admin \
    --switch-pass 'YourPassword' \
    --alias-file my_aliases.txt \
    --zone-file my_zones.txt \
    --cfg-file my_config.txt \
    --dry-run
```

**All available options:**

| Option | Description | Default |
|---|---|---|
| `--dry-run` | Print commands without executing | `false` |
| `--switch-ip IP` | Target switch IP address | `10.154.81.7` |
| `--switch-user USER` | SSH username | `admin` |
| `--switch-pass PASS` | SSH password | *(set in script)* |
| `--alias-file FILE` | Path to alias input file | `aliases.txt` |
| `--zone-file FILE` | Path to zone input file | `zones.txt` |
| `--cfg-file FILE` | Path to config input file | `config.txt` |
| `--log-file FILE` | Path to log output file | `zoning_YYYYMMDD_HHMMSS.log` |
| `-h`, `--help` | Show help and exit | — |

### Cisco MDS

> Planned. Contributions welcome! See [Contributing](#contributing).

---

## Validation Logic

The script enforces a **strict dependency chain** before executing any commands on the switch:

```
+---------------+     validates      +---------------+     validates      +---------------+
|  aliases.txt  | -----------------> |   zones.txt   | -----------------> |  config.txt   |
|               |  "Do all zone     |               |  "Do all config   |               |
|   Aliases     |   members exist   |    Zones      |   members exist   |    Config     |
|   tracked in  |   as aliases?"    |   tracked in  |   as zones?"      |               |
|   memory      |                   |   memory      |                   |               |
|               |  If NO -> ABORT   |               |  If NO -> ABORT   |               |
+---------------+                   +---------------+                   +---------------+
```

**Example validation error:**

```
!!! VALIDATION ERROR: Zone 'Z_ctlnm_pesx001_hba2_ctlnp1_u001' references
    alias 'ctlnm_pesx001_hba2' which was NOT defined in aliases.txt
!!! ABORTING: 1 validation error(s) found.
```

The script will **never** send partially valid configurations to the switch. Either everything validates, or nothing is executed.

---

## Safety Features

| Feature | Description |
|---|---|
| **Dry-run mode** | `--dry-run` prints every command without sending anything to the switch |
| **Dependency validation** | Zones are checked against aliases; config is checked against zones — before any SSH commands |
| **Interactive confirmations** | In live mode, the script pauses and requires ENTER before `cfgsave` and `cfgenable` |
| **Automatic logging** | Every command and its output is logged to a timestamped file |
| **Fail-fast on errors** | `set -euo pipefail` and explicit error checking — the script aborts immediately on any SSH command failure |
| **Pre-flight connectivity test** | Runs `switchstatusshow` before any changes to verify SSH access and switch health |
| **Input file validation** | Checks that all input files exist before starting; validates file format during parsing |

---

## Logging

Every run generates a timestamped log file (e.g., `zoning_20260707_171026.log`) containing:

- All commands sent to the switch (prefixed with `>>>`)
- All switch output/responses
- Validation results
- Timestamps for each action
- Error messages (if any)

This provides a complete **audit trail** for every zoning change.

---

## FAQ

### Can I use this on non-Dell Brocade switches?

Yes. The script uses standard Brocade FOS CLI commands (`alicreate`, `zonecreate`, `cfgcreate`, `cfgsave`, `cfgenable`) that are the same across all Brocade-based switches.

### Does this work on Windows?

Yes, through **WSL** (Windows Subsystem for Linux), **Git Bash** (with sshpass compiled), or **Cygwin**. WSL is the recommended approach.

### What if some aliases already exist on the switch?

The script uses `alicreate` which will fail if the alias already exists. If you need to handle pre-existing aliases, consider modifying the script to use `alishow` to check first, or use `alidelete` + `alicreate`. Pull requests welcome!

### What if I want to ADD zones to an existing config rather than CREATE a new one?

Replace `cfgcreate` with `cfgadd` in the script. A future version may support this as a command-line option.

### Is it safe to use sshpass?

`sshpass` is convenient for automation but passes the password on the command line, which may be visible in process listings. For production use, consider:

- SSH key-based authentication
- Wrapping the script with a secrets manager (e.g., HashiCorp Vault, CyberArk)
- Running on a secured jump host with restricted access

### How were the example files generated?

The example files in this repository were derived from actual Connectrix switch outputs (`switchshow`, `nsshow`, `cfgshow`, `configshow`). All identifying information has been anonymized.

---

## Contributing

Contributions are welcome! Here's how you can help:

### Ways to contribute

- **Bug reports** — Found an issue? Open a GitHub Issue with reproduction steps.
- **Feature requests** — Have an idea? Open an Issue describing the use case.
- **Pull requests** — Code contributions are greatly appreciated!
- **Documentation** — Improvements to docs, examples, and guides.
- **Testing** — Test on different FOS/NX-OS versions and report results.

### Pull Request Guidelines

1. **Fork** the repository and create a feature branch
2. **Test** your changes in `--dry-run` mode at minimum
3. **Document** any new features or changed behavior
4. **Follow** the existing code style (Bash best practices, `shellcheck` clean)
5. **Do not** include real switch IPs, passwords, or customer-identifiable data

### Priority areas for contribution

| Area | Description |
|---|---|
| **Cisco MDS support** | `zone_cisco.sh` — port the concept to NX-OS CLI (`device-alias`, `zone`, `zoneset`) |
| **Idempotency** | Check if alias/zone/config already exists before creating |
| **SSH key auth** | Support key-based SSH as alternative to `sshpass` |
| **Multi-switch** | Deploy to multiple switches in a fabric from a single run |
| **Config diff** | Compare desired state (input files) against current switch state |
| **Parser scripts** | Generate input files automatically from `cfgshow` / `switchshow` output |

### Code Quality

Please run [ShellCheck](https://www.shellcheck.net/) before submitting:

```bash
shellcheck zone_brocade.sh
```

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Disclaimer

**USE AT YOUR OWN RISK.**

These scripts modify **production SAN switch configurations**. Incorrect zoning changes can cause **storage outages** and **data unavailability**.

- **Always** run with `--dry-run` first and review every command.
- **Always** test in a lab environment before using in production.
- **Always** have a rollback plan (note the current `cfgshow` output before making changes).
- **Always** ensure you have proper authorization before modifying switch configurations.

The authors and contributors of this repository are **not responsible** for any damage, outage, or data loss caused by the use of these scripts.

This project is **not affiliated with, endorsed by, or supported by Dell Technologies, Broadcom, or Cisco Systems**. "Connectrix" is a trademark of Dell Technologies. "Brocade" is a trademark of Broadcom. "Cisco" and "MDS" are trademarks of Cisco Systems.
