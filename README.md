# cmdclip 📋

> A smart, cross-platform command clipboard manager for the terminal.
> Built by [M5 Dev](https://github.com/M5Develop) — GPL-3.0

---

## Why cmdclip?

`history` is short. `grep` is tedious. `pet` is Go-only.  
**cmdclip** is Python, works on Linux / macOS / Windows, and has AI built in.

---

## Install

```bash
pip install cmdclip
```

---

## Quick start

```bash
# Save a command
cmdclip add "docker ps -a --format '{{.Names}}'" --tags docker,ops --note "list container names"

# List all
cmdclip list

# Search
cmdclip search docker

# Run by ID
cmdclip run a3f9

# Dry-run with AI explanation
cmdclip run a3f9 --dry-run

# AI explain any saved command
cmdclip explain a3f9

# Import from shell history (smart — picks commands used 5+ times)
cmdclip history

# Export / import
cmdclip export --output backup.json
cmdclip import backup.json --safe

# Share as a snippet (copies to clipboard)
cmdclip share a3f9

# Usage stats
cmdclip stats
```

---

## AI features (Groq)

```bash
# Save your Groq API key once
cmdclip config set-key gsk_xxxxxxxxxxxx

# Now add / explain / dry-run all use AI automatically
```

Get a free key at [console.groq.com](https://console.groq.com).

---

## Command templates

Use `{variable}` or `{variable=default}` syntax:

```bash
cmdclip add "ssh {user}@{host} -p {port=22}" --name ssh-connect
cmdclip run <id>
# Fill in: user? host? port [22]?
```

---

## Safe mode

Import with `--safe` to automatically quarantine dangerous commands  
(`rm -rf`, `sudo rm`, `DROP TABLE`, etc.) into a separate file.

```bash
cmdclip import backup.json --safe
```

---

## Cross-platform paths

| OS | Data directory |
|----|---------------|
| Linux / macOS | `~/.cmdclip/` |
| Windows | `%LOCALAPPDATA%\cmdclip\` |

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE)  
© M5 Dev
