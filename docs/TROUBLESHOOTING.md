# Troubleshooting Guide

This document covers common issues, error messages, and solutions when using the Connectrix zoning automation scripts.

---

## Table of Contents

- [Connection Issues](#connection-issues)
- [sshpass Issues](#sshpass-issues)
- [Input File Errors](#input-file-errors)
- [Switch Command Failures](#switch-command-failures)
- [Bash Compatibility](#bash-compatibility)
- [Windows-Specific Issues](#windows-specific-issues)
- [Recovery Procedures](#recovery-procedures)

---

## Connection Issues

### Error: `ssh: connect to host X.X.X.X port 22: Connection timed out`

**Cause:** No network path to the switch on TCP port 22.

**Solutions:**
1. Verify the switch IP address is correct
2. Check that you can ping the switch: `ping <switch_ip>`
3. Verify no firewall is blocking SSH (port 22) between your machine and the switch
4. Confirm SSH is enabled on the switch: connect via serial console and run `sshutil`
5. Check if the switch management interface is on a different VLAN or subnet

### Error: `ssh: connect to host X.X.X.X port 22: Connection refused`

**Cause:** SSH service is not running on the switch.

**Solutions:**
1. Connect via serial console
2. Run `sshutil` to check SSH status
3. Enable SSH if disabled: `sshutil allowpubkey` or check FOS admin guide

### Error: `Host key verification failed`

**Cause:** The switch's SSH host key doesn't match what's stored in `known_hosts`.

**Solutions:**
- The script uses `-o StrictHostKeyChecking=no` and `-o UserKnownHostsFile=/dev/null` to bypass this. If you still see this error, your SSH configuration may be overriding these options.
- Check `~/.ssh/config` for conflicting `StrictHostKeyChecking` settings
- Manually remove the old key: `ssh-keygen -R <switch_ip>`

### Error: `Permission denied (password)`

**Cause:** Wrong username or password.

**Solutions:**
1. Verify credentials by logging in manually: `ssh admin@<switch_ip>`
2. Check that the password doesn't contain special characters that need escaping in your shell
3. If the password contains single quotes, modify the `SWITCH_PASS` variable in the script to use different quoting

---

## sshpass Issues

### Error: `sshpass: command not found`

**Cause:** sshpass is not installed.

**Solutions:**

| OS | Install Command |
|---|---|
| Debian / Ubuntu | `sudo apt install sshpass` |
| RHEL / CentOS 7 | `sudo yum install sshpass` |
| RHEL / CentOS 8+ / Fedora | `sudo dnf install sshpass` |
| macOS | `brew install hudochenkov/sshpass/sshpass` |
| Windows (WSL) | `sudo apt install sshpass` |

### Error: `sshpass: Invalid option` or unexpected behavior

**Cause:** Old version of sshpass.

**Solution:** Upgrade to the latest version. Check version with `sshpass -V`.

### Security warning about sshpass

sshpass passes the password via the command line, which may be visible in `/proc` or `ps` output. For production environments, consider:

- SSH key-based authentication (modify the script to remove sshpass calls)
- Running the script on a secured jump host
- Using a secrets manager

---

## Input File Errors

### Error: `Input file not found: aliases.txt`

**Cause:** The script can't find the input file in the current directory.

**Solutions:**
1. Ensure you're running the script from the correct directory
2. Use absolute or relative paths: `--alias-file /path/to/aliases.txt`
3. Verify the file exists: `ls -la aliases.txt`

### Error: `WWN found on line X without preceding alias: line`

**Cause:** The alias file has a WWN line that isn't preceded by an `alias:` line.

**Solution:** Check the file around the indicated line number. Ensure every WWN has an `alias:` line directly above it.

### Error: `Alias 'X' has no corresponding WWN`

**Cause:** An `alias:` line at the end of the file (or before another `alias:` line) has no WWN following it.

**Solution:** Add the missing WWN or remove the incomplete alias entry.

### Error: `WARNING: Unrecognized line`

**Cause:** A line in the file doesn't match the expected `alias:` or WWN format.

**Common causes:**
- Extra spaces inside the WWN (e.g., `10:00:00:10: 9b:33:b3:a7`)
- Truncated WWN (fewer than 8 octets)
- Copy-paste artifacts (invisible Unicode characters)
- Windows line endings on some lines but not others

**Solution:** Open the file in a hex editor or run `cat -A aliases.txt` to check for hidden characters. Retype the problematic line.

### Error: `VALIDATION ERROR: Zone references alias which was NOT defined`

**Cause:** A zone member name in `zones.txt` doesn't match any alias created from `aliases.txt`.

**Common causes:**
- Typo in the alias name (in either file)
- Missing alias entry in `aliases.txt`
- Extra whitespace in the alias name

**Solution:** Compare the exact alias name in the error message against `aliases.txt`. Use `grep` to search: `grep '<alias_name>' aliases.txt`

### Error: `Multiple configs found`

**Cause:** The config file contains more than one `cfg:` line.

**Solution:** Keep only one `cfg:` line per file. If you need multiple configs, use separate files and separate script runs.

---

## Switch Command Failures

### Error: `!!! COMMAND FAILED: alicreate ...`

**Common causes and solutions:**

| Switch Error Message | Cause | Solution |
|---|---|---|
| `duplicate name` | Alias already exists | Delete first: `alidelete '<name>'`, or skip existing aliases |
| `invalid name` | Name contains invalid characters or exceeds 64 chars | Rename the alias in your input file |
| `maximum number of aliases exceeded` | Switch alias table is full | Delete unused aliases first |
| `not a valid command` | FOS version doesn't support this command | Check FOS version: `firmwareshow` |

### Error: `!!! COMMAND FAILED: zonecreate ...`

| Switch Error Message | Cause | Solution |
|---|---|---|
| `duplicate name` | Zone already exists | Delete first: `zonedelete '<name>'` |
| `member does not exist` | An alias member wasn't created | Check alias creation output for errors |

### Error: `!!! COMMAND FAILED: cfgcreate ...`

| Switch Error Message | Cause | Solution |
|---|---|---|
| `duplicate name` | Config already exists | Delete first: `cfgdelete '<name>'`, or use `cfgadd` to add zones to existing config |
| `zone does not exist` | A zone member wasn't created | Check zone creation output for errors |

### Error: `!!! COMMAND FAILED: cfgsave`

| Switch Error Message | Cause | Solution |
|---|---|---|
| `nothing changed` | No changes to save | Not an error — config was already saved |
| `fabric busy` | Another operation is in progress | Wait and retry |

### Error: `!!! COMMAND FAILED: cfgenable ...`

| Switch Error Message | Cause | Solution |
|---|---|---|
| `config does not exist` | Config wasn't created/saved | Check cfgcreate and cfgsave output |
| `zone DB full` | Too many zones in the config | Reduce zone count or upgrade switch |

---

## Bash Compatibility

### Error: `declare: -A: invalid option`

**Cause:** You're running Bash 3.x, which doesn't support associative arrays (`declare -A`).

**Solutions:**
- **Linux:** Usually not an issue (Bash 4+ is standard). Check with `bash --version`
- **macOS:** macOS ships with Bash 3.2. Install Bash 4+: `brew install bash`, then run the script with `/usr/local/bin/bash zone_brocade.sh` or update your PATH
- **Windows WSL:** Usually Bash 4+. Check with `bash --version`

### Error: `set: pipefail: invalid option name`

**Cause:** Running with a non-Bash shell (e.g., `sh`, `dash`).

**Solution:** Run explicitly with Bash: `bash zone_brocade.sh --dry-run`

---

## Windows-Specific Issues

### WSL (Windows Subsystem for Linux) — Recommended

- Install WSL: `wsl --install` (PowerShell as admin)
- Install sshpass: `sudo apt install sshpass`
- Navigate to your files: `cd /mnt/c/Users/<username>/path/to/files`
- Line endings: If files were created on Windows, convert them: `dos2unix aliases.txt zones.txt config.txt`

### Git Bash

- sshpass is not included by default. You'll need to compile it or find a pre-built binary
- Alternatively, use WSL instead

### Cygwin

- Install the `sshpass` and `openssh` packages via the Cygwin installer
- File paths use Cygwin notation: `/cygdrive/c/Users/...`

### Line Ending Issues

Windows uses CRLF (`\r\n`) line endings. The script handles these in most cases, but if you see unexpected errors:

```bash
# Check for Windows line endings
file aliases.txt
# Output containing "CRLF" indicates Windows endings

# Convert to Unix line endings
dos2unix aliases.txt zones.txt config.txt

# Or use sed
sed -i 's/\r$//' aliases.txt zones.txt config.txt
```

---

## Recovery Procedures

### If the script fails partway through

The script uses `set -euo pipefail` and aborts on the first failed SSH command. This means:

1. **Some aliases may have been created** but not all
2. **Some zones may have been created** but not all
3. **cfgsave may NOT have been run** — meaning changes are in volatile memory only

**To check current state:**

```bash
ssh admin@<switch_ip> "cfgshow"
```

**To clear uncommitted changes (revert to last saved config):**

```bash
ssh admin@<switch_ip> "cfgclear"
```

> WARNING: `cfgclear` removes ALL unsaved zoning changes from volatile memory. This is safe if `cfgsave` was never run during the failed script execution.

**To remove specific items:**

```bash
ssh admin@<switch_ip> "alidelete '<alias_name>'"
ssh admin@<switch_ip> "zonedelete '<zone_name>'"
ssh admin@<switch_ip> "cfgdelete '<config_name>'"
ssh admin@<switch_ip> "cfgsave"  # Save the deletions
```

### If cfgenable activated a bad config

If the wrong configuration was enabled and is causing issues:

```bash
# Re-enable the previous configuration
ssh admin@<switch_ip> "cfgenable '<previous_config_name>'"

# Or disable all zoning (DANGEROUS — allows all-to-all access)
ssh admin@<switch_ip> "cfgdisable"
```

> Always note the current effective configuration (`cfgshow`) BEFORE running the script so you can roll back if needed.

### Best practice: Pre-change backup

Before running the script, capture the current state:

```bash
ssh admin@<switch_ip> "cfgshow; echo '===CONFIGSHOW==='; configshow" > pre_change_backup_$(date +%Y%m%d_%H%M%S).txt
```

This gives you a complete record to restore from if anything goes wrong.
