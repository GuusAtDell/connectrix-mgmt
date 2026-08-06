# Contributing to Connectrix SAN Zoning Automation

Thank you for your interest in contributing! This project aims to simplify SAN zoning automation for Dell Connectrix (Brocade and Cisco) switches, and community contributions are essential to making it better.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Getting Started](#getting-started)
- [Development Guidelines](#development-guidelines)
- [Pull Request Process](#pull-request-process)
- [Priority Areas](#priority-areas)
- [Reporting Bugs](#reporting-bugs)
- [Requesting Features](#requesting-features)
- [Style Guide](#style-guide)
- [Testing](#testing)
- [Security](#security)

---

## Code of Conduct

This project follows a simple code of conduct:

- **Be respectful** — Treat all contributors with courtesy and professionalism
- **Be constructive** — Provide helpful feedback and suggestions
- **Be inclusive** — Welcome contributors of all experience levels
- **Be patient** — Maintainers review PRs in their spare time

---

## How Can I Contribute?

| Contribution Type | Description |
|---|---|
| **Bug reports** | Found something broken? Open an Issue |
| **Bug fixes** | Fix a known issue and submit a PR |
| **Feature development** | Implement a new feature (check Priority Areas below) |
| **Documentation** | Improve READMEs, guides, examples, or inline comments |
| **Testing** | Test on different FOS/NX-OS versions and report results |
| **Examples** | Add example input files for different environments |
| **Code review** | Review open PRs and provide feedback |

---

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/connectrix-zoning.git
   cd connectrix-zoning
   ```
3. **Create a feature branch**:
   ```bash
   git checkout -b feature/my-new-feature
   ```
4. **Make your changes** and test them
5. **Commit** with a clear message:
   ```bash
   git commit -m "Add: description of what was added/changed"
   ```
6. **Push** to your fork:
   ```bash
   git push origin feature/my-new-feature
   ```
7. **Open a Pull Request** against the `main` branch

---

## Development Guidelines

### General Rules

- **Do not hardcode** switch IPs, passwords, hostnames, or customer-identifiable data
- **Do not commit** real switch output files, log files, or credentials
- **Use input files** for all configurable data (follow the existing pattern)
- **Maintain backward compatibility** — existing input file formats should continue to work
- **Document** all new features, options, and behavior changes

### Script Structure

Follow the existing script structure:

1. **Configuration variables** at the top
2. **Argument parsing** (support `--long-options`)
3. **Helper functions** (logging, SSH, utilities)
4. **Pre-flight checks** (file existence, tool availability, connectivity)
5. **Main logic** (parse, validate, execute — in that order)
6. **Post-change verification** (show results)

### File Organization

```
connectrix-zoning/
├── README.md              # Main project documentation
├── LICENSE                 # MIT License
├── CONTRIBUTING.md         # This file
├── CONTRIBUTORS.md         # List of contributors
├── brocade/
│   ├── zone_brocade.sh    # Main Brocade script
│   └── examples/          # Example input files
├── cisco/
│   ├── zone_cisco.sh      # Main Cisco MDS script
│   └── examples/          # Example input files
└── docs/
    ├── FILE_FORMATS.md    # Input file format reference
    ├── VALIDATION.md      # Validation logic explained
    └── TROUBLESHOOTING.md # Common issues and solutions
```

---

## Pull Request Process

1. **Test your changes** — At minimum, run with `--dry-run` and verify output
2. **Run ShellCheck** — Ensure no linting warnings:
   ```bash
   shellcheck zone_brocade.sh
   ```
3. **Update documentation** — If you add/change options or behavior, update:
   - The script's header comment block
   - The relevant docs/ files
   - The README.md if applicable
4. **Write a clear PR description** including:
   - What the change does
   - Why it's needed
   - How it was tested
   - Any breaking changes
5. **One feature per PR** — Keep PRs focused and reviewable
6. **Respond to review feedback** — Maintainers may request changes

### PR Title Format

Use a clear, descriptive title:

- `Add: Cisco MDS support`
- `Fix: Handle trailing whitespace in zone file members`
- `Improve: Add SSH key authentication option`
- `Docs: Update troubleshooting for FOS 9.x`

---

## Priority Areas

The following areas are most needed. If you're looking for something to work on, start here:

### High Priority

| Area | Description | Difficulty |
|---|---|---|
| **Cisco MDS support** | Create `zone_cisco.sh` using NX-OS CLI (`device-alias`, `zone`, `zoneset`, `zone commit`) | Medium-High |
| **Idempotency** | Check if alias/zone/config already exists before creating. Support `--force` to recreate | Medium |
| **SSH key authentication** | Support key-based SSH as an alternative to sshpass | Low-Medium |

### Medium Priority

| Area | Description | Difficulty |
|---|---|---|
| **Multi-switch deployment** | Run against multiple switches from a single execution (e.g., both fabric A and B switches) | Medium |
| **Config diff** | Compare desired state (input files) vs. current switch state before making changes | Medium-High |
| **Parser/generator scripts** | Auto-generate input files from `cfgshow` or `configshow` output | Medium |
| **cfgadd support** | Option to add zones to an existing config instead of creating new (`--mode add`) | Low |

### Low Priority

| Area | Description | Difficulty |
|---|---|---|
| **Interactive mode** | Prompt for confirmation before each command (not just cfgsave/cfgenable) | Low |
| **Rollback script** | Generate a rollback script from the log file | Medium |
| **JSON/YAML input** | Support structured input formats as alternative to current text format | Medium |
| **Unit tests** | Bash-based test framework (e.g., bats-core) for parser functions | Medium |

---

## Reporting Bugs

When opening a bug report, include:

1. **Script version** — Which commit hash or release
2. **Environment** — OS, Bash version (`bash --version`), sshpass version
3. **Switch model and FOS/NX-OS version** — `firmwareshow` output
4. **Steps to reproduce** — What commands you ran
5. **Expected behavior** — What should have happened
6. **Actual behavior** — What actually happened (include error messages)
7. **Log file** — Attach the timestamped log file (redact sensitive information)
8. **Input files** — Attach sanitized versions if relevant (replace real WWNs/hostnames)

### Bug Report Template

```
**Environment:**
- OS: Ubuntu 22.04
- Bash: 5.1.16
- sshpass: 1.09
- Switch: DS-6620B, FOS 9.1.1

**Steps to reproduce:**
1. Created aliases.txt with ...
2. Ran: ./zone_brocade.sh --dry-run
3. ...

**Expected behavior:**
Script should ...

**Actual behavior:**
Script fails with ...

**Error output:**
(paste relevant log lines here)
```

---

## Requesting Features

When opening a feature request, include:

1. **Use case** — What problem does this solve?
2. **Proposed solution** — How should it work?
3. **Alternatives considered** — What other approaches did you think about?
4. **Impact** — Does this affect existing functionality or file formats?

---

## Style Guide

### Bash Scripting

- Use `#!/bin/bash` shebang (not `#!/bin/sh`)
- Enable strict mode: `set -euo pipefail`
- Quote all variables: `"${VAR}"` not `$VAR`
- Use `[[ ]]` for conditionals (not `[ ]`)
- Use `$(command)` for command substitution (not backticks)
- Use `local` for function variables
- Use descriptive variable names in UPPER_CASE for globals, lower_case for locals
- Add comments for non-obvious logic
- Keep functions focused — one function, one purpose

### ShellCheck Compliance

All scripts must pass ShellCheck without warnings:

```bash
shellcheck -x zone_brocade.sh
```

If a ShellCheck warning must be suppressed, add a comment explaining why:

```bash
# shellcheck disable=SC2034  # Variable is used in sourced file
MY_VAR="value"
```

### Commit Messages

- Use present tense: "Add feature" not "Added feature"
- Use imperative mood: "Fix bug" not "Fixes bug"
- Keep the first line under 72 characters
- Reference issue numbers where applicable: "Fix: Handle CRLF in alias files (#42)"

---

## Testing

### Minimum Testing Requirements

Before submitting a PR:

1. **Dry-run test** — Run with `--dry-run` and verify all commands are correct
2. **Validation test** — Intentionally introduce an error in an input file and verify the script catches it
3. **ShellCheck** — Zero warnings
4. **Both LF and CRLF** — Test with both Unix and Windows line endings if your change touches the file parser

### Testing on Real Switches

If you have access to a lab switch:

1. Run the full script against a test switch
2. Verify with `cfgshow` that the configuration matches the input files
3. Test error recovery — cancel midway and verify switch state

### Automated Tests (Future)

We plan to adopt [bats-core](https://github.com/bats-core/bats-core) for automated testing. Contributions in this area are very welcome.

---

## Security

### Reporting Security Issues

If you discover a security vulnerability, **do not open a public issue**. Instead:

1. Contact the maintainer privately via GitHub (use the Security tab if available)
2. Describe the vulnerability and potential impact
3. Allow reasonable time for a fix before public disclosure

### Security Guidelines for Contributors

- **Never commit credentials** — Not even "example" passwords that might be real
- **Never commit real switch output** — Sanitize all hostnames, IPs, and WWNs
- **Avoid command injection** — All user input passed to SSH commands should be validated
- **Use single quotes** around SSH commands to prevent local shell expansion
